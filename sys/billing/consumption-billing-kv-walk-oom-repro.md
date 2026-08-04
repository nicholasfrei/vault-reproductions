# Consumption Billing KV Walk OOM Repro

## Overview

Vault 2.0.x introduced an unconditional background worker (`consumptionBillingMetricsWorker`) that
runs on the active node every 10 minutes and walks every key in every KV v2 mount to count secrets
for billing metrics. On a small store the cost is invisible. On a large store the walk floods the
physical storage read cache, driving active-node memory up by tens of megabytes per minute until
the process is OOM killed.

Last log line before OOM (always the same, appears in `vault.log` or stdout):

```text
core: updated replicated hwm role and managed key counts: prefix=replicated/
```

The next expected line (`updated replicated max kv counts`) never appears because the process dies
during the KV enumeration that follows.

On Vault 1.21.3 the billing worker is not present and the lines above never appear.

## Objective

Observe active-node memory growth caused by the 10-minute billing tick on a KV-heavy store, and
confirm the behavior is absent on Vault 1.21.3.

## Prerequisites

- Podman (Podman Desktop or the `podman` CLI)
- `vault` CLI (any version, used only to write secrets)
- `jq` (optional)
- At least 2 GB of free memory on the host
- A terminal that can tail container logs (`podman logs -f`)

The repro uses a single Vault container with the `mysql` storage backend so the `ha_enabled`
path is exercised and the active-node billing worker runs, matching the original report. MariaDB is
used as a drop-in replacement because it is available on every platform as an official container image.

## Step 1: Create the Podman network and start MariaDB

```bash
podman network create vault-billing-repro

podman run -d \
  --name mariadb \
  --network vault-billing-repro \
  -e MYSQL_ROOT_PASSWORD=vaultpass \
  -e MYSQL_DATABASE=vault \
  -e MYSQL_USER=vault \
  -e MYSQL_PASSWORD=vaultpass \
  mariadb:11
```

Wait for MariaDB to finish initializing (about 10–15 seconds):

```bash
podman logs -f mariadb 2>&1 | grep -m1 "ready for connections"
```

Expected output:

```text
... [Note] mariadbd: ready for connections.
```

Press `Ctrl-C` after the line appears.

## Step 2: Write the Vault config

```bash
mkdir -p ~/vault-billing-repro

cat > ~/vault-billing-repro/vault.hcl <<'EOF'
storage "mysql" {
  address     = "mariadb:3306"
  username    = "vault"
  password    = "vaultpass"
  database    = "vault"
  ha_enabled  = "true"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = true
}

api_addr      = "http://0.0.0.0:8200"
disable_mlock = true
ui            = false
EOF
```

## Step 3: Start Vault 2.0.3

```bash
podman run -d \
  --name vault-2-0-3 \
  --network vault-billing-repro \
  --cap-add=IPC_LOCK \
  -p 8200:8200 \
  -v ~/vault-billing-repro/vault.hcl:/vault/config/vault.hcl \
  hashicorp/vault:2.0.3 \
  vault server -config=/vault/config/vault.hcl
```

## Step 4: Initialize and unseal

```bash
export VAULT_ADDR='http://127.0.0.1:8200'

sleep 5

vault operator init -key-shares=1 -key-threshold=1 -format=json \
  > ~/vault-billing-repro/init.json

UNSEAL_KEY=$(jq -r '.unseal_keys_b64[0]' ~/vault-billing-repro/init.json)
ROOT_TOKEN=$(jq -r '.root_token'          ~/vault-billing-repro/init.json)

vault operator unseal "${UNSEAL_KEY}"
export VAULT_TOKEN="${ROOT_TOKEN}"
```

Confirm the node is active:

```bash
vault status
```

Expected output (relevant fields):

```text
Key             Value
---             -----
Seal Type       shamir
Initialized     true
Sealed          false
HA Enabled      true
HA Cluster      http://127.0.0.1:8201
HA Mode         active
```

## Step 5: Enable a KV v2 mount and write a large number of secrets

Enable the mount:

```bash
vault secrets enable -path=secret kv-v2

seq 1 60000 | xargs -P 10 -I{} \
  vault kv put secret/repro/{} \
    key1="$(head -c 512 /dev/urandom | base64)" \
    key2="$(head -c 512 /dev/urandom | base64)"
```

This takes several minutes. To track progress:

```bash
vault kv list secret/repro | wc -l
```

## Step 6: Record baseline memory

After all secrets are written, wait for Vault to settle (30 seconds), then record the baseline
resident set size:

```bash
podman stats --no-stream vault-2-0-3
```

Expected output (example — exact values vary):

```text
ID            NAME         CPU %   MEM USAGE / LIMIT   MEM %   NET I/O       BLOCK I/O
<id>          vault-2-0-3  0.20%   62MiB / 7.77GiB     0.78%   1.4MB / 2MB   0B / 0B
```

Note the `MEM USAGE` value.

## Step 7: Watch memory and logs across the 10-minute billing tick

Open two terminals.

Terminal 1 — tail Vault logs and watch for the billing lines:

```bash
podman logs -f vault-2-0-3 2>&1 | grep -E "billing|kv count|hwm|max kv"
```

Terminal 2 — poll memory every 30 seconds:

```bash
while true; do
  printf "%s  " "$(date +%H:%M:%S)"
  podman stats --no-stream vault-2-0-3 \
    --format "{{.MemUsage}}"
  sleep 30
done
```

Wait up to 10 minutes. When the billing worker runs you will see:

```text
core: updated replicated hwm role and managed key counts: prefix=replicated/
```

Immediately after that line, memory climbs at roughly 50–100 MiB per minute depending on KV store
size. With 60,000 secrets and 2 KB values the container typically reaches
300–400 MiB before the walk completes or the container is OOM killed.

Sample memory timeline from a 60,000-secret store:

```text
12:04:00   62MiB    leader, flat before billing tick
12:14:30   65MiB    billing tick starts (hwm log line appears)
12:15:00  138MiB
12:15:30  231MiB
12:16:00  312MiB
12:16:30  OOM / or walk completes and GC recovers over ~2 minutes
```

## Step 8: Confirm with 1.21.3

Stop the 2.0.3 container and run the same test with 1.21.3 to confirm the worker is absent:

```bash
podman rm -f vault-2-0-3
```

Start Vault 1.21.3 against the same MariaDB database (the schema is compatible):

```bash
podman run -d \
  --name vault-1-21-3 \
  --network vault-billing-repro \
  --cap-add=IPC_LOCK \
  -p 8200:8200 \
  -v ~/vault-billing-repro/vault.hcl:/vault/config/vault.hcl \
  hashicorp/vault:1.21.3 \
  vault server -config=/vault/config/vault.hcl
```

Unseal using the same key:

```bash
sleep 5
vault operator unseal "${UNSEAL_KEY}"
```

Monitor logs and memory for 10 minutes:

```bash
podman logs -f vault-1-21-3 2>&1 | grep -E "billing|kv count|hwm|max kv"
```

The billing worker lines do not appear and memory stays flat. The grep produces no output.

## Validation

The repro is confirmed when all of the following are true on Vault 2.0.3:

- The log line `updated replicated hwm role and managed key counts: prefix=replicated/` appears approximately 10 minutes after the node acquires leadership.
- `podman stats` shows memory growing immediately after that line.
- `podman stats` shows memory returning toward baseline only after the walk completes (may take several minutes) or after the container is OOM killed.

The repro is confirmed absent on Vault 1.21.3 when:

- No `hwm` or `billing` log lines appear.
- Memory stays within a few MiB of the baseline for the full observation window.

## Cleanup

```bash
podman rm -f vault-2-0-3 vault-1-21-3 mariadb
podman network rm vault-billing-repro
rm -rf ~/vault-billing-repro
```

## References

- `vault/billing/billing_counts.go` — `BillingWriteInterval = 10 * time.Minute`
- `vault/consumption_billing.go` — `consumptionBillingMetricsWorker`, `postUnsealFuncs`
- `vault/consumption_billing_util.go` — `UpdateMaxKvCounts`, `GetKvUsageMetricsByNamespace`
- `vault/core_metrics.go` — `walkKvMountSecrets`
- `sdk/physical/cache.go` — default `cache_size = 131072`
