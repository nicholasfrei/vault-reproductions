# Vault KB: Oracle Enterprise Plugin Callback Resource Leak During Static-Role Rotation

## Overview

This KB explains how failed Oracle Enterprise database-plugin initialization during automatic static-role rotation can leave plugin callback resources behind. In the reported environment, stale and unreachable Oracle configurations caused repeated initialization failures. Vault memory, file descriptors (FDs), and goroutines grew until the active node was terminated for out-of-memory (OOM), causing leadership loss and a Raft election. The issue is tracked as `VAULT-50722`.

The RCA identifies two interacting factors. The underlying leak is incomplete cleanup of Enterprise database-plugin callback resources after initialization failures, combined with the Oracle Enterprise plugin not broadcasting its version. Vault's Enterprise database client sets up a callback gRPC server using configuration metadata, but its graceful shutdown path is gated on the plugin-reported version. When that version is absent, the callback server cleanup path can be skipped. The shared Oracle plugin process can remain running while these failed attempts leave callback sockets, goroutines, and FDs behind.

Vault's May 2026 static-role rotation timeout/retry changes amplified the leak; they were not its root cause. The changes were introduced for `VAULT-43596`, where a hanging MySQL handshake could block the synchronous rotation queue for an entire mount. The bounded wait allows the queue to continue, but repeated retries against stale Oracle configurations can cause more failed initializations and cleanup attempts in less time. The ten-second timeout is therefore an accelerator for accumulation, not the mechanism that makes callback resources leak.

## Symptoms

The customer upgraded Vault from `1.19.9+ent` to `1.21.9+ent` and the Oracle database plugin from community `0.7.0` to Enterprise `0.11.0+ent`. This was a change in both Vault and plugin edition/version, not only a Vault upgrade. The environment had at least 82 database secrets engine mounts generating thousands of Oracle client errors per hour, with many stale or unreachable database configurations. Goroutines accumulated roughly linearly with the number of mounts and role configurations experiencing client errors. Rising RSS, goroutines, and FDs eventually led to OOM termination and leadership loss/Raft election; cluster-state changes such as elections and restarts reset the observed counts.

The customer was using Oracle Instant Client `19.32` and Oracle database plugin `v0.11.0+ent`. Errors across database mounts included:

```text
ORA-01017: invalid username/password
ORA-12154: could not resolve connect identifier
ORA-12514: listener doesn't know requested service
ORA-12543: destination host unreachable
ORA-12545: target host/object does not exist
ORA-28001: password expired
```

## Details

### Enterprise callback setup and cleanup

In the Enterprise database client at `v1.21.9+ent`, `plugin_client_ent.go` checks the configured plugin tier and version. For an official Enterprise plugin it starts a broker `AcceptAndServe` goroutine, creates a callback gRPC server, and sends the broker ID to the plugin through `Setup`. That callback server exposes Vault's Enterprise system-view functionality to the plugin.

Cleanup in `grpc_client_ent.go` calls the plugin's `Close`, then only waits for the callback server to be ready and calls `GracefulStop` when the plugin is official and its reported version is recognized as Enterprise. The version lookup is an RPC; if it returns no version, the Enterprise cleanup condition is false even though the callback server was set up based on the configured version. The Oracle Enterprise plugin's missing version broadcast therefore causes the callback-server graceful cleanup path to be skipped after failed initialization, leaving callback-side resources uncleaned. The RCA observed these callback resources accumulating while the shared Oracle plugin process remained running; do not misreport each leaked callback resource as a newly spawned plugin process.


### How static-role retry behavior amplified the leak

The May 2026 static-role changes, present in the affected Vault release lines, added a timeout/retry path so one slow operation would not block the mount's rotation queue. With many stale Oracle configurations and no retry backoff, those retries repeatedly entered failed database initialization. Failed initialization does not establish a healthy cached connection, so further attempts can create additional client/callback setup work. The ten-second wait bounded how long Vault waited for an individual call; it did not fix cleanup of callback resources left by a failed attempt.

The primary RCA path is failed initialization and cleanup. A cached `UpdateUser` timeout is a separate operation and should not be treated as proof of this initialization leak. The runbook is an investigation procedure: collect measurements to determine whether and where resources grow rather than assuming a particular outcome from a timeout message alone.

## Investigation and evidence limits

Two custom fixes were tested with the customer: one added a threshold-based reaper for client connections that failed to connect without canceling their contexts; the other reverted the May 2026 client-connection management/retry changes for static-role rotations. Customer testing still showed FD and goroutine growth, so neither candidate was sufficient. These tests do not establish a fixed Vault or Oracle plugin release.

Use the [runbook](automated-rotation-leak/oracle-static-role-goroutine-fd-leak-runbook.md) to compare healthy and unreachable-Oracle operation. Its ten-role lab is not a substitute for the customer's scale or a pre-verified reproduction result. Capture per-PID FDs, threads, RSS, Vault goroutines, stack/socket snapshots, errors, and plugin process identity over time. A Vault restart or election resetting counters is not evidence of a fix, and a callback socket/FD increase should not automatically be attributed to a new plugin process.

A final binary, shown in [PR #19091](https://github.com/hashicorp/vault-enterprise/pull/19091), addresses the callback-server cleanup issue by ensuring that the graceful shutdown path is executed even when the plugin version is not broadcast, mitigating the resource-growth problem observed in failed initializations. This was the final fix that proved effective in preventing the accumulation of callback-side resources after failed initializations.

## Triage and mitigation

1. Identify failing database mounts and roles and correlate their errors (including Oracle `ORA-` errors and `timeout exceeded during Initialize`) with time-series Vault memory, FDs, and goroutine counts. The reported environment had 82+ mounts and thousands of Oracle client errors per hour.
2. Measure Vault and Oracle plugin processes separately. Capture PID, FDs, threads, RSS, Vault goroutines, stacks, and socket state. Determine whether callback resources persist while the shared plugin process remains active; do not infer a new plugin process per failed role.
3. Compare healthy operation with unreachable-target operation using the [runbook](automated-rotation-leak/oracle-static-role-goroutine-fd-leak-runbook.md). Record the actual trend, including a plateau if observed. Restart/election resets are not proof of cleanup.
4. Reduce/remove stale and unreachable database configurations and roles, or pause automated rotations against known-bad targets while investigating. This reduces the error volume and the number of repeated failed initializations.
5. Keep Oracle Instant Client `19.32`, which includes the TNS aliasing memory-leak patch, as recommended in the RCA. Oracle Net connect timeouts may be evaluated as a separate network mitigation but do not fix Vault's plugin callback cleanup gap.

Engineering plans to improve Vault plugin lifecycle management for these errors/workflows and add a boolean option to disable static-role rotation retries. These are planned follow-ups, not available fixes in a release identified by this KB. Validation should exercise failed initialization, plugin-reported version behavior, callback server shutdown, and repeated rotations while tracking Vault and plugin process resources. Disabling retries and cleaning stale targets can reduce the pressure, but only lifecycle cleanup addresses the root cause described here.

## Version notes

- The customer changed both Vault (`1.19.9+ent` to `1.21.9+ent`) and the Oracle plugin (community `0.7.0` to Enterprise `0.11.0+ent`); do not attribute the trigger to Vault alone.
- The static-role retry/timeout changes were introduced in May 2026 in Vault `1.19.17`, `1.20.11`, `1.21.6`, and `2.0.1`. They amplified resource accumulation but were not the underlying cleanup defect.
- Candidate custom binaries did not stop the observed FD/goroutine growth. No fixed Vault or Oracle plugin release is established by the RCA.

## Related scenarios

- [Oracle automatic static-role rotation resource-growth runbook](automated-rotation-leak/oracle-static-role-goroutine-fd-leak-runbook.md) — cold-cache outage, automatic queue, and per-process measurements.
- [Oracle plugin `Type()` timeout and misleading API-version mismatch](../../../drafts/archive/oracle-plugin-type-timeout-api-mismatch-kb.md) — a separate `Type()` RPC and cached-plugin investigation (archived draft).

## References

- [Vault PR #13697: static rotation timeout](https://github.com/hashicorp/vault-enterprise/pull/13697) and [1.21 backport #14352](https://github.com/hashicorp/vault-enterprise/pull/14352) — timeout/retry amplifier, not root cause.
- [`v1.21.9+ent` `plugin_client_ent.go`](https://github.com/hashicorp/vault-enterprise/blob/v1.21.9%2Bent/sdk/database/dbplugin/v5/plugin_client_ent.go#L47-L82) — Enterprise callback server setup.
- [`v1.21.9+ent` `grpc_client_ent.go`](https://github.com/hashicorp/vault-enterprise/blob/v1.21.9%2Bent/sdk/database/dbplugin/v5/grpc_client_ent.go#L48-L72) — version-gated callback server cleanup.
- [`v1.21.9+ent` `builtin/logical/database/backend.go`](https://github.com/hashicorp/vault-enterprise/blob/v1.21.9%2Bent/builtin/logical/database/backend.go) — initialization timeout and cleanup call.
- [`v1.21.9+ent` `builtin/logical/database/rotation.go`](https://github.com/hashicorp/vault-enterprise/blob/v1.21.9%2Bent/builtin/logical/database/rotation.go) — automatic queue retries and cached-connection `UpdateUser`.
- [Oracle Enterprise plugin `oracle.go`](https://github.com/hashicorp/vault-plugin-database-oracle-enterprise/blob/v0.11.0%2Bent/oracle.go).
- [Oracle Net timeout parameters](https://docs.oracle.com/en/database/oracle/oracle-database/21/netrf/parameters-for-the-sqlnet.ora.html) — separate network timeout controls; not a callback cleanup fix.
