# `sys/health` Best Practices KB

## Overview

The `sys/health` endpoint is a lightweight, unauthenticated HTTP endpoint on every Vault node that reports the node's current role and seal state via HTTP status codes. It was designed to integrate directly with load balancer and health check systems (including Consul service checks) that make routing decisions based on HTTP response codes.

This KB covers how the endpoint works, what each query parameter does, and a real support case where a misconfigured `standbycode` parameter caused a cluster-wide outage during a planned maintenance window.

---

## Default Status Codes in `1.16.x`

Out of the box, with no query parameters, `sys/health` returns:

| HTTP Code | Node State |
|-----------|-----------|
| `200` | Initialized, unsealed, and active |
| `429` | Unsealed and standby (including performance standbys that haven't been identified yet) |
| `472` | Disaster Recovery secondary (all nodes in the DR secondary cluster) |
| `473` | Performance standby |
| `501` | Not initialized |
| `503` | Sealed |

These defaults mirror the original Consul health check semantics where `2xx` means healthy, `429` means warning, and `5xx` is critical and the node is pulled from rotation.

### Sample: Active Node Response

```bash
curl -i http://vault-1.vault-1.svc.cluster.local:8200/v1/sys/health
```

```text
HTTP/1.1 200 OK
Cache-Control: no-store
Content-Type: application/json
X-Vault-Hostname: vault-1-0
X-Vault-Raft-Node-Id: vault-1-0
```

```json
{
  "initialized": true,
  "sealed": false,
  "standby": false,
  "performance_standby": false,
  "replication_performance_mode": "disabled",
  "replication_dr_mode": "disabled",
  "server_time_utc": 1777317213,
  "version": "1.16.7+ent",
  "enterprise": true,
  "cluster_name": "vault-cluster-ac55e2c8",
  "cluster_id": "56a9a41a-e8ab-ef59-f44e-d7c9b25e89d9",
  "last_wal": 39064,
  "license": {
    "state": "autoloaded",
    "expiry_time": "2030-07-01T00:00:00Z",
    "terminated": false
  },
  "echo_duration_ms": 0,
  "clock_skew_ms": 0
}
```

---

## Query Parameters

All query parameters override the default status code for a specific node state. They do not change what the node actually is — they only change what HTTP code the endpoint returns for that state. This is the distinction that causes most misconfigurations.

### Boolean flags

| Parameter | Default | Purpose |
|-----------|---------|---------|
| `standbyok` | `false` | If `true`, a standby node returns `200` instead of `429`. Does **not** apply to performance standbys. |
| `perfstandbyok` | `false` | If `true`, a performance standby returns `200` instead of `473`. |

These flags are useful when a load balancer can only route on `200` vs non-`200` and you want all unsealed nodes (active + standbys) in the pool.

### Integer overrides

These let you map each node state to any HTTP status code you choose. The key insight is that setting a code to `503` tells the health check system "treat this state as unhealthy / remove from pool."

| Parameter | Default value | Overrides the code for... |
|-----------|--------------|--------------------------|
| `activecode` | `200` | The active (leader) node |
| `standbycode` | `429` | Any standby node that is **not** a performance standby |
| `drsecondarycode` | `472` | All nodes in a DR secondary cluster |
| `performancestandbycode` | `473` | Performance standby nodes |
| `uninitcode` | `501` | Uninitialized nodes |
| `sealedcode` | `503` | Sealed nodes |

#### `standbycode`

Controls the status code returned for a regular standby — a node that is unsealed and in the cluster but is not the active leader and is not a performance standby. In a cluster with all performance standbys this parameter appears irrelevant, but it becomes critical during leader elections (see the incident below).

#### `performancestandbycode`

Controls the status code for performance standbys. These nodes can serve read requests and most non-write API calls. Setting this to `200` includes them in the Consul-managed load balancer pool for read traffic.

#### `drsecondarycode`

Controls the status code for all nodes on a DR secondary cluster. By default `472` causes them to be excluded from a generic load balancer. Setting to `200` is appropriate when you have a dedicated health check specifically for DR secondary nodes.

### Disclaimer on Performance Standbys

> **Important caveat from the Vault documentation**: In rare occasions such as during cluster instability or a leadership change, a node may return `429` even when it is normally a performance standby (`473`). This happens because the new active node has not yet propagated cluster membership information to the standbys. From the node's perspective, it briefly does not know it is a performance standby.

This means `standbycode` is **not** purely about "non-performance standbys." It is also the code returned by performance standbys during the brief window after a leadership change before the new active communicates their role back to them.

---

## Sample Customer Incident 

`standbycode=503` caused temporary outage during planned maintenance

### Environment

| Item | Value |
|------|-------|
| Vault version | Enterprise 1.16.x |
| Storage backend | Consul |
| Cluster topology | 5 nodes: 1 active + 4 performance standbys |
| Load balancing | Consul HTTP health check (static service registration) |

### Consul Health Check Configuration

```json
{
  "name": "Vault HTTP Health",
  "http": "https://127.0.0.1:8200/v1/sys/health?performancestandbycode=200&drsecondarycode=200&standbycode=503",
  "interval": "1s",
  "timeout": "5s",
  "tls_skip_verify": false
}
```

Based on this health check configuration, performance standbys (`performancestandbycode=200`) will serve traffic, but standbys should not. `standbycode=503` was set to exclude any node that is a standby.

### What Happened

1. Planned maintenance: the active node was restarted to cycle leadership.
2. A new leader was elected within ~3 seconds and began accepting traffic.
3. The 4 performance standbys, which had been serving traffic normally, entered a brief transition window where they returned `429` (regular standby) instead of `473` (performance standby). This happens because the old active is gone and the new active has not yet sent cluster state to them.
4. With `standbycode=503`, the Consul health check immediately failed all 4 standbys and removed them from the service pool.
5. 100% of traffic — previously spread across 5 nodes — was now routed to the single new active node. This was roughly a 5× traffic increase to one node.
6. The new active node, now handling the full cluster load, could not drain its audit queue fast enough. The `file/` audit device became the bottleneck.
7. Because Vault blocks on audit writes before returning a response, every in-flight request stalled waiting for audit. Goroutines piled up: `go_goroutines` peaked at ~2.5 million (baseline ~10–20K).
8. The node returned `5xx` for all requests for approximately 3 minutes until the standbys re-established their performance standby status and Consul returned them to the pool.

### Root Cause

The `standbycode=503` parameter was intended to exclude standbys, but it also caused performance standbys to be marked unhealthy during the brief post-election window when they transiently return `429`. The planned maintenance window triggered a leadership change which triggered the transition window, which triggered the health check failure, which caused a full traffic consolidation onto one node.

This is a cascade:

```
Active node restarted
  → Leadership election (~3s)
  → Performance standbys transiently return 429 (standby)
  → standbycode=503 maps 429 → 503
  → Consul removes all 4 standbys from pool
  → 5× traffic lands on new active
  → Audit write queue backs up
  → Goroutine pile-up (~2.5M goroutines)
  → 5xx responses for ~3 minutes
```

### Why the Standbys Briefly Return 429

A performance standby learns it is a performance standby from the active node. When the active node is replaced, there is a window — typically a few seconds — where the standbys have not yet received the performance standby designation from the new leader. During this window they return `429` (unsealed standby), not `473` (performance standby). Once the new active propagates cluster state, the nodes return to `473` and `performancestandbycode=200` maps them back to healthy.

### Verification: What the Consul Check Saw on a Standby During Transition

```bash
curl -i "https://127.0.0.1:8200/v1/sys/health?performancestandbycode=200&drsecondarycode=200&standbycode=503"
```

```text
HTTP/1.1 503 Service Unavailable
Cache-Control: no-store
Content-Type: application/json
X-Vault-Hostname: vault-1-2
X-Vault-Raft-Node-Id: vault-1-2
```

```json
{
  "initialized": true,
  "sealed": false,
  "standby": true,
  "performance_standby": false,
  "replication_performance_mode": "disabled",
  "replication_dr_mode": "disabled",
  "server_time_utc": 1777315824,
  "version": "1.16.7+ent",
  "enterprise": true,
  "cluster_name": "vault-cluster-ac55e2c8",
  "cluster_id": "56a9a41a-e8ab-ef59-f44e-d7c9b25e89d9"
}
```

Note `"performance_standby": false` in the response body even though this node is normally a performance standby. The body is accurate — the node genuinely does not know it is a performance standby yet. The Consul health check is working exactly as configured; the configuration was the problem.

### Alternative Configurations

### Option 1: Accept 429 as healthy (recommended for read-capable clusters)

Instead of mapping `standbycode` to `503`, leave it at the default (`429`) and configure the Consul check to treat `429` as passing. Consul HTTP checks accept a `success_before_passing` and `failures_before_critical` count but do not natively accept custom passing codes. The correct approach is to use `standbyok=true` or `perfstandbyok=true` to promote the node to `200`:

```json
{
  "name": "Vault HTTP Health",
  "http": "https://127.0.0.1:8200/v1/sys/health?perfstandbyok=true&standbyok=true",
  "interval": "10s",
  "timeout": "5s"
}
```

This returns `200` for active, performance standbys, and regular standbys — all unsealed nodes are in the pool. Use this when you want maximum availability and your load balancer handles routing internally.

### Option 2: Keep performance standbys in pool but use a longer Consul deregister window

If you genuinely want to exclude regular standbys but keep performance standbys, keep `performancestandbycode=200` but do **not** set `standbycode=503`. Accept that `429` will briefly appear and configure a `deregister_critical_service_after` window large enough to survive an election cycle (typically 15–30 seconds):

```json
{
  "name": "Vault HTTP Health",
  "http": "https://127.0.0.1:8200/v1/sys/health?performancestandbycode=200&drsecondarycode=200",
  "interval": "5s",
  "timeout": "5s",
  "deregister_critical_service_after": "30s"
}
```

Under default settings, a `429` response causes the Consul check to enter a warning state (not immediately critical), which is another reason the original `503` mapping was more aggressive than needed.

---

## Key Takeaways

- `standbycode` affects performance standbys during leadership elections, not just standbys.
- Performance standbys transiently return `429` after a leadership change.
- Short Consul health check intervals (`1s`) amplify the unintended impact — nodes are deregistered within seconds of entering the transition window.

---

## References

- https://developer.hashicorp.com/vault/api-docs/v1.16.x/system/health
- https://developer.hashicorp.com/consul/docs/register/health-check/vm#http-checks
- https://developer.hashicorp.com/consul/docs/reference/service/health-check#check-block