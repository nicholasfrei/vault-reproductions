# Vault KV v1 Secret Recovery Runbook

This runbook demonstrates how to recover a deleted or overwritten KV v1 secret from a loaded Raft snapshot.

This feature is Vault Enterprise only and requires Vault 1.20.0+.

## What this validates

- You can load a snapshot without restoring the entire cluster.
- You can inspect snapshot load status.
- You can recover one KV v1 path from the loaded snapshot.

## Prerequisites

- Vault Enterprise 1.20.0 or newer.
- Integrated storage (Raft).
- `vault` CLI authenticated as a token with permission to:
  - save/load/unload snapshots (`sys/storage/raft/snapshot*`)
  - read/list/recover on your KV v1 mount path.
- `jq` installed (optional, but helpful for parsing command output).

Optional pre-check:

```bash
vault status
```

Expected output (example):

```text
Key                     Value
---                     -----
Seal Type               shamir
Initialized             true
Sealed                  false
Storage Type            raft
HA Enabled              true
HA Mode                 active
Version                 1.21.0+ent
```

Notes:
- Exact values such as cluster ID, build date, and raft indexes will vary.
- `Sealed` should be `false` before continuing.

Important limitations:
- Recovery support in this runbook is for KV v1 only.
- Snapshot load/unload operations are root-namespace operations.
- You can only load one snapshot at a time.
- Snapshot must come from the same cluster and unseal key set.

## Step 1: Enable a KV v1 mount (test path)

If you already have a KV v1 test mount, skip this step.

```bash
vault secrets enable -path=kv-v1 -version=1 kv
```

Expected output:

```text
Success! Enabled the kv secrets engine at: kv-v1/
```

Verify mount type/version:

```bash
vault secrets list -detailed | grep -A5 '^kv-v1/'
```

Expected output (example):

```text
kv-v1/        kv           ...   map[version:1]   ...
```

Notes:
- Output is wide and may wrap.
- The important part is `map[version:1]`, confirming KV v1.

## Step 2: Create baseline secret data

```bash
vault write kv-v1/app/config username="appuser" password="before-snapshot"
vault read kv-v1/app/config
```

Expected: `password` is `before-snapshot`.

Expected output (example):

```text
Success! Data written to: kv-v1/app/config

Key                 Value
---                 -----
refresh_interval    768h
password            before-snapshot
username            appuser
```

## Step 3: Save a raft snapshot

```bash
SNAP_FILE=/tmp/kv-v1-recovery.snap
vault operator raft snapshot save "$SNAP_FILE"
ls -lh "$SNAP_FILE"
```

Expected: snapshot file exists and is non-zero size.

Expected output (example):

```text
-rw-------    1 vault    vault     121.9K Mar 16 19:19 /tmp/kv-v1-recovery.snap
```

## Step 4: Simulate data loss or bad change

Choose one scenario:

Option A: delete the secret

```bash
vault delete kv-v1/app/config
vault read kv-v1/app/config
```

Expected: read fails with not found.

Expected output:

```text
Success! Data deleted (if it existed) at: kv-v1/app/config
No value found at kv-v1/app/config
```

Option B: overwrite with bad value

```bash
vault write kv-v1/app/config username="appuser" password="bad-value"
vault read kv-v1/app/config
```

Expected: `password` is `bad-value`.

Expected output:

```text
Success! Data written to: kv-v1/app/config

Key                 Value
---                 -----
refresh_interval    768h
password            bad-value
username            appuser
```

## Step 5: Load snapshot for secret recovery

```bash
vault operator raft snapshot load "$SNAP_FILE"
```

Example output fields include `snapshot_id` and `status`.

Expected output (example):

```text
Key            Value
---            -----
cluster_id     3165db89-c3ac-298a-b150-16e8a4a3f797
created_at     2026-03-16T19:20:07.163774926Z
expires_at     2026-03-19T19:20:07.163774926Z
snapshot_id    c76b3656-74e2-27e3-7da6-697aaa245ddc
status         loading
```

Notes:
- `status` is often `loading` initially.
- You will use `snapshot_id` in later steps.

Capture the snapshot ID from the output and export it:

```bash
export SNAPSHOT_ID="<paste-snapshot-id-here>"
```

You can also confirm a loaded snapshot exists:

```bash
vault list /sys/storage/raft/snapshot-load
```

Expected output (example):

```text
Keys
----
c76b3656-74e2-27e3-7da6-697aaa245ddc
```

## Step 6: Wait for snapshot status `ready`

```bash
vault read /sys/storage/raft/snapshot-load/$SNAPSHOT_ID
```

If status is still `loading`, wait a few seconds and re-run.

Expected output (example):

```text
Key            Value
---            -----
cluster_id     3165db89-c3ac-298a-b150-16e8a4a3f797
created_at     2026-03-16T19:20:07.163774926Z
expires_at     2026-03-19T19:20:07.163774926Z
snapshot_id    c76b3656-74e2-27e3-7da6-697aaa245ddc
status         ready
```

## Step 7: Recover the secret path

Recover in place:

```bash
vault recover -snapshot-id "$SNAPSHOT_ID" kv-v1/app/config
```

Expected output:

```text
Success! Data written to: kv-v1/app/config
```

Validate:

```bash
vault read kv-v1/app/config
```

Expected: the data matches the snapshot state (`password=before-snapshot`).

Expected output:

```text
Key                 Value
---                 -----
refresh_interval    768h
password            before-snapshot
username            appuser
```

## Step 8: Optional recovery to a different path

You can recover from one path and write to another path on the same mount.

```bash
vault recover \
  -snapshot-id "$SNAPSHOT_ID" \
  -from kv-v1/app/config \
  kv-v1/app/config-recovered

vault read kv-v1/app/config-recovered
```

Expected output:

```text
Success! Data written to: kv-v1/app/config-recovered

Key                 Value
---                 -----
refresh_interval    768h
password            before-snapshot
username            appuser
```

## Step 9: Unload the snapshot

```bash
vault operator raft snapshot unload "$SNAPSHOT_ID"
vault list /sys/storage/raft/snapshot-load
```

Expected: the loaded snapshot ID is no longer listed.

Expected output (example):

```text
No value found at sys/storage/raft/snapshot-load
```

## Optional least-privilege policy snippet for recovery

```hcl
path "sys/storage/raft/snapshot" {
  capabilities = ["read"]
}

path "sys/storage/raft/snapshot-load" {
  capabilities = ["create", "update", "list"]
}

path "sys/storage/raft/snapshot-load/*" {
  capabilities = ["read", "delete"]
}

path "kv-v1/*" {
  capabilities = ["read", "list", "recover"]
}
```

Adjust capabilities to your internal controls.

## Troubleshooting

- `permission denied` on recover:
  - Ensure policy has `recover` capability on the exact path.
- Snapshot load stuck in `error`:
  - Check Vault logs.
  - If leadership changed, unload/reload snapshot.
- `unsupported operation` on mount path:
  - Confirm the mount is KV v1, not KV v2.
- Cannot load snapshot:
  - Verify same cluster/unseal keys and that no other snapshot is already loaded.

## Cleanup

```bash
vault operator raft snapshot unload "$SNAPSHOT_ID" 2>/dev/null || true
vault secrets disable kv-v1
rm -f "$SNAP_FILE"
```