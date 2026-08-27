# `vault recover` Panic on Missing Path Argument — Repro

## Overview

`vault recover` panics with `index out of range [0] with length 0` when called with
`-snapshot-id` but no path argument. The command does not validate that a path was
provided before indexing into `args`, so the process crashes instead of returning a
CLI error.

The same command with an invalid path returns a clean `400` error, which is the
expected behavior for the missing-path case as well.

Exact panic string:

```text
panic: runtime error: index out of range [0] with length 0
goroutine 1 [running]:
github.com/hashicorp/vault/command.(*RecoverCommand).Run(0x..., {0x..., 0x2, 0x2})
	.../command/recover_ent.go:86 +0x58b
```

## Objective

Confirm that running `vault recover -snapshot-id <id>` with no path argument triggers
a panic on Vault Enterprise 2.0.3+ent, and that the equivalent call with a path
returns a structured error instead.

## Prerequisites

- A running 3-node Vault Enterprise Raft cluster on Kubernetes at version `2.0.3+ent`.
- `kubectl` and `helm` installed and configured for the target cluster.
- `vault` CLI installed locally (matching the cluster version).
- A Vault root token or a token with at least the following capabilities:
  - `create` on `sys/storage/raft/snapshot-req`
  - `create` on `sys/storage/raft/snapshot-req/<id>/load`
  - `create` and `read` on `<mount>/path` for any KV path used
  - `update` on `<mount>/path` for the `vault recover` call
- A loaded snapshot ID (covered in step 3 below).

### Optional pre-check

```bash
vault status
```

Expected output:

```text
Key                     Value
---                     -----
Seal Type               shamir
Initialized             true
Sealed                  false
Storage Type            raft
HA Enabled              true
HA Mode                 active
Version                 2.0.3+ent
```

## Steps

### 1. Set environment variables

Port-forward the active Vault pod and export credentials. Replace `<namespace>`,
`<pod-name>`, and `<root-token>` with your actual values.

```bash
kubectl port-forward -n <namespace> pod/<pod-name> 8200:8200 &
export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="<root-token>"
export VAULT_SKIP_VERIFY="true"
```

Verify connectivity:

```bash
vault status
```

### 2. Enable a KV v1 mount and write a secret

```bash
vault secrets enable -path=kv kv
vault write kv/repro-secret value="original"
```

Expected output:

```text
Success! Enabled the kv secrets engine at: kv/
Success! Data written to: kv/repro-secret
```

### 3. Take and load a snapshot

Save a snapshot:

```bash
vault operator raft snapshot save /tmp/repro.snap
```

Load the snapshot (non-destructive; does not replace cluster state):

```bash
vault operator raft snapshot load /tmp/repro.snap
```

Retrieve the snapshot ID:

```bash
vault list sys/storage/raft/snapshot-load
vault read sys/storage/raft/snapshot-load/<key>
```

Expected output:

```text
Key          Value
---          -----
id           <snapshot-id>
status       ready
```

Copy the value under `id` and export it:

```bash
export SNAPSHOT_ID="<snapshot-id>"
```

### 4. Reproduce the panic — no path argument

Run `vault recover` with `-snapshot-id` but omit the path argument:

```bash
vault recover -snapshot-id "$SNAPSHOT_ID"
```

Expected (buggy) output:

```text
panic: runtime error: index out of range [0] with length 0
goroutine 1 [running]:
github.com/hashicorp/vault/command.(*RecoverCommand).Run(0x..., {0x..., 0x2, 0x2})
	.../command/recover_ent.go:86 +0x58b
github.com/hashicorp/cli.(*CLI).Run(0x...)
	.../cli.go:265 +0x54c
...
exit status 2
```

The process panics and exits instead of printing a usage error.

### 5. Confirm structured error with an invalid path

Run the same command with a path that does not exist in the snapshot:

```bash
vault recover -snapshot-id "$SNAPSHOT_ID" kv/does-not-exist
```

Expected output:

```text
Error making API request.

URL: PUT http://127.0.0.1:8200/v1/kv/does-not-exist?recover_snapshot_id=<snapshot-id>
Code: 400. Errors:

* no data in the snapshot
```

This confirms the validation path works when a path is supplied — the missing-path
case should produce the same type of CLI error rather than a panic.

### 6. Confirm recovery works with a valid path

```bash
vault recover -snapshot-id "$SNAPSHOT_ID" kv/repro-secret
```

Expected output:

```text
Success! Data written to: kv/repro-secret
```

## Validation

| Step | Command | Expected result |
|------|---------|-----------------|
| No path supplied | `vault recover -snapshot-id "$SNAPSHOT_ID"` | panic (bug) |
| Invalid path supplied | `vault recover -snapshot-id "$SNAPSHOT_ID" kv/does-not-exist` | `400` error |
| Valid path supplied | `vault recover -snapshot-id "$SNAPSHOT_ID" kv/repro-secret` | secret value returned |

## Cleanup

Unload the snapshot and remove the KV mount:

```bash
vault operator raft snapshot unload "$SNAPSHOT_ID"
vault secrets disable kv
```

Kill the port-forward:

```bash
kill %1
```

## References

- [`vault recover` command docs](https://developer.hashicorp.com/vault/docs/commands/recover)
- Panic location: `command/recover_ent.go:86` — `args[0]` indexed without a length check
- Comparable working behavior: `command/read.go` — validates `len(args) != 1` before use
