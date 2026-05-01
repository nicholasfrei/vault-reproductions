# How to Migrate KV Secrets in HashiCorp Vault

This runbook demonstrates a safe, repeatable way to copy a folder subtree and all secrets to another path inside the same KV mount.

Use case covered:

- Copy everything under `kv2/folder1/folderA/` to `kv2/folder2/`

Reference:

- [HashiCorp Support: Migrating KV Secrets](https://support.hashicorp.com/hc/en-us/articles/4411124879891-Migrating-KV-Secrets)

## Customer Context

This is a rare scenario; however, some customers request assistance in migrating KV secrets from one folder subtree to another path in the same mount.

Important notes about this approach:

- This preserves current secret values.
- This does not preserve KV v2 version history or per-version metadata.

If you must preserve metadata/history exactly, use replication or snapshot-based migration patterns (Enterprise-focused), then prune mounts/paths as needed.

## What this validates

- Recursive copy of all keys under one source prefix.
- Writing copied values under a new destination prefix in the same mount.
- Dry-run safety before any write operations.
- Post-copy validation with source and destination key counts.

## Prerequisites

- Vault CLI installed and authenticated.
- `jq` installed.
- `VAULT_ADDR` and `VAULT_TOKEN` exported.
- Policy permissions for both source and destination:
  - `list` and `read` on source.
  - `create`/`update` on destination.

## Step 1: Define migration scope

Set your mount and source/destination prefixes.

```bash
export MOUNT="kv2"
export SRC_PREFIX="folder1/folderA"
export DST_PREFIX="folder2"
```

Notes:

- Do not include leading or trailing `/` in these values.
- The script below normalizes extra slashes anyway.

## Step 2: Create the migration script

Create a local script file.

```bash
cat > /tmp/kv-path-migrate.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Required env vars:
# VAULT_ADDR, VAULT_TOKEN, MOUNT, SRC_PREFIX, DST_PREFIX

for v in VAULT_ADDR VAULT_TOKEN MOUNT SRC_PREFIX DST_PREFIX; do
  if [[ -z "${!v:-}" ]]; then
    echo "ERROR: missing required env var: ${v}" >&2
    exit 1
  fi
done

# Safety controls
DRY_RUN="${DRY_RUN:-true}"           # true|false
OVERWRITE="${OVERWRITE:-false}"      # true|false

trim_slashes() {
  local s="$1"
  s="${s#/}"
  s="${s%/}"
  printf '%s' "$s"
}

MOUNT="$(trim_slashes "$MOUNT")"
SRC_PREFIX="$(trim_slashes "$SRC_PREFIX")"
DST_PREFIX="$(trim_slashes "$DST_PREFIX")"

if [[ "$SRC_PREFIX" == "$DST_PREFIX" ]]; then
  echo "ERROR: source and destination prefixes are identical" >&2
  exit 1
fi

if [[ "$DST_PREFIX" == "$SRC_PREFIX"/* ]]; then
  echo "ERROR: destination cannot be inside source (infinite recursion risk)" >&2
  exit 1
fi

MOUNT_JSON_KEY="${MOUNT}/"
KV_VERSION="$(vault secrets list -format=json | jq -r --arg m "$MOUNT_JSON_KEY" '.[$m].options.version // "1"')"

if [[ "$KV_VERSION" != "1" && "$KV_VERSION" != "2" ]]; then
  echo "ERROR: unable to determine KV version for mount ${MOUNT}/" >&2
  exit 1
fi

echo "INFO: mount=${MOUNT}/ version=${KV_VERSION} src=${SRC_PREFIX} dst=${DST_PREFIX} dry_run=${DRY_RUN} overwrite=${OVERWRITE}"

copy_count=0
skip_count=0
error_count=0

dst_exists() {
  local dst_key="$1"
  if vault kv get -format=json "${MOUNT}/${dst_key}" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

write_secret() {
  local src_key="$1"
  local dst_key="$2"
  local payload
  local endpoint

  if [[ "$OVERWRITE" != "true" ]] && dst_exists "$dst_key"; then
    echo "SKIP: destination exists (${MOUNT}/${dst_key})"
    skip_count=$((skip_count + 1))
    return 0
  fi

  if [[ "$KV_VERSION" == "2" ]]; then
    payload="$(vault kv get -format=json "${MOUNT}/${src_key}" | jq -c '{data: .data.data}')"
    endpoint="${VAULT_ADDR%/}/v1/${MOUNT}/data/${dst_key}"
  else
    payload="$(vault kv get -format=json "${MOUNT}/${src_key}" | jq -c '.data')"
    endpoint="${VAULT_ADDR%/}/v1/${MOUNT}/${dst_key}"
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "DRY-RUN: copy ${MOUNT}/${src_key} -> ${MOUNT}/${dst_key}"
    return 0
  fi

  code="$(curl -sS -o /dev/null -w '%{http_code}' \
    -X POST \
    -H "X-Vault-Token: ${VAULT_TOKEN}" \
    -H 'Content-Type: application/json' \
    --data "$payload" \
    "$endpoint")"

  if [[ "$code" == "200" || "$code" == "204" ]]; then
    echo "OK: ${MOUNT}/${src_key} -> ${MOUNT}/${dst_key}"
    copy_count=$((copy_count + 1))
  else
    echo "ERROR: failed copy ${MOUNT}/${src_key} -> ${MOUNT}/${dst_key} (HTTP ${code})" >&2
    error_count=$((error_count + 1))
  fi
}

recurse_copy() {
  local rel_dir="$1"
  local list_path
  local entries

  if [[ -n "$rel_dir" ]]; then
    list_path="${MOUNT}/${SRC_PREFIX}/${rel_dir}"
  else
    list_path="${MOUNT}/${SRC_PREFIX}"
  fi

  # kv list returns child key names; folder entries end with '/'
  entries="$(vault kv list -format=json "$list_path" 2>/dev/null || true)"
  if [[ -z "$entries" || "$entries" == "null" ]]; then
    return 0
  fi

  while IFS= read -r entry; do
    if [[ "$entry" == */ ]]; then
      recurse_copy "${rel_dir}${entry}"
      continue
    fi

    local rel_key="${rel_dir}${entry}"
    local src_key="${SRC_PREFIX}/${rel_key}"
    local dst_key="${DST_PREFIX}/${rel_key}"

    write_secret "$src_key" "$dst_key"
  done < <(printf '%s' "$entries" | jq -r '.[]')
}

recurse_copy ""

echo "---"
echo "SUMMARY: copied=${copy_count} skipped=${skip_count} errors=${error_count} dry_run=${DRY_RUN}"

if [[ "$error_count" -gt 0 ]]; then
  exit 2
fi
EOF
```

Make it executable:

```bash
chmod +x /tmp/kv-path-migrate.sh
```

## Step 3: Run a dry-run first (recommended)

```bash
DRY_RUN=true OVERWRITE=false /tmp/kv-path-migrate.sh
```

Expected result:

- `DRY-RUN` lines showing planned source to destination copies.
- Summary line with `errors=0`.

## Step 4: Execute the copy

```bash
DRY_RUN=false OVERWRITE=false /tmp/kv-path-migrate.sh
```

Expected result:

- `OK` lines for each copied secret.
- Summary line with `errors=0`.

If you need to replace existing destination keys:

```bash
DRY_RUN=false OVERWRITE=true /tmp/kv-path-migrate.sh
```

## Step 5: Validate source vs destination counts

Count leaf secrets recursively for source and destination.

```bash
count_leaf_keys() {
  local mount="$1"
  local prefix="$2"
  local total=0

  walk() {
    local p="$1"
    local entries
    entries="$(vault kv list -format=json "${mount}/${p}" 2>/dev/null || true)"
    [[ -z "$entries" || "$entries" == "null" ]] && return 0

    while IFS= read -r item; do
      if [[ "$item" == */ ]]; then
        walk "${p}/${item%/}"
      else
        total=$((total + 1))
      fi
    done < <(printf '%s' "$entries" | jq -r '.[]')
  }

  walk "$prefix"
  echo "$total"
}

SRC_COUNT="$(count_leaf_keys "$MOUNT" "$SRC_PREFIX")"
DST_COUNT="$(count_leaf_keys "$MOUNT" "$DST_PREFIX")"
echo "source_count=${SRC_COUNT} destination_count=${DST_COUNT}"
```

Optional content spot-check:

```bash
vault kv get "${MOUNT}/${SRC_PREFIX}/<some/key>"
vault kv get "${MOUNT}/${DST_PREFIX}/<same/key>"
```

## Step 6: Optional cleanup after verification

If your migration intent is move/rename (not duplicate), delete source keys only after validation and backup/snapshot confirmation.

For KV v2, deletion options differ:

- Soft delete latest values:

```bash
vault kv delete "${MOUNT}/${SRC_PREFIX}/<key>"
```

- Remove all metadata/history for a key (destructive):

```bash
vault kv metadata delete "${MOUNT}/${SRC_PREFIX}/<key>"
```

## Common pitfalls

- Path confusion:
  - Use mount-relative paths in CLI commands, for example `kv2/folder1/folderA/app1`.
- Permissions:
  - Missing `list` on source or `create`/`update` on destination causes failures.
- KV v2 assumptions:
  - Manual copy scripts duplicate current values only, not historical versions.
- Recursion hazard:
  - Never set destination under source prefix.

## Conclusion

For same-mount path migration such as `kv2/folder1/folderA/` to `kv2/folder2/`, the recommended operational method is a recursive copy script with dry-run and validation.

When strict preservation of KV v2 metadata/version history is required, plan for replication/snapshot-based migration strategies rather than manual path copy.