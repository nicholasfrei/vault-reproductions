# Vault KV v2 Soft-Delete, Destroy, Undelete, and Recovery Runbook

This runbook validates KV v2 version lifecycle behavior and how to recover from soft-delete scenarios.

It covers:
- Writing multiple secret versions.
- Soft-deleting latest and specific versions.
- Restoring soft-deleted versions with undelete.
- Permanently destroying selected versions.
- Understanding when recovery is no longer possible.

## Prerequisites

- Vault CLI authenticated with a token that can manage a KV v2 mount.
- Vault 1.10+ (behavior shown here is standard for current supported versions).
- `jq` installed (optional, only used for easier output inspection).

This command confirms Vault is reachable and unsealed before you begin.

```bash
vault status
```

Expected output (example):

```text
Key             Value
---             -----
Initialized     true
Sealed          false
Version         1.21.0
```

## Step 1: Create an isolated KV v2 mount

This command enables a dedicated KV v2 mount so the runbook does not affect existing data.

```bash
vault secrets enable -path=kv-v2-lifecycle kv-v2
```

Expected output:

```text
Success! Enabled the kv-v2 secrets engine at: kv-v2-lifecycle/
```

This command verifies the mount version is KV v2.

```bash
vault secrets list -detailed | grep -i 'kv-v2-lifecycle/'
```

Expected output includes `options map[version:2]`.

## Step 2: Write multiple versions of one secret

This command writes version 1 of the secret.

```bash
vault kv put kv-v2-lifecycle/app/config username=appuser password=v1
```

Expected output includes `version         1`.

This command writes version 2 of the same secret.

```bash
vault kv put kv-v2-lifecycle/app/config username=appuser password=v2
```

Expected output includes `version         2`.

This command writes version 3 of the same secret.

```bash
vault kv put kv-v2-lifecycle/app/config username=appuser password=v3
```

Expected output includes `version         3`.

This command reads the latest version to validate baseline state.

```bash
vault kv get kv-v2-lifecycle/app/config
```

Expected output (example):

```text
====== Metadata ======
Key                Value
---                -----
version            3

====== Data ======
Key       Value
---       -----
password  v3
username  appuser
```

## Step 3: Soft-delete the latest version

This command performs a soft delete of the current latest version.

```bash
vault kv delete kv-v2-lifecycle/app/config
```

Expected output:

```text
Success! Data deleted (if it existed) at: kv-v2-lifecycle/app/config
```

This command checks metadata to confirm version 3 has a deletion timestamp.

```bash
vault kv metadata get kv-v2-lifecycle/app/config
```

Expected output includes a non-empty `deletion_time` for version 3 and `destroyed` set to `false`.

Result:
- Latest version is soft-deleted and can still be undeleted.

Rollback note:
- If this delete was accidental, recover now with `vault kv undelete -versions=3 kv-v2-lifecycle/app/config`.

## Step 4: Read behavior after latest soft-delete

This command attempts to read the latest version after soft-delete.

```bash
vault kv get kv-v2-lifecycle/app/config
```

Expected output is to not see the data, but you will see metadata at this path.

This command reads a known-good prior version.

```bash
vault kv get -version=2 kv-v2-lifecycle/app/config
```

Expected output shows `password=v2`.

Result:
- Deleted latest versions are not returned by default reads.
- Older non-deleted versions remain readable by explicit version.

## Step 5: Undelete a soft-deleted version

This command restores version 3.

```bash
vault kv undelete -versions=3 kv-v2-lifecycle/app/config
```

Expected output:

```text
Success! Data written to: kv-v2-lifecycle/undelete/app/config
```

Note:
- Some Vault versions print a generic success message for undelete and may not display the final path consistently.

This command validates version 3 is readable again.

```bash
vault kv get -version=3 kv-v2-lifecycle/app/config
```

Expected output shows `password=v3`.

Result:
- Soft-delete recovery is successful.

## Step 6: Soft-delete specific versions

This command soft-deletes versions 1 and 2 without touching version 3.

```bash
vault kv delete -versions=1,2 kv-v2-lifecycle/app/config
```

Expected output:

```text
Success! Data deleted (if it existed) at: kv-v2-lifecycle/app/config
```

This command confirms deletion metadata per version.

```bash
vault kv metadata get kv-v2-lifecycle/app/config
```

Expected output includes:
- Version 1: `deletion_time` set, `destroyed=false`
- Version 2: `deletion_time` set, `destroyed=false`
- Version 3: `deletion_time` empty, `destroyed=false`

Rollback note:
- Accidental delete of versions 1 or 2 can be reversed with `vault kv undelete -versions=1,2 kv-v2-lifecycle/app/config`.

## Step 7: Permanently destroy a version

WARNING: The next command is destructive and permanent for the selected version.

This command permanently destroys version 2.

```bash
vault kv destroy -versions=2 kv-v2-lifecycle/app/config
```

Expected output:

```text
Success! Data written to: kv-v2-lifecycle/destroy/app/config
```

Note:
- Success-path text can vary by Vault version, but metadata is the source of truth.

This command verifies the destroyed flag is set.

```bash
vault kv metadata get kv-v2-lifecycle/app/config
```

Expected output for version 2 includes `destroyed=true`.

This command attempts to undelete the destroyed version.

```bash
vault kv undelete -versions=2 kv-v2-lifecycle/app/config
```

Expected output indicates no recovery of destroyed data.

Result:
- Destroyed versions cannot be recovered with undelete.

## Step 8: Optional metadata delete (removes all versions)

Optional: Run this only if you want to remove the secret metadata and all version history.

WARNING: The next command is destructive for all versions and metadata at this path.

This command deletes all metadata and version history for the key.

```bash
vault kv metadata delete kv-v2-lifecycle/app/config
```

Expected output:

```text
Success! Data deleted (if it existed) at: kv-v2-lifecycle/metadata/app/config
```

This command verifies the key no longer exists.

```bash
vault kv metadata get kv-v2-lifecycle/app/config
```

Expected output is `No value found` or a not found error.

Result:
- No version history remains at that key path.

Rollback note:
- There is no in-place rollback for metadata delete; restoration requires external backup/snapshot workflow.

## Conclusion

This runbook confirms KV v2 lifecycle semantics:
- `delete` is recoverable (soft-delete).
- `undelete` restores soft-deleted versions.
- `destroy` is permanent for selected versions.
- `metadata delete` removes the key and all version history.

Use this as an operator reference before incident response changes on production KV v2 paths.

## Cleanup

This command removes the temporary mount created for validation.

```bash
vault secrets disable kv-v2-lifecycle
```

Expected output:

```text
Success! Disabled the secrets engine (if it existed) at: kv-v2-lifecycle/
```
