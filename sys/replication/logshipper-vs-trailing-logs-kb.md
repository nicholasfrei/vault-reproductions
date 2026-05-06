# Vault KB: Logshipper Buffer vs. `trailing_logs` — Replication vs. HA Lag

## Overview

Vault exposes two distinct log-buffering parameters that are frequently confused with each other because both describe "how many log entries to keep before falling back to a heavier sync." They operate at entirely different layers of the system:

- `trailing_logs` — Raft log entries retained **within a single cluster** for HA standby catchup (intracluster).
- `logshipper_buffer_length` — WAL entries buffered **in memory on the primary** for shipping to remote secondary clusters (intercluster, Enterprise only).

Misconfiguring or misdiagnosing these leads to repeated full-snapshot floods on HA nodes, or secondary clusters stuck in Merkle reconciliation instead of streaming WALs.

## Architecture Context

### Intracluster: Raft log shipping (HA standbys)

Every Vault cluster using Integrated Storage runs a Raft consensus group consisting of one active (leader) node and one or more standby (follower) nodes. The leader continuously appends entries to the Raft log and replicates them to all followers. Periodically, the leader takes a **Raft snapshot** — a point-in-time serialization of the full state machine — and then **truncates** the log, retaining only the last `trailing_logs` entries on disk.

When a follower falls behind (network blip, restart, maintenance), it catches up by replaying those retained log entries. If it has missed more entries than `trailing_logs` holds, it cannot replay — the leader must send a full Raft snapshot. On large datasets, this snapshot can be hundreds of megabytes to several gigabytes and may take minutes to transfer and install.

### Intercluster: WAL log shipping (Enterprise replication)

Vault Enterprise replication (Performance Replication and DR Replication) operates across independent clusters over mTLS on the cluster port. It uses a separate mechanism: a **Write-Ahead Log (WAL)**. Every write on the primary creates one or more WAL entries. The primary maintains an in-memory ring buffer (`logshipper_buffer_length` entries) of recent WAL entries and streams them to each connected secondary in near real-time (`state: stream-wals`).

When a secondary falls behind — due to network latency, a maintenance window, or write bursts outpacing delivery — the ring buffer may no longer hold the WAL entries that secondary needs. When that happens, Vault falls back to **Merkle tree reconciliation**: both sides compare their Merkle indexes to identify which keys are out of sync, exchange diffs, and then resume WAL streaming. Merkle reconciliation is more expensive than WAL streaming and scales with dataset size.

## Parameter Reference

### `trailing_logs`

| Attribute | Value |
|---|---|
| Config stanza | `storage "raft" { }` |
| Default | `10000` |
| Editions | Community Edition and Enterprise (Integrated Storage) |
| Unit | Count of Raft log entries |
| Persisted where | Disk (Raft log files on the leader and all followers) |

> Note: `max_trailing_logs` is a separate parameter and is not the same as `trailing_logs`. `max_trailing_logs` is an autopilot configuration value (default `1000`, set via `vault operator raft autopilot set-config -max-trailing-logs`) that controls how many log entries behind the leader a follower can be before autopilot marks it as unhealthy. `trailing_logs` controls how many log entries the leader retains on disk after a snapshot — a much earlier-stage threshold that governs whether catch-up via log replay is even possible. The Vault documentation explicitly notes: "The `trailing_logs` metric is not the same as `max_trailing_logs`."

### `logshipper_buffer_length`

| Attribute | Value |
|---|---|
| Config stanza | `replication { }` |
| Default | `16384` |
| Editions | Vault Enterprise only |
| Unit | Count of WAL entries (in-memory ring buffer) |
| Persisted where | Memory on the primary active node only |

A companion parameter, `logshipper_buffer_size`, caps the buffer by byte size rather than entry count. Whichever limit is reached first takes effect.

| Parameter | Default | Description |
|---|---|---|
| `logshipper_buffer_length` | `16384` | Max WAL entries buffered for secondary delivery |
| `logshipper_buffer_size` | 10% of host RAM (falls back to 1 GB if host RAM cannot be detected) | Max byte size of the logshipper buffer |

Example configuration:

```hcl
replication {
  logshipper_buffer_length = 16384
  logshipper_buffer_size   = "5gb"
}
```

## Comparison

| Dimension | `trailing_logs` | `logshipper_buffer_length` |
|---|---|---|
| Scope | Intracluster (single cluster, leader → HA standbys) | Intercluster (primary cluster → secondary clusters) |
| Transport | Raft consensus log over cluster port | WAL log shipping over mTLS cluster port |
| Protocol | HashiCorp Raft | Vault Enterprise replication |
| Stored on | Disk (all Raft members) | Memory (primary active node only) |
| Default | `10000` | `16384` |
| Config stanza | `storage "raft" { }` | `replication { }` |
| Edition | CE and Enterprise | Enterprise only |
| Fallback when exhausted | Full Raft snapshot sent to follower | Merkle tree reconciliation, then WAL streaming resumes |
| Symptom when too low | Repeated full snapshot transfers to standbys | Secondary `state` leaves `stream-wals`, enters reconciliation |

## Failure Modes

### `trailing_logs` too low: snapshot storm

On clusters with large datasets (many PKI certificates, high lease volumes, large KV stores), Raft snapshots can reach hundreds of megabytes to several gigabytes. A slow or restarting follower may not finish installing a snapshot before the leader completes another snapshot cycle and truncates the log entries the follower still needs. The leader then sends another full snapshot — and the cycle repeats.

Symptoms:
- Vault standby logs show repeated snapshot install messages.
- Followers never fully catch up after restarts.
- Elevated Raft snapshot metrics.
- On larger clusters, brief unavailability during a rolling restart if standbys cannot reattach quickly.

Relevant log patterns:

```text
[INFO]  core: starting server
[INFO]  storage.raft: entering follower state
[INFO]  storage.raft: installed remote snapshot
```

### `logshipper_buffer_length` too low: secondary falls out of WAL streaming

A burst of writes — batch secret imports, PKI bulk certificate issuance, lease renewal storms — can fill the logshipper buffer faster than a secondary can consume it. Older WAL entries are evicted from the ring buffer. Any secondary that needed those evicted entries can no longer catch up by WAL streaming and must fall into Merkle reconciliation.

Symptoms:
- Secondary `state` field changes from `stream-wals` to a reconciling state.
- `replication_primary_canary_age_ms` rises sharply on the primary's status output.
- Replication lag visible via WAL index delta (`last_remote_wal` on secondary vs. `last_wal` on primary).
- Clients may observe stale reads on the secondary during reconciliation.

## Diagnosing Lag

### Checking HA Raft state

Check the Raft configuration and peer state on a cluster node:

```bash
vault operator raft list-peers
```

```text
Node          Address                State       Voter
----          -------                -----       -----
vault-node-1  10.0.1.10:8201         leader      true
vault-node-2  10.0.1.11:8201         follower    true
vault-node-3  10.0.1.12:8201         follower    true
```

Check Raft autopilot state (includes last index and health):

```bash
vault operator raft autopilot state
```

### Checking replication WAL lag

Overall replication status (primary or secondary):

```bash
vault read sys/replication/status
```

Performance replication status:

```bash
vault read sys/replication/performance/status
```

DR replication status:

```bash
vault read sys/replication/dr/status
```

Key fields to examine:

| Field | Location | Meaning |
|---|---|---|
| `state` | Secondary status | `stream-wals` is healthy; other states indicate reconciliation |
| `last_remote_wal` | Secondary status | Last WAL index received from primary |
| `last_wal` | Primary status | Latest WAL index on primary |
| `connection_status` | Primary's view of secondary | `connected` or `disconnected` |
| `replication_primary_canary_age_ms` | Primary's view of secondary | Canary age in ms; higher values indicate replication lag |
| `merkle_root` | Both primary and secondary | Should match when fully synced |

WAL lag count = `last_wal` (primary) minus `last_remote_wal` (secondary). A delta larger than `logshipper_buffer_length` means the secondary has already fallen out of the WAL window and will need Merkle reconciliation to recover.

Example status output fields on a secondary:

```text
Key                    Value
---                    -----
state                  stream-wals
connection_state       ready
last_remote_wal        18423
merkle_root            a1b2c3d4e5f6...
```

Example canary age fields on a primary (per connected secondary):

```text
Key                                          Value
---                                          -----
connection_status                            connected
last_heartbeat                               2026-05-06T10:05:56-05:00
replication_primary_canary_age_ms            712
```

## Tuning Recommendations

### `trailing_logs`

- The default of `10000` is appropriate for most deployments.
- Increase if standbys are repeatedly receiving full snapshots after brief disconnects. A value of `50000`–`100000` is reasonable for large, high-write clusters.
- Increasing `trailing_logs` keeps more entries on disk, so factor in available disk space on all Raft members.
- Consider also increasing `snapshot_threshold` to reduce how often the log is truncated, giving followers more time to catch up.
- Before tuning, rule out underlying storage performance issues (disk I/O saturation) that slow down snapshot installation independently.

### `logshipper_buffer_length`

- The default of `16384` is appropriate for most deployments.
- Increase if secondary clusters frequently fall into Merkle reconciliation under sustained write load.
- A rough sizing formula: `buffer_length >= write_rate_wals_per_second × acceptable_lag_seconds`. For example, a cluster generating 500 WAL entries/second that must tolerate 60 seconds of secondary lag needs a buffer of at least `30000`.
- Pair `logshipper_buffer_length` with an explicit `logshipper_buffer_size` to avoid unexpected memory pressure on hosts with very large RAM (the 10% default can be several gigabytes on large instances).
- Very large buffers increase memory consumption on the primary active node. Increase gradually and monitor heap metrics.

## Related Endpoints

| Endpoint | Method | Description |
|---|---|---|
| `sys/replication/status` | `GET` | Overall replication status |
| `sys/replication/performance/status` | `GET` | PR replication status |
| `sys/replication/dr/status` | `GET` | DR replication status |
| `sys/replication/recover` | `POST` | Attempt recovery of stalled replication |
| `sys/replication/reindex` | `POST` | Reindex the local Merkle tree (slow on large stores) |
| `sys/replication/merkle-check` | `POST` | Check Merkle tree integrity before reindexing |
| `sys/replication/dr/secondary/reindex` | `POST` | Reindex on a DR secondary using DR op token |
| `sys/replication/dr/secondary/merkle-check` | `POST` | Merkle check on a DR secondary |

## Additional Gotchas

- `ha_storage` is not compatible with Integrated Storage. When using `storage "raft"`, all HA coordination runs through Raft. There is no separate `ha_storage` stanza.
- Replication traffic uses Vault-generated mTLS certificates on the cluster port. Load balancers handling the cluster port must be configured as **TCP passthrough** — TLS termination at the load balancer breaks replication.
- Always upgrade secondary clusters before the primary. Replication from a newer primary to an older secondary is unsupported.
- Read-after-write consistency: when clients write through a secondary (which forwards to the primary), the secondary waits up to `best_effort_wal_wait_duration` (default `2s`) for the WAL to appear locally. A lagging secondary may return stale reads within this window. Use the `X-Vault-Inconsistent: forward-active-node` header for latency-sensitive read paths, or configure `allow_forwarding_via_header = true` in the `replication` stanza.

## References

- [Vault Integrated Storage — Raft configuration](https://developer.hashicorp.com/vault/docs/configuration/storage/raft)
- [Vault Enterprise Replication](https://developer.hashicorp.com/vault/docs/enterprise/replication)
- [Vault API — sys/replication](https://developer.hashicorp.com/vault/api-docs/system/replication)
- [Vault KB: Corrupted Merkle Trees Blocking PR and DR Replication](./vault-replication-merkle-corruption-reindex-kb.md)
