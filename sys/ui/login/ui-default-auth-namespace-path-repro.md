# VAULT-40617: UI Default Auth `namespace_path` Canonicalization Repro

## Overview

This runbook deploys a 3-node Vault Enterprise Raft cluster on EC2 (AWS KMS auto-unseal) and reproduces the `sys/internal/ui/default-auth-methods` returning `data: null` after upgrading from 1.21.1+ent (or earlier) to 2.0.x+ent. Customers are facing issues with the default auth method config when upgrading to 2.0.x+ent and this runbook shows the behavior.  

## Objective

1. Deploy a 3-node Vault 1.21.1+ent Raft cluster with AWS KMS auto-unseal using Terraform.
2. Initialize the cluster and write a default auth rule with `namespace_path=""` (empty string).
3. Confirm the rule is readable on 1.21.1+ent and `sys/internal/ui/default-auth-methods` returns data.
4. Upgrade one node to 2.0.3+ent and confirm `sys/internal/ui/default-auth-methods` returns `data: null`.
5. Confirm that `vault read sys/config/ui/login/default-auth/<name>` still returns the rule (name-based lookup is unaffected).
6. Apply the delete-and-recreate workaround and confirm `sys/internal/ui/default-auth-methods` returns data again.

## Prerequisites

- AWS CLI configured on your workstation.
- AWS permissions to create EC2 instances, security groups, IAM roles, instance profiles, and KMS keys.
- Terraform >= 1.6.0 on your workstation.
- An existing EC2 key pair in the target region.
- Vault Enterprise license text (`.hclic` content).
- `jq` on your workstation.

Do not commit `terraform.tfvars`, root tokens, or license content.

## Architecture

```text
us-east-1 (default VPC, single AZ)

  vault-ui-login-repro-vault-1   (t3.medium, Amazon Linux 2023)
  vault-ui-login-repro-vault-2   (t3.medium, Amazon Linux 2023)
  vault-ui-login-repro-vault-3   (t3.medium, Amazon Linux 2023)

  All nodes: raft storage, awskms auto-unseal (shared KMS key)
  vault-1: initial leader candidate, cluster bootstrap target
  vault-2/3: join vault-1 via raft, run as performance standbys
```

All infrastructure is managed by Terraform. The KMS key, IAM role, instance profile, and security group are created by Terraform alongside the EC2 instances.

## Step 1: Configure Terraform

Run this from your workstation inside the `terraform/` directory.

```bash
cd sys/ui/login/terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and set at minimum:

```hcl
key_name       = "<ec2_key_pair_name>"
admin_ssh_cidr = "<your_public_ip>/32"
vault_version  = "1.21.1+ent"
```

Set the license via an environment variable so it is never written to disk:

```bash
export TF_VAR_vault_license="$(cat /path/to/vault.hclic)"
```

## Step 2: Deploy the cluster

```bash
terraform init
terraform apply -auto-approve
```

Terraform creates the KMS key, IAM role and instance profile, security group, and 3 EC2 instances. Each instance runs the user-data script which installs Vault, writes the config and systemd unit, and starts the Vault service.

Capture the public IPs from the output:

```bash
terraform output
```

## Step 3: Set workstation environment variables

Confirm vault-1 is up and waiting to be initialized (sealed, not initialized):

```bash
vault status
```

Expected output:

```text
Key                      Value
---                      -----
Seal Type                awskms
Recovery Seal Type       shamir
Initialized              false
Sealed                   true
...
```

## Step 4: Initialize the cluster on vault-1

```bash
export VAULT_ADDR=http://127.0.0.1:8200
vault operator init -format=json > /tmp/vault-init.json

cat /tmp/vault-init.json
```

Save the root token:

```bash
export VAULT_TOKEN=$(jq -r '.root_token' /tmp/vault-init.json)
```

Confirm vault-1 is active:

```bash
vault status
```

Expected output:

```text
Key                      Value
---                      -----
Seal Type                awskms
Initialized              true
Sealed                   false
...
HA Mode                  active
```

## Step 5: Enable a test auth method

Enable `userpass` so the default auth rule has a valid target to reference.

```bash
vault auth enable userpass
```

Confirm:

```bash
vault auth list
```

Expected output includes:

```text
Path         Type        ...
----         ----        ---
token/       token       ...
userpass/    userpass    ...
```

## Step 6: Write the default auth rule on 1.21.1+ent

Write the rule targeting the root namespace by passing an empty `namespace_path`. This triggers the buggy code path: the write handler canonicalizes the empty string to `""`, then `upsertRuleInTxn` normalizes it to `namespace.RootNamespaceID` = `"root"` and persists that value to Raft storage.

```bash
vault write sys/config/ui/login/default-auth/oidc \
  namespace_path="" \
  default_auth_type="userpass" \
  backup_auth_types="token" \
  disable_inheritance=false
```

Confirm the rule is stored. The read endpoint returns `namespace_path = root/` because `handleConfigUILoginDefaultAuthRead` calls `Canonicalize()` on the display value, but the underlying storage has `"root"`:

```bash
vault read sys/config/ui/login/default-auth/oidc
```

Expected output:

```text
Key                    Value
---                    -----
backup_auth_types      [token]
default_auth_type      userpass
disable_inheritance    false
namespace_path         root/
```

Confirm the unauthenticated UI endpoint returns data on 1.21.1+ent:

```bash
curl -s "http://127.0.0.1:8200/v1/sys/internal/ui/default-auth-methods" | jq .data
```

Expected output (works on 1.21.1+ent because the active node populated memdb correctly from the write):

```json
{
  "backup_auth_types": ["token"],
  "default_auth_type": "userpass",
  "disable_inheritance": false
}
```

## Step 7: Upgrade vault-1 to 2.0.3+ent

Stop Vault, replace the binary, and restart:

```bash
sudo systemctl stop vault

curl -O https://releases.hashicorp.com/vault/2.0.3+ent/vault_2.0.3+ent_linux_amd64.zip
unzip vault_2.0.3+ent_linux_amd64.zip
sudo mv vault /usr/local/bin/vault
sudo chmod 755 /usr/local/bin/vault

sudo systemctl start vault
vault version
```

Expected output:

```text
Vault v2.0.3+ent (...)
```

Wait for vault-1 to rejoin and elect a leader:

```bash
vault status
```

Expected:

```text
Version     2.0.3+ent
Sealed      false
HA Mode     active
```

## Step 8: Confirm the bug

`vault read` still works because it looks up the rule by name — the name index in memdb is unaffected:

```bash
vault read sys/config/ui/login/default-auth/oidc
```

Expected: returns the rule with `namespace_path = root/`.

`sys/internal/ui/default-auth-methods` returns `data: null` because it looks up by `namespace_path`. On startup, `Manager.Setup()` loaded the rule from storage with `NamespacePath = "root"`. The `upsertRuleInTxn` normalization guard only fires when `NamespacePath == ""`, so `"root"` bypasses it and enters memdb as `"root"`. The lookup uses `Canonicalize("") = ""` → guard fires → looks up `"root/"` → no match:

```bash
curl -s "http://127.0.0.1:8200/v1/sys/internal/ui/default-auth-methods" | jq .data
```

Expected output (bug reproduced):

```json
null
```

## Step 9: Apply the workaround and confirm resolution

Delete the existing rule and recreate it. The write handler calls `namespace.Canonicalize("root")` = `"root/"` and persists that to storage. On the next `Setup()` load, `"root/"` enters memdb as `"root/"`, and the `GetRuleByNamespace("") → "root/"` lookup succeeds:

```bash
vault delete sys/config/ui/login/default-auth/oidc

vault write sys/config/ui/login/default-auth/oidc \
  namespace_path="root" \
  default_auth_type="userpass" \
  backup_auth_types="token" \
  disable_inheritance=false
```

Confirm the UI endpoint returns data:

```bash
curl -s "http://127.0.0.1:8200/v1/sys/internal/ui/default-auth-methods" | jq .data
```

Expected output (workaround confirmed):

```json
{
  "backup_auth_types": ["token"],
  "default_auth_type": "userpass",
  "disable_inheritance": false
}
```

## Validation summary

| Step | Action | Expected on 1.21.1+ent | Expected on 2.0.3+ent (post-upgrade) |
|------|--------|------------------------|--------------------------------------|
| Write | `namespace_path=""` | succeeds | — |
| Read | `vault read .../oidc` | `namespace_path = root/` | `namespace_path = root/` (name lookup, unaffected) |
| UI endpoint | `GET /v1/sys/internal/ui/default-auth-methods` | `data` non-null | `data: null` (bug) |
| Workaround | delete + recreate with `namespace_path="root"` | — | `data` non-null |

## Cleanup

Remove the Vault Enterprise resources from your workstation:

```bash
cd sys/ui/login/terraform
terraform destroy
```

Terraform destroys the EC2 instances, security group, IAM role and instance profile, and schedules the KMS key for deletion (7-day pending window by default).

Remove the init output from disk:

```bash
rm -f /tmp/vault-init.json
```

## Summary

### Root cause

When a default auth rule is created for the root namespace on a pre-fix release (1.21.0–1.21.2+ent, 1.20.0–1.20.7+ent), the in-memory manager's `upsertRuleInTxn` normalizes an empty or unset `namespace_path` to `namespace.RootNamespaceID` = `"root"` (no trailing slash) and persists that value to storage:

```go
// vault/ui_default_auth/manager_ent.go — pre-fix
if rule.NamespacePath == "" {
    rule.NamespacePath = namespace.RootNamespaceID  // "root"
}
```

`"root"` is stored in the Raft snapshot as the `namespace_path` JSON field.

After upgrade to a fixed release (1.20.8+ent, 1.21.3+ent, or any 2.0.x+ent), `Manager.Setup()` reads those rules from storage and calls `upsertRuleInTxn`. The guard only fires when `NamespacePath == ""`. Because the stored value is `"root"` (non-empty), no normalization is applied. The rule enters the memdb cache with key `"root"`.

All lookups in the fixed code use `namespace.Canonicalize(namespace.RootNamespaceID)` = `"root/"`. The key `"root"` ≠ `"root/"`, so the lookup misses and `sys/internal/ui/default-auth-methods` returns `data: null`.

The authenticated `vault read sys/config/ui/login/default-auth/<name>` endpoint looks up rules by **name**, not by `namespace_path`, so it returns data correctly even on the broken cluster. This can mislead operators into thinking the rule is intact when the UI endpoint that browsers actually use is returning null.

### Why `vault read` works but `sys/internal/ui/default-auth-methods` does not

- `vault read sys/config/ui/login/default-auth/<name>` → `handleConfigUILoginDefaultAuthRead` → `GetRuleLocked(name)` → memdb lookup by name index → **hit**
- `curl /v1/sys/internal/ui/default-auth-methods` → `handleConfigUILoginDefaultMethods` → `GetRuleByNamespace(namespace.Canonicalize(ns.Path))` → for root, `ns.Path = ""` → `Canonicalize("") = ""` → hits empty-guard → looks up `"root/"` → **miss** → `data: null`

### Why the write handler does not exhibit the same bug

The write handler (`handleConfigUILoginDefaultAuthUpdate`) calls `namespace.Canonicalize(nsName)` on the user-supplied value before passing it to storage. So `namespace_path=""` or `namespace_path="root"` both produce `"root/"` on disk when written through the fixed write path. The bug is specific to rules written before the fix and then loaded on a fixed binary.

### Fix

PR #12115 (`VAULT-40617`) updated all three lookup paths in `manager_ent.go` to use `namespace.Canonicalize(namespace.RootNamespaceID)` = `"root/"`:

```go
// vault/ui_default_auth/manager_ent.go — fixed
if rule.NamespacePath == "" {
    rule.NamespacePath = namespace.Canonicalize(namespace.RootNamespaceID)  // "root/"
}
```

This ensures the stored key and lookup key agree whether the rule was created with `""`, `"root"`, or `"root/"`. It does not migrate pre-existing stale storage entries. The delete-and-recreate workaround is still required for rules that were written before the fix.

### Affected versions

- 1.20.0+ent – 1.20.7+ent (when upgrading to any newer version)
- 1.21.0+ent – 1.21.2+ent (when upgrading to any newer version)

### Fixed versions

- 1.20.8+ent and newer
- 1.21.3+ent and newer
- 2.0.0+ent and newer (but data written on buggy 1.20.x/1.21.x still needs remediation after upgrade)

### Customer workaround

Delete and recreate the rule. The write handler canonicalizes the stored `namespace_path` to `"root/"`, which the fixed lookup path also uses:

```shell
vault delete sys/config/ui/login/default-auth/<name>
vault write sys/config/ui/login/default-auth/<name> \
  namespace_path="root" \
  default_auth_type="<type>" \
  backup_auth_types="<type>" \
  disable_inheritance=false
```

## References

- Source fix: `vault/ui_default_auth/manager_ent.go` — `upsertRuleInTxn`, `GetRuleByNamespace`, `RuleExistForNamespace`
- Source fix: `vault/logical_system_ui_default_auth_ent.go` — `handleConfigUILoginDefaultAuthRead`
- Regression tests: `vault/external_tests/perfstandby/perfstandby_ui_default_auth_config_ent_test.go`
- `helper/namespace/namespace.go` — `RootNamespaceID = "root"`, `Canonicalize()` adds trailing `/`
- PR #12115 (main fix), PR #12122 (1.20.x backport), PR #12123 (1.21.x backport)
- VAULT-40617, VAULT-34562, VAULT-34563
- AWS KMS Auto-Unseal setup reference: [sys/seal/awskms/awskms-auto-unseal-runbook.md](../../seal/awskms/awskms-auto-unseal-runbook.md)
- https://developer.hashicorp.com/vault/docs/configuration/seal/awskms
