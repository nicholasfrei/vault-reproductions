# Consul Health Check Misconfiguration Amplifying a Leadership Election Cascade

## Overview

This article documents a production incident where a very large enterprise Vault customer experienced an outage following a planned maintenance event. The event totaled less than 10 minutes, but the customer wanted to understand why the outage occurred and how to prevent it in the future. The first suspicion was related to the audit sink in Vault, since the error message `event not processed by enough sink nodes ... context deadline exceeded` was observed in the logs. We suspected a potential bottleneck in the audit sink process in Vault; however, after investigation, the root cause turned out to be the Consul service registration that unintentionally removed all performance standbys from the load balancer pool during the maintenance window and created unnecessary load on the active node during initialization.

I want to discuss a few key mechanisms of Vault that contributed to this outage and share some of my learnings.

## Environment

| Item | Value |
|------|-------|
| Vault version | Enterprise 1.16.x |
| Storage backend | Raft (Integrated Storage) |
| Cluster topology | 5 nodes: 1 active + 4 performance standbys |
| Load balancing | Consul HTTP health check (static service registration, Consul service registration disabled in Vault) |
| Lease count | ~1 million leases at time of election |

## Quick Outline

This is a very rough outline of the customer's outage, so you can better understand the timeline and context related to the information below: 

1. Maintenance process begins
2. Vault's leadership election occurs (when the active node is restarted)
3. Consul service registration removes all non-leader nodes from the load balancer pool
4. Production traffic concentrates on the new active node at ~7× baseline
5. New active node starts lease restoration, which takes several minutes due to the large number of leases and the increased traffic load during restoration
6. Standbys are blocked from re-promoting to performance standby until lease restoration completes
7. Audit sink is overwhelmed by the traffic concentration, hits the 10s timeout, and produces the `event not processed by enough sink nodes` error
8. 5xx errors are returned to clients throughout the election and lease restoration window
9. Lease restoration completes, and performance standbys re-promote to `performance_standby=true`
10. Standbys return to the pool, traffic normalizes, and the audit sink recovers

## Problem Statement

The customer configured a Consul service registration with the following HTTP health check against the Vault `sys/health` endpoint:

```json
{
  "name": "Vault HTTP Health",
  "http": "https://127.0.0.1:8200/v1/sys/health?performancestandbycode=200&drsecondarycode=200&standbycode=503",
  "interval": "1s",
  "timeout": "5s",
  "tls_skip_verify": false
}
```

Here are the docs that reference this configuration:
- [Vault `sys/health` API for 1.16.x](https://developer.hashicorp.com/vault/api-docs/v1.16.x/system/health)

In 1.16.x, this customer configured:
- `performancestandbycode=200`: performance standby nodes return `200 OK`
- `drsecondarycode=200`: DR secondary nodes return `200 OK`
- `standbycode=503`: all non-performance standby nodes return `503 Service Unavailable`

At first glance, there doesn't seem to be anything wrong with this configuration. After all, the customer is not using the default Consul service registration with Vault and is customizing this health check to only direct traffic to the leader and performance standby nodes. By designing the health check this way, the customer explicitly does not want traffic going to standby nodes. And based on the Consul docs, `5xx` status codes are expected to be treated as critical and removed from the pool immediately ([Consul HTTP health check docs](https://developer.hashicorp.com/consul/docs/use-case/service-discovery)).

However, there is one big piece missing from this health check. In Vault, performance standbys during an election are torn down and their flag is changed to `standby=true, performance_standby=false` until they can catch up with the new leader and re-promote to performance standby. This means that during the election window, all 4 performance standby nodes were returning `503` from the Consul health check and were removed from the pool. This caused 100% of traffic to be directed to the new active node during the election window, which was also when it was performing lease restoration. The combination of these two factors caused a cascade that resulted in audit sink timeouts and 5xx errors to clients for several minutes after the election.

(Here is more information in my repo about the `sys/health` endpoint and how these status codes work: [sys/health Best Practices KB](./sys-health-best-practices-kb.md).)

All 4 performance standbys were removed from the Consul service pool and remained out of rotation for several minutes (which is longer than the customer expected). During this period the new active node absorbed roughly 7× its baseline request rate (~14K req/s vs ~2K req/s baseline), audit log writes began timing out, and the cluster returned 5xx errors to clients until standbys were restored to the pool.

Vault audit log error:

```text
event not processed by enough sink nodes ... context deadline exceeded
```

## Key Mechanisms

### Why Standbys Are Removed from the Pool Immediately

When a performance standby loses its leader, it clears the `perfStandby` flag. Until the new leader propagates cluster state back to it, the node reports `standby=true, performance_standby=false` from `sys/health`. With `standbycode=503`, the Consul HTTP check maps this to `503 Service Unavailable` and removes the node from rotation within one check interval (1s in this case).

This behavior is documented in the Vault `sys/health` docs:

> In rare occasions such as during cluster instability or a leadership change, a performance standby node may return `429` instead of `473`.

### Why Standbys Stayed Out of the Pool for Several Minutes

Getting back to `performance_standby=true` requires passing through the `waitForPerfStandby()` function, which has two gates:

Gate 1 — Raft index catch-up:

The standby calls `GuardHash()` on the active leader, receives the leader's current raft index, and then polls its own applied index until it catches up:

```text
// ha_ent.go
if raftStorage.AppliedIndex() >= guardResponse.RaftIndex {
    break
}
time.Sleep(5 * time.Millisecond)
```

This gate exists for consistency. The standby must have applied every raft log entry up to the leader's index at the time of the `GuardHash` call before it is allowed to serve as a performance standby.

Gate 2 — `postUnseal` with `perfStandbyUnsealStrategy`:

After the raft gate clears, the standby must complete `postUnseal()`. On the active node side, this includes `setupExpiration()`, which launches `expiration.Restore()` as a goroutine:

```text
// expiration.go
go c.expiration.Restore(errorFunc)
```

`Restore()` uses 64 worker goroutines to load all leases from storage. With ~1 million leases, this took approximately 4 minutes. The active node does not broadcast that standbys can rejoin until this initialization completes, which is why standbys showed `core: waiting to become performance standby` in logs only after lease restoration finished.

### Why the Audit Sink Started Failing

The Vault audit broker has a 10-second write timeout:

```text
// broker.go
timeout = 10 * time.Second
```

When the new active was handling 7× its normal request rate while simultaneously restoring leases and initializing, the file/socket audit backend could not drain the write queue within 10 seconds. This produced the error:

```text
event not processed by enough sink nodes ... context deadline exceeded
```

Audit sink latency exceeding 10s is visible in metrics (`vault_audit_log_response` latency). The errors stopped at the same time the performance standbys returned to the pool, confirming that traffic concentration was the root cause of extending this outage.

## Key Indicators in Logs

Standby nodes losing performance standby status (nodes begin returning `429`, which `standbycode=503` maps to `503` in the Consul health check, triggering removal from the pool):

```text
[ERROR] core: error shutting down performance standby
```

Audit sink failures on the active node during the window:

```text
[ERROR] audit: event not processed by enough sink nodes: context deadline exceeded
```

New active restoring leases (watch for this in the gap between election and standby recovery):

```text
[INFO]  expiration: lease restore complete
```

Standbys waiting for the active to finish:

```text
[INFO]  core: waiting to become performance standby
```

Standbys re-joining after lease restoration:

```text
[INFO]  core: authing to leader cluster successful
[INFO]  core: upgraded to performance standby
```

## Root Cause

The root cause was `standbycode=503` in the Consul health check, which caused all performance standbys to be removed from the load balancer pool during the transient post-election window.

The severity and duration of the outage were amplified by lease restoration taking several minutes, which delayed standbys from re-promoting. During that window, the traffic concentration onto one node caused the audit sink timeout cascade.

## References

- [Vault `sys/health` API for 1.16.x](https://developer.hashicorp.com/vault/api-docs/v1.16.x/system/health)
- [Consul HTTP health check docs](https://developer.hashicorp.com/consul/docs/use-case/service-discovery)
- [sys/health Best Practices KB](./sys-health-best-practices-kb.md)
- [Vault Performance Standby Documentation](https://developer.hashicorp.com/vault/docs/enterprise/performance-standby)
