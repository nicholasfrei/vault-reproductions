# Prometheus Negative Counter Panic (VAULT-46830)

## Overview

Vault Enterprise panics at startup with `panic: counter cannot decrease in value` when Prometheus
telemetry is enabled and any metric code path emits a negative value to a Prometheus counter.

This is two independent problems: a missing defensive guard in Vault's telemetry layer, 
and an unidentified code path that produces a negative counter value. This article explains 
both, traces the exact call chain, and shows the panic mechanically using the same library 
versions Vault 1.19.8-ent ships.

### Affected versions

Confirmed customer-impacted: `1.19.8+ent.hsm`. Affected: any Vault Enterprise release with
`prometheus_retention_time` configured that has not received the `guardedPrometheusSink` fix.

### Symptoms

- Vault crashes immediately after the configuration is loaded, before unsealing.
- Removing or commenting out the `telemetry` stanza (specifically `prometheus_retention_time`,
  `disable_hostname`, `enable_hostname_label`) allows Vault to start cleanly.
- The panic only surfaced after multiple unclean VM restarts across DR/PR cluster nodes.

### Exact panic string

```text
panic: counter cannot decrease in value
```

---

## The call chain

The panic travels through three layers. Each one is documented below with the exact source
location.

### Layer 1 — where the panic fires

**`prometheus/client_golang@v1.20.5/prometheus/counter.go:126`**

```go
func (c *counter) Add(v float64) {
    if v < 0 {
        panic(errors.New("counter cannot decrease in value"))
    }
    ...
}
```

Prometheus requires counters to be non-decreasing. The client library
enforces this with an unconditional panic. There is no option to disable it.

### Layer 2 — the missing guard in armon/go-metrics v0.4.1

**`armon/go-metrics@v0.4.1/prometheus/prometheus.go:362`**

```go
func (p *PrometheusSink) IncrCounterWithLabels(parts []string, val float32, labels []metrics.Label) {
    key, hash := flattenKey(parts, labels)
    pc, ok := p.counters.Load(hash)

    if ok {
        localCounter := *pc.(*counter)
        localCounter.Add(float64(val))  // no check — panics if val < 0
        ...
    } else {
        c := prometheus.NewCounter(...)
        c.Add(float64(val))             // also panics if val < 0
        ...
    }
}
```

Both branches call `Counter.Add()` unconditionally. There is no guard on `val`. The `ok == true`
branch (counter already exists in the registry) is the path the customer hit. The `ok == false`
branch (first time this counter is seen) also panics with a negative value.

`IncrCounter` is a one-liner that delegates straight to `IncrCounterWithLabels`:

**`armon/go-metrics@v0.4.1/prometheus/prometheus.go:359`**

```go
func (p *PrometheusSink) IncrCounter(parts []string, val float32) {
    p.IncrCounterWithLabels(parts, val, nil)
}
```

### Layer 3 — the unguarded Vault call site

**`internalshared/configutil/telemetry.go` (`release/1.19.x+ent`)**

```go
sink, err := prometheus.NewPrometheusSinkFrom(prometheusOpts)
if err != nil {
    return nil, nil, false, err
}
fanout = append(fanout, sink)  // raw sink, no wrapper
```

The raw `PrometheusSink` is added directly to the `metrics.FanoutSink`. Every call to
`IncrCounter` or `IncrCounterWithLabels` anywhere in Vault flows through this sink without
any interception. One negative value anywhere in the codebase crashes the process.

---

## Demonstrating the panic

The following program uses the exact library versions Vault 1.19.8-ent ships and reproduces the
panic in under a second. No cluster required.

```bash
mkdir -p /tmp/vault-46830-repro

cat <<'EOF' > /tmp/vault-46830-repro/main.go
package main

import (
	"fmt"

	armonPrometheus "github.com/armon/go-metrics/prometheus"
	"github.com/prometheus/client_golang/prometheus"
)

func main() {
	registry := prometheus.NewRegistry()
	sink, err := armonPrometheus.NewPrometheusSinkFrom(armonPrometheus.PrometheusOpts{
		Expiration: 0,
		Registerer: registry,
		Name:       "vault_repro",
	})
	if err != nil {
		panic(err)
	}

	// Step 1: seed the counter positive — this is normal Vault operation
	fmt.Println("seeding vault_raft_storage_bolt_write_time counter at +42")
	sink.IncrCounter([]string{"vault", "raft_storage", "bolt", "write", "time"}, 42)
	fmt.Println("  OK")

	// Step 2: increment with a negative value — triggers the panic
	fmt.Println("calling IncrCounter with val=-10 ...")
	sink.IncrCounter([]string{"vault", "raft_storage", "bolt", "write", "time"}, -10)
	fmt.Println("  never reached")
}
EOF

cd /tmp/vault-46830-repro
go mod init vault-46830-repro
go get github.com/armon/go-metrics@v0.4.1
go get github.com/armon/go-metrics/prometheus@v0.4.1
go get github.com/prometheus/client_golang@v1.20.5
go mod tidy
go run main.go
```

Output:

```text
seeding vault_raft_storage_bolt_write_time counter at +42
  OK
calling IncrCounter with val=-10 ...
panic: counter cannot decrease in value

goroutine 1 [running]:
github.com/prometheus/client_golang/prometheus.(*counter).Add(...)
        .../prometheus/client_golang@v1.20.5/prometheus/counter.go:128
github.com/armon/go-metrics/prometheus.(*PrometheusSink).IncrCounterWithLabels(...)
        .../armon/go-metrics@v0.4.1/prometheus/prometheus.go:370
github.com/armon/go-metrics/prometheus.(*PrometheusSink).IncrCounter(...)
        .../armon/go-metrics@v0.4.1/prometheus/prometheus.go:360
main.main()
        .../main.go:30
exit status 2
```

---

## The fix

**`internalshared/configutil/telemetry.go`** (`origin/VAULT-46830/add-prometheus-guard`, commit `c142c4f73a`)

The raw sink is replaced with a `guardedPrometheusSink` wrapper:

```go
// before (affected)
sink, err := prometheus.NewPrometheusSinkFrom(prometheusOpts)

// after (fixed)
sink, err := newGuardedPrometheusSink(prometheusOpts)
```

`guardedPrometheusSink` checks `val >= 0` before delegating, and logs a drop instead of
panicking:

```go
func (s *guardedPrometheusSink) dropNegativeCounterIncrement(parts []string, val float32, labels []metrics.Label) bool {
    if val >= 0 {
        return false
    }
    log.Printf("telemetry: dropping negative prometheus counter increment parts=%q value=%v labels=%s",
        formatMetricParts(parts), val, formatMetricLabels(labels))
    return true
}
```

The same guard and log pattern applies to both `IncrCounter` and `IncrCounterWithLabels`.

---

## All non-literal IncrCounter call sites in vault-enterprise

The panic requires a computed (non-`1`) value to go negative. Every `IncrCounter` /
`IncrCounterWithLabels` call in the vault-enterprise codebase that passes a variable — not a
literal `1` — is listed here with an assessment of whether it can go negative.

### `physical/raft/raft.go:957` — `raft_storage_bolt_write_time`

```go
sink.IncrCounterWithLabels(
    []string{"raft_storage", "bolt", "write", "time"},
    float32(txstats.GetWriteTime().Milliseconds()),
    labels,
)
```

`GetWriteTime()` returns a cumulative `time.Duration` accumulated via `time.Since(startTime)` on
each bbolt commit (`go.etcd.io/bbolt@v1.4.0/tx.go:272`). Under normal conditions this is always
positive. However, `time.Since` uses the monotonic clock. If the VM clock is stepped backward
(NTP correction, hypervisor clock sync during live migration or VM resume) between `startTime`
capture and the `time.Since` call, the duration is negative. That negative accumulates in
`TxStats.WriteTime` via an atomic int64 add, making `GetWriteTime().Milliseconds()` negative on
the next metrics collection tick.

This is the most credible trigger for the customer's scenario: multiple unclean VM restarts in a
DR/PR cluster are frequently accompanied by clock correction events on resume.

**Can go negative: yes, on VM clock step-down during a bbolt commit.**

### `builtin/logical/pki/path_tidy.go:1874-1875` — PKI tidy deleted counts

```go
metrics.IncrCounter([]string{"secrets", "pki", "tidy", "cert_store_deleted_count"},
    float32(b.tidyStatus.certStoreDeletedCount))
metrics.IncrCounter([]string{"secrets", "pki", "tidy", "revoked_cert_deleted_count"},
    float32(b.tidyStatus.revokedCertDeletedCount))
```

Both fields are declared as `uint` (`builtin/logical/pki/backend.go:70-71`). `uint` cannot be
negative and the `float32` cast of a non-negative uint cannot produce a negative float32 within
the range of values a cert count could realistically reach.

**Can go negative: no.**

### `vault/logical_system_sync_telemetry_ent.go:198` — secrets-sync reconciliation corrections

```go
totalCorrections := numToSync + numToUnsync
b.core.metricSink.IncrCounterWithLabels(
    []string{"secrets-sync", "reconciliation", "correction"},
    float32(totalCorrections),
    labels,
)
```

`numToSync` and `numToUnsync` are set from `len(diffs.ToSync)` and `len(diffs.ToUnsync)`
(`vault/logical_system_sync_queue_ent.go:259-260`). `len()` always returns >= 0 in Go.

**Can go negative: no.**

### `vault/activity_log.go:417,422` and `vault/activity_log_util_ent.go:40,49` — activity fragment size

```go
a.metrics.IncrCounterWithLabels(
    []string{"core", "activity", "fragment_size"},
    float32(len(localFragment.Clients)),
    ...
)
```

`len()` always returns >= 0.

**Can go negative: no.**

### `audit/broker.go:270,337` — audit log failure

```go
metricVal := float32(0.0)
if retErr != nil {
    metricVal = 1.0
}
metrics.IncrCounter([]string{"audit", "log_request_failure"}, metricVal)
```

Only ever 0.0 or 1.0.

**Can go negative: no.**

---

## Fix location

| Item | Detail |
|---|---|
| File | `internalshared/configutil/telemetry.go` |
| Functions added | `guardedPrometheusSink`, `newGuardedPrometheusSink`, `dropNegativeCounterIncrement` |
| Call site changed | `SetupTelemetry()` — `prometheus.NewPrometheusSinkFrom` → `newGuardedPrometheusSink` |
| Fix branch (`main`) | `origin/VAULT-46830/add-prometheus-guard` — commit `c142c4f73a` |
| Fix branch (`1.19.x`) | `origin/VAULT-46830/fix-telemetry-panic` — commit `4bc8e900d9` |
| Test | `internalshared/configutil/telemetry_test.go` — `TestGuardedPrometheusSinkDropsNegativeCounterIncrements` |

## References

- `internalshared/configutil/telemetry.go` — `SetupTelemetry()`, `newGuardedPrometheusSink()`
- `physical/raft/raft.go:957` — `raft_storage_bolt_write_time`, the only non-literal counter call
- `go.etcd.io/bbolt@v1.4.0/tx.go:272` — `IncWriteTime(time.Since(startTime))`
- `armon/go-metrics@v0.4.1/prometheus/prometheus.go:362` — `IncrCounterWithLabels`, no guard on `val`
- `prometheus/client_golang@v1.20.5/prometheus/counter.go:126` — `Counter.Add()`, panics when `val < 0`
- `builtin/logical/pki/backend.go:70` — `certStoreDeletedCount uint`
- `vault/logical_system_sync_queue_ent.go:259` — `numToSync := len(diffs.ToSync)`
- Prometheus data model — counter monotonicity: https://prometheus.io/docs/concepts/metric_types/#counter
- Vault telemetry configuration: https://developer.hashicorp.com/vault/docs/configuration/telemetry
