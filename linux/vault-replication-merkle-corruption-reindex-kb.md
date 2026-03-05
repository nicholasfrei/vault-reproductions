# Vault KB: Corrupted Merkle Trees Blocking PR and DR Replication

## Problem Statement / Introduction

This KB is based on a real support-case for a Global Fortune 500 Corporation where Performance Replication (PR) and Disaster Recovery (DR) secondaries stayed in `merkle-diff` or `merkle-sync` for an extended period (several months). The customer had spent months troubleshooting the issue before they reached out. They had attempted reindexing the secondaries (PR and DR) but were unable to resolve the issue. 

The key issue was corruption on the primary in both merkle trees:

- `tree_type="replicated"` (impacts PR replication)
- `tree_type="local"` (impacts DR replication)

In this condition, reindexing only a secondary can complete cleanly but still fail to restore steady streaming replication.

What reindex does at a high level:

- Vault builds a new in-memory merkle tree by listing and reading keys from storage.
- Vault replays write-ahead-log (WAL) updates that occurred during tree construction.
- Vault compares the existing replication tree to the rebuilt tree and replaces mismatched pages.

Reindex duration has no exact estimator and depends mostly on:

- Total key volume/data size.
- Storage performance (disk I/O, and Consul/network latency where applicable).
- Write pressure during reindex (logins, lease activity, revocations, tidy, config writes).

## Findings / Errors / Diagnostics

The repeated primary signal in logs was:

```text
state is still irreconcilable after reindex, try reindexing primary cluster
```

Check current replication state on each cluster (primary, PR secondary, DR secondary):

```bash
vault read -format=json sys/replication/status
```

Expected diagnostic indicators:

- Affected secondaries show `state` as `merkle-diff` or `merkle-sync`.
- Replication may show recurring backoff with irreconcilable-state errors.

Check merkle corruption on each cluster:

```bash
vault write -format=json sys/replication/merkle-check
```

Sample primary corruption pattern:

```json
{
  "data": {
    "merkle_corruption_report": {
      "corrupted_root": true,
      "corrupted_tree_map": {
        "1": {
          "tree_type": "replicated",
          "corrupted_subtree_root": true
        },
        "2": {
          "tree_type": "local",
          "corrupted_subtree_root": true
        }
      }
    }
  }
}
```

Case pattern that pointed to primary-side corruption:

- PR secondary remained in `merkle-sync` even after a long-running secondary reindex.
- DR secondary remained in `merkle-diff`.
- Primary `sys/replication/merkle-check` showed `corrupted_root=true` in both:
  - `tree_type="replicated"` (PR impact)
  - `tree_type="local"` (DR impact)
- Logs repeatedly showed:

```text
state is still irreconcilable after reindex, try reindexing primary cluster
```

## Path to Resolution

After identifying the corruption on the primary cluster, we worked with the customer to create a plan to address the issue. We recommended a reindex on the primary cluster with controlled write pressure, followed by checks on both PR and DR secondaries. The idea being, if we can resolve the merkle tree corruption, we will no longer see the `merkle-diff` or `merkle-sync` state on the secondaries, and replication should return to healthy streaming behavior. Below were the rough steps we recommended:

1. Capture baseline status and take a fresh primary storage backup/snapshot.
   1. Keep a previous known-good backup available for rollback planning.
2. Reduce write-heavy operations before and during reindex.
3. Avoid leader changes/restarts during reindex.
4. Reindex the primary with `skip_flush=true`:

```bash
vault write -f sys/replication/reindex skip_flush=true
```

5. Monitor primary stage progression:

```bash
vault read -format=json sys/replication/status
```

6. Keep the active node stable after command completion so background dirty-page flush can finish.

### Pre-flight and Change Window Checklist

- Capture `sys/replication/status` on primary, PR secondary, and DR secondary before changes.
- Capture `sys/replication/merkle-check` on all clusters before reindex.
- Take fresh primary backend backup/snapshot and retain a prior known-good backup.
- Plan a low-traffic window.
- Temporarily pause/relax health checks or automation that could restart/step down active Vault nodes during reindex.
- Communicate expected write impact during `wal-replay`/`commit` lock windows.

### Reindex Stages

- `scanning`
  - Vault performs breadth-first list operations to gather key paths.
  - Impact is usually low.
  - No write lock is held.
  - `sys/replication/status` remains available.

- `building`
  - Vault reads each collected key and builds a new in-memory merkle tree.
  - Usually the longest stage.
  - No write lock is held.
  - Read load and memory usage can increase.
  - Progress fields may appear in status output, such as:
    - `reindex_building_progress`
    - `reindex_building_total`

- `wal-replay`
  - Phase 1: Vault replays writes that occurred during scanning/building (without lock).
  - Phase 2: Vault applies a write lock and replays remaining writes generated during phase 1.
  - During lock window, writes may fail or block.
  - Locking is required so Vault can finalize the new tree without additional mutations.
  - `sys/replication/status` may become unavailable during the lock.

- `commit`
  - Vault finalizes merkle page replacement.
  - Write lock remains active.
  - `sys/replication/status` is often temporarily unavailable.
  - Tree updates are in memory first; persistence depends on dirty-page flush.

After the command completes, keep the active node stable while dirty pages flush in the background:

```bash
journalctl -u vault -f | grep -E "merkle|reindex|flush"
```

If telemetry is enabled, monitor `vault.merkle.flushDirty.outstanding_pages` for downward trend.

If writes were heavily reduced for reindex, resume traffic gradually to avoid a thundering-herd surge while flush is still settling.

### Write-impact guidance during reindex

Typical write sources to minimize before and during reindex:

- Login/auth bursts.
- Secret updates/config changes.
- Lease renewals and revocations.
- Tidy operations or other high-churn maintenance.

Mitigations:

- Prefer low-activity maintenance windows.
- Throttle applications where possible.
- Consider temporary TTL tuning.
- If redirecting read/auth traffic to a PR secondary, remember forwarded writes to primary can still fail during lock windows.

## Discussion About the Issue

Why secondary-only reindex would not fix the issue:

- The primary is the authoritative source for replication merkle state.
- If the primary tree remains corrupted, secondaries can re-enter `merkle-diff` or stay stuck.
- During this case, the customer came to us after a reindex of their secondary clusters.

Operational considerations:

- Keep writes low before and during `wal-replay` and `commit` to reduce lock duration.
- Keep leadership stable; a leader change causes reindex restart on the new leader.
- For app routing during primary reindex:
  - Auth/read-only traffic can be temporarily pointed to a Performance Secondary.
  - Write/admin operations must target the primary and can fail during lock windows.
  - Tokens and leases are not replicated to PR secondaries, so clients may need to re-authenticate on the PR secondary.

Answering a common app-team question from this case:

- During primary reindex, temporary endpoint redirection to PR secondary is acceptable for auth/read workloads.
- If unexpected behavior occurs while on PR secondary, either:
  - fail back to primary when primary is available and not write-locked, or
  - pause/retry until lock window completes.
- After primary reindex and replication health confirmation, route traffic back to primary as authoritative write endpoint.

Version notes from this case:

- Customer was using `1.14.x` on the primary/PR secondary & `1.16.x` on the DR secondary.

Rollback caution:

- Vault persists reindex markers in storage and will resume reindex after leadership events/outages.
- Marker keys persisted at start of reindex:
  - `index/reindex-in-progress`
  - `index-dr/reindex-in-progress`
- Because reindex work is in memory, a new leader resumes by restarting reindex work.
- If an operator must abort reindex, marker cleanup is storage-backend specific and should be coordinated carefully with support.

## Resolution / Conclusion

The issue was considered resolved when all checkpoints were true:

- Primary `vault write -format=json sys/replication/merkle-check` reports `corrupted_root=false`.
- Primary `corrupted_tree_map` is clean for both:
  - `tree_type="replicated"`
  - `tree_type="local"`
- Primary no longer reports `reindex_in_progress=true`.
- PR and DR replication leave `merkle-diff`/`merkle-sync` and return to healthy running/streaming behavior.
- Logs stop showing `state is still irreconcilable after reindex`.
- Application write path to the primary is stable after reindex and flush settling.

Helpful post-check commands:

```bash
vault read -format=json sys/replication/status
vault write -format=json sys/replication/merkle-check
```

## References

- [Replication Overview and Merkle Sync Loop Analyses](https://support.hashicorp.com/hc/en-us/articles/20457140183443-Replication-Overview-and-Merkle-Sync-Loop-Analyses)
- [Vault Enterprise Replication](https://developer.hashicorp.com/vault/docs/enterprise/replication)
