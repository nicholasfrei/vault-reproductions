# Vault KB: Performance Secondary Snapshot Loop with Large Lease Volume

## Overview

This incident came in as an issue related to a performance secondary cluster. A single node inside the secondary cluster was stuck in a Raft snapshot loop, unable to converge with its own cluster leader. This started when the customer was attempting to increase RAM on the cluster to address other performance related issues (I suspect it was related to a lease explosion issue).

The environment was under significant pressure at the time. The secondary's `vault.db` had grown to roughly 40 GB, lease volume had ballooned to around 6M leases, and the cluster was running with sustained memory pressure above 90% RAM with more than 10 GB of swap in active use. Under those conditions, one follower node fell far enough behind the leader that it was attempting to catch up via snapshots. Each snapshot cycle took approximately 1.5 hours to apply — but by the time it finished, the node was still ~175k Raft index or more behind the active node and the cycle would begin again.

What made this difficult to resolve was that the cluster was under immense memory pressure and the customer was unable to allocate additional resources to the VMs in the cluster. The underlying dataset size and lease churn were generating enough write pressure that the node couldn't outrun the log between snapshot cycles. This KB captures what we observed, the triage path, what we tried, and what the best options are to address this issue in the future.

## Problem Statement

Scope:

- Performance secondary cluster was healthy with 2 nodes out of 3 in qourum. 
   - `vault operator raft autopilot state` showed one node as `healthy: false` and an index of 0
- One follower node was unable to catch up to the leader and repeatedly tried to restore from snapshots.
   - The lagging node was unable to elect as a performance standby; high RAM utilization on the leader and the large `vault.db` size prevented it from completing Raft catchup.
- Replication from the performance primary cluster was healthy.

Observed factors on the performance secondary cluster:

- `vault.db` was approximately `40 GB`.
- Lease count was roughly `6M`.
- Server had `64 GB RAM` and 8 CPU.
- RAM usage exceeded `90%` with more than `10 GB` swap in use (disk-backed memory pressure).
   - The cluster had less than ~500MB of RAM free at any point during the incident.
- One node fell behind and repeatedly entered snapshot behavior instead of stabilizing.
- One snapshot cycle on the lagging node took approximately `1.5 hours`.
- After snapshot restore completed, the lagging node still reported approximately `175k` index behind the active node.
   - The snapshot completion message would show `NaN%` and start back over from 0. 

Primary concern during the incident:

- Since it was a 3 node cluster, we were worried about another node in the cluster falling behind and causing a loss of qourum. 

## Triage and Investigation

The snapshot restore loop was confirmed by watching Vault logs on the lagging node. The restore percentage output would reach completion but then reset to `NaN%` and immediately begin a new cycle — indicating the node could not converge with the leader before the next snapshot was triggered.

The standard recovery procedure for a node stuck in this state is to stop Vault, wipe local Raft state (`vault.db` and the `raft/` directory), and rejoin the node to the cluster. This was attempted and did not resolve the loop. The underlying write pressure and lease churn on the cluster were generating new Raft entries faster than the node could apply the restored snapshot and catch up by log replay.

Key observations:

- The snapshot cycle duration (~1.5 hours) was significantly extended by memory pressure and active swap usage. Snapshot restore requires loading a large volume of state into memory, which was severely constrained on this cluster.
- After each restore, the lagging node was still ~175k Raft index behind the active node. Write throughput during the snapshot apply window alone was enough to keep it perpetually behind.
- An increase in RAM was identified as the primary blocker to stabilizing the node. The customer's infrastructure team was unable to approve the additional resources during the incident window, which left the cluster in a degraded 2-of-3 quorum state for the duration of the incident.

## Recommendations Provided During Incident

The following recommendations were provided during incident handling:

1. Increase `trailing_logs` to allow larger follower lag tolerance before snapshot-based catch-up is required.
   - The default is `10000` Raft log entries. On a high-write cluster with a large dataset, a brief follower disconnect or a slow apply can easily exceed this threshold and force a full snapshot transfer. Increasing to `50000`–`100000` gives followers more opportunity to catch up by log replay instead of triggering a snapshot cycle.
   - In this incident, write pressure was high enough that even after a clean rejoin the node could not outrun the log. A larger `trailing_logs` value would not have broken the loop once the node was already far behind — but it provides more tolerance for transient lag earlier in the degradation curve, potentially preventing the loop from starting in the first place. See [Logshipper Buffer vs. `trailing_logs` — Replication vs. HA Lag](../replication/logshipper-vs-trailing-logs-kb.md)
2. Remove local Raft state on the lagging node (`vault.db` and `raft/` directory), then rejoin the node to the cluster.
   - Result in this case: this action did not resolve the recurring snapshot loop.
3. Increase RAM capacity on the affected cluster to reduce memory pressure and swap utilization during snapshot apply/WAL catch-up.
   - This was the primary blocker during this incident. With less than ~500 MB of RAM free and more than 10 GB of swap in active use, snapshot restore performance was severely degraded — the cluster was effectively I/O-bound on swap for the entirety of each cycle. The customer's infrastructure team was not able to approve additional resources during the incident window, which prolonged the degraded state. Until RAM is increased, the snapshot loop is unlikely to resolve on its own given the current lease volume and write rate. 

The customer was advised to increase RAM to 128GB and stop traffic to this cluster until the leases could be cleaned up and the node could stabilize. We felt if they were unable to increase RAM, the only other option was to let the cluster run in a degraded 2-of-3 state until the lease volume and write pressure subsided enough for the node to catch up during one of snapshot cycles.

## References

- [Vault Enterprise Replication](https://developer.hashicorp.com/vault/docs/enterprise/replication)
- [Integrated Storage Concepts](https://developer.hashicorp.com/vault/docs/concepts/integrated-storage)
- [Troubleshooting Vault](https://developer.hashicorp.com/vault/tutorials/monitoring/troubleshooting-vault)
- [Logshipper Buffer vs. `trailing_logs` — Replication vs. HA Lag](../replication/logshipper-vs-trailing-logs-kb.md)

---

## Appendix: Performance Primary Cluster Context

The following environment indicators were collected from the performance primary cluster during the incident. This isn't related to the issues on the performance secondary cluster, but does show that the primary was also under significant pressure at the time. (e.g. lease explosion resulting in cascading effects across their environment)

- `vault.db` on performance primary was approximately `35 GB`.
- Lease count on performance primary was approximately `5.1M`.
- Memory allocated to the performance primary cluster was `74 GB RAM`.
- RAM usage on the primary also exceeded `90%` with more than `10 GB` swap in use at the time of the incident.