# Global Plugin Reload Cleanup: OOM and Quorum Loss at Namespace Scale

## Incident Summary

During a Cloud Foundry (CF) auth plugin migration from an external plugin to the built-in CF plugin, a large enterprise customer reloaded the CF plugin once per namespace using `vault plugin reload -type=auth -plugin=cf -scope=global` (and, for root-namespace mounts, an equivalent mount-scoped global reload). Across approximately 850 namespaces this produced roughly 850 accepted global reload requests over the course of the migration. The Vault Enterprise sandbox had no client traffic during either migration session.

Approximately 30 minutes after the migration activity began, the cluster lost quorum. A supplied CPU profile from the affected node showed the time concentrated in `entHandleGlobalPluginReload` and `logical.ScanView`, and the failure was reproduced across two independent migration sessions with the same ~30-minute timing.

Root cause: a defect in the *delayed cleanup* path for global plugin reload bookkeeping, not in the CF plugin or in any client-facing code path. Every accepted global reload request scheduled its own independent cleanup timer 30 minutes in the future. When those timers fired, cleanup performed a full walk of the entire Vault storage hierarchy (not just the small reload-bookkeeping keyspace) once per request, and never deleted the request records it was supposed to be retiring. Because cleanup is re-armed by whichever node is currently active, every subsequent Raft leader election handed the *entire, still-growing backlog* to the new leader as one immediate, synchronous burst of work — allowing an ordinary, supported CLI command, issued with zero client traffic, to repeatedly overload and remove nodes from the cluster until quorum was lost.

This is fixed in commit `c64fcbab91d9c0394a62fcf60f24357f5bbb6c3c` on `VAULT-46511/<customer>-2.0.x+ent-custom-build-nf`. Status: fixed and reproduced pre/post with a standalone stress harness (see Evidence).

## Environment

- Vault Enterprise, restored from a QA snapshot, no client traffic during either migration session.
- Approximately 1,350 CF auth mounts.
- Approximately 850 namespaces.
- Thousands of total mounts across several plugin types.
- 128 GB RAM per node.
- A custom Vault build prepared for this investigation (predecessor of the fix commit).
- Quorum loss occurred during both of two independent, assisted migration sessions.

The absence of client traffic does not imply the absence of load: plugin reload propagation, reload-status bookkeeping, Raft replication of the reload request, and the delayed cleanup callback all execute purely from Vault's own internal machinery, independent of any CF login traffic.

## What Triggered It

The migration helper (`~/repos/vault-tools/users/maithyton/cf-upgrade/reload.sh` at the time of investigation) issued:

- One mount-scoped global reload for every root-namespace CF mount.
- One plugin-scoped global reload (`scope=global`) for every non-root namespace containing CF mounts.

For ~850 namespaces this produced on the order of 850 accepted `POST /v1/sys/plugins/reload/backend` requests, each with `scope=global`, spread over the course of the migration (the helper paced requests with a short delay between namespaces). Every one of those requests is a normal, supported operation — the defect was entirely in what Vault did with the bookkeeping for each request 30 minutes later.

## Root Cause

### 1. Every accepted global reload scheduled its own independent 30-minute timer

Pre-fix, `entHandleGlobalPluginReload` unconditionally scheduled a new goroutine timer for every accepted request:

```go
func entHandleGlobalPluginReload(ctx context.Context, c *Core, req pluginReloadRequest) error {
	time.AfterFunc(pluginReloadRequestExpirationTime, func() {
		if err := c.PluginReloadCleanup(c.activeContext, pluginReloadRequestExpirationTime); err != nil {
			c.logger.Error("error cleaning up plugin reload request", "error", err)
		}
	})
	// ... write status entry and request record ...
}
```

`pluginReloadRequestExpirationTime` is 30 minutes. With ~850 accepted requests, the active node armed ~850 independent timers, all owned by (and running on) that one active node — not the cluster as a whole.

### 2. Cleanup walked the entire storage hierarchy, not just the reload keyspace

When a timer fired, `PluginReloadCleanup` called `logical.CollectKeysWithPrefix(ctx, c.barrier, pluginReloadRequestPath)`. Despite taking a prefix argument, the implementation only filtered *after* an unbounded `ScanView` that recursively lists every key from the barrier root (`""`) downward:

```go
func CollectKeysWithPrefix(ctx context.Context, view ClearableView, prefix string) ([]string, error) {
	var keys []string
	cb := func(path string) {
		if strings.HasPrefix(path, prefix) {
			keys = append(keys, path)
		}
	}
	if err := ScanView(ctx, view, cb); err != nil {
		return nil, err
	}
	return keys, nil
}
```

So every one of the ~850 fired timers repeated a full recursive walk of the customer's *entire* barrier keyspace — thousands of mounts across ~850 namespaces — purely to find a handful of keys under `core/plugins/reload/request/`. Cost scaled with total Vault storage size and hierarchy depth, not with the number of CF mounts or even the number of outstanding reload requests.

### 3. Reload request records were read repeatedly and never deleted

For each key found, cleanup read and JSON-decoded the request record, and, if expired, cleared only the associated status subtree — it never deleted the request record itself:

```go
if time.Since(reloadRequest.Timestamp) >= rrExpTime {
	statusPath := path.Join(pluginReloadStatusPath, reloadRequest.ReloadID)
	if err = logical.ClearView(ctx, NewBarrierView(c.barrier, statusPath)); err != nil {
		c.logger.Warn("error cleaning up plugin reload status", err)
		continue
	}
}
```

With N≈850 outstanding requests submitted close together, this is on the order of N² Get/decode operations across the run (≈722,500 for N=850), on top of the N full-barrier scans from point 2. The un-pruned `core/plugins/reload/request/` keyspace also meant nothing was ever removed — every future cleanup pass, by any node, would rediscover the same backlog and grow it further, forever.

### 4. Leadership failover handed the entire backlog to the next node as one immediate burst

`setupPluginReload` runs as part of `runUnsealSetupForPrimary`, i.e. it fires every time a node becomes the active/primary node of the cluster — not just once at process startup, but on every subsequent Raft leader election. Pre-fix, that function scheduled a single cleanup call 5 minutes later:

```go
func entHandleSetupPluginReload(c *Core) error {
	time.AfterFunc(5*time.Minute, func() {
		if stopped := grabLockOrStop(...); stopped {
			return
		}
		defer c.stateLock.RUnlock()
		_ = c.PluginReloadCleanup(c.activeContext, pluginReloadRequestExpirationTime)
	})
	return nil
}
```

Because request records were never deleted (point 3), any node newly promoted to active inherits the *entire, ever-growing* backlog of past reload requests. And because those requests are, by the time of a failover, already well past their 30-minute expiry, cleanup does not trickle in gradually the way the original 850 requests were submitted — it fires as one single, synchronous, maximally expensive burst, 5 minutes after the new leader takes over.

### Putting it together: how this produces quorum loss with no client traffic

1. The original active node accumulates ~850 independent 30-minute timers from the migration's global reloads.
2. ~30 minutes after migration begins, those timers fire in a short window. Each one performs a full-barrier scan (point 2) plus repeated request reads (point 3) against the customer's full-scale storage tree — orders of magnitude larger than anything exercised in the lab reproduction below.
3. This produces a sustained allocation and GC-pressure spike large enough, at the customer's scale, to either trigger the Linux OOM killer on the active node or cause it to miss Raft heartbeats long enough for followers to call an election.
4. Whichever follower becomes the new active node runs its own `setupPluginReload` 5 minutes later. Because the backlog was never pruned, it inherits every past request — now all overdue at once — and immediately performs the same expensive full-barrier scan and cleanup burst that just took down the previous leader.
5. This repeats on each newly elected leader in turn. In a Raft cluster, enough nodes cycling through this OOM/stall-and-lose-leadership pattern in succession is sufficient to lose quorum entirely — without a single CF login, and without any command beyond a supported, once-per-namespace `-scope=global` reload.

The reproduction below independently confirms steps 1–3 (the memory amplification from delayed cleanup). Steps 4–5 (the cross-leader backlog inheritance) are confirmed as present in the pre-fix code by inspection (`setupPluginReload` is invoked from `runUnsealSetupForPrimary`, which runs on every primary/active transition) and are the leading explanation, consistent with all available evidence, for how the failure escalates from a single active-node memory spike to full cluster quorum loss. The lab reproduction below used a 3-node cluster and a storage tree far smaller than the customer's, and did not itself lose leadership — it isolates and measures the amplification mechanism rather than reproducing the full multi-node cascade at the customer's original scale.

## Evidence

A standalone stress harness submitted global reload requests for a deliberately nonexistent auth plugin against a disposable 3-node Vault Enterprise Raft cluster. Vault accepts each request and runs the real global reload bookkeeping and delayed cleanup path, but because no mount uses the given plugin name, no CF (or other) backend is actually restarted — this isolates the cleanup-path cost from the separate cost of actually reloading plugin processes.

Pre-fix timeline (active node), RSS climbing sharply right at the 30-minute mark after the first request (accepted at `18:28:59Z`):

```text
18:58:59Z   440,812 KiB
18:59:04Z   585,456 KiB
18:59:09Z   621,576 KiB
18:59:14Z   709,504 KiB
18:59:19Z   859,112 KiB
18:59:24Z 1,014,548 KiB
18:59:29Z 1,014,776 KiB  (peak)
18:59:34Z   872,864 KiB
```

RSS rose from baseline (~441,988 KiB) to a peak of 1,014,776 KiB — approximately 2.3x baseline, and an increase of roughly 573 MiB — within about 30 seconds of the 30-minute reload-expiration deadline. This is despite the lab's storage tree (250 already-migrated CF mounts on a 3-node cluster) being far smaller than the customer's QA snapshot (thousands of mounts across ~850 namespaces); a full-barrier scan against the customer's actual tree is expected to be substantially more expensive than what this lab run measured.

The post-fix run against the same 850-request workload started at a higher baseline (817,464 KiB, from a different lab session) and peaked at 921,540 KiB — an increase of roughly 102 MiB, with no cleanup-aligned spike and no correlation to the 30-minute mark. Neither run observed a leader change; the lab cluster is not large enough for the pre-fix spike alone to exhaust node memory, so this evidence isolates and confirms the memory-amplification mechanism (points 1–3 above) rather than reproducing full quorum loss.

## Fix

The code fix changes the cleanup lifecycle in three ways that map directly to the root-cause points above:

1. **Dedupe guard on the cleanup schedule** (closes points 1 and 4). The active node now maintains a single managed cleanup schedule per active lifecycle instead of one timer per request: scheduling keeps only the earliest pending deadline, execution is serialized, and all pending work is cancelled when the node stops being active. A newly promoted leader still runs its own startup sweep, but it no longer races hundreds of independently-armed timers against itself or inherits an ever-growing set of them.
2. **Delete reload request records after cleanup** (closes point 3). Expired requests are now deleted from `core/plugins/reload/request/` once their status subtree is successfully cleared (and retried, not silently dropped, if the delete fails). The backlog a newly active node can inherit is bounded by however many requests are genuinely still outstanding, not by every reload ever issued since the cluster was created.
3. **Prefix-scoped `List` instead of a full-barrier scan** (closes point 2). Cleanup now lists only the direct children of `core/plugins/reload/request/` instead of calling `CollectKeysWithPrefix`/`ScanView` from the storage root. Cleanup cost now scales with the number of outstanding reload requests, not with the size of the customer's entire Vault storage tree.

Together, these changes remove the two multiplying factors that made a single, ordinary migration command capable of cascading through every node in the cluster: cleanup work is no longer duplicated per request, and a newly elected leader no longer inherits an unbounded, all-at-once backlog.

## Verification

The stress harness was re-run with an identical workload (850 global reloads against a nonexistent plugin, same 3-node lab topology) against a build containing the fix. Accepted-request count, response codes, and leader stability matched the pre-fix run; the RSS trajectory did not. See Evidence above for the full comparison.

This verification directly confirms the fix removes the memory-amplification effect measured in the lab (root-cause points 1–3). It does not, by itself, re-run the customer's original failure end-to-end at full QA-snapshot scale, so the specific magnitude of improvement at that scale is inferred rather than independently re-measured. The cross-leader backlog-inheritance mechanism (points 4–5) is closed by fix item 2 (expired requests are now deleted) and by the single managed schedule in fix item 1, which is consistent with, but was not separately load-tested against, a multi-leader-failover scenario at the customer's scale.

## Scope and Residual Risk

This fix addresses the delayed global reload *cleanup* path only. It does not change the separate, immediate cost of an external-to-built-in migration itself: reloading many mounted plugin processes and persisting large auth mount tables (`persistAuth`) still happens synchronously across every node participating in a global reload, and remains a real source of load during the migration itself, independent of the cleanup defect described here.

Operationally: `scope=global` reloads a plugin cluster-wide by design. At high namespace or mount counts, pace and batch migration work, and monitor RSS, Raft health, leadership, `vault plugin reload-status`, and Vault logs throughout — even on a build with this fix, since the immediate reload cost above is unrelated to it.

## References

- [Vault plugin reload API](https://developer.hashicorp.com/vault/api-docs/system/plugins-reload)
- Customer CF upgrade session 1 (internal vault-tools runbook; link redacted for customer confidentiality)
- Customer CF upgrade session 2 (internal vault-tools runbook; link redacted for customer confidentiality)
- CF auth plugin reload reproduction (harness, scripts, Terraform — not in this repository): `~/Documents/Vault/CF-Auth/cf-auth-plugin-reload-250-repro.md`
- Stress harness: `~/Documents/Vault/CF-Auth/plugin-reload-cleanup-stress.go`
- Migration and observation scripts: `~/Documents/Vault/CF-Auth/scripts/`
- Terraform cluster definition: `~/Documents/Vault/CF-Auth/terraform/`
- Enterprise implementation and tests: `~/repos/vault-enterprise/vault/plugin_reload_ent.go`, `~/repos/vault-enterprise/vault/plugin_reload_ent_test.go`
- Active/primary setup call site: `~/repos/vault-enterprise/vault/core.go` (`runUnsealSetupForPrimary` → `setupPluginReload`), `~/repos/vault-enterprise/vault/plugin_reload.go`
- Fix commit: `c64fcbab91d9c0394a62fcf60f24357f5bbb6c3c` on `VAULT-46511/<customer>-2.0.x+ent-custom-build-nf`
