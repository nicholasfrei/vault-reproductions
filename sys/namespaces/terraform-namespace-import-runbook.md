# Terraform import of a mount under an already-managed namespace

## Objective

The customer in [VAULT-34835](https://hashicorp.atlassian.net/browse/VAULT-34835) wants to import an existing Vault namespace into Terraform, then import a secrets engine inside it. They expect the mount to be added to Terraform state without changing the namespace that Terraform already manages. Instead, with `TERRAFORM_VAULT_NAMESPACE_IMPORT` set for the mount import, Vault provider `4.7.0` also plans to create the parent namespace inside itself as `test/test`.

This runbook creates a disposable `test` namespace, imports it, and shows the unexpected plan for the mount import. 

Vault version: `2.0.4+ent`
Vault provider version: `4.7.0`

## Prerequisites

- A running Vault Enterprise cluster
- `vault` and a Terraform CLI version supporting configuration-driven `import` blocks (Terraform `1.5` or later).
- `VAULT_ADDR` and `VAULT_TOKEN` set in your shell for the target lab.

Run all commands on the workstation with Vault and Terraform access. Terraform files and state stay in a separate temporary working directory.

## Step 1: Create the Namespace and Mount

Check that you are connected to the disposable Vault lab and that `test/` does not already exist. Stop rather than reusing an existing namespace: cleanup will delete it. Then create `test` and a KV v2 mount within it. Keep `REPRO_DIR` set in the same shell for the remaining steps.

```bash
unset VAULT_NAMESPACE TERRAFORM_VAULT_NAMESPACE_IMPORT TF_CLI_CONFIG_FILE
vault status
vault namespace list
```

Only if `test/` is absent, continue:

```bash
export REPRO_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vault-34835.XXXXXX")"
cd "$REPRO_DIR"

vault namespace create test
vault secrets enable -namespace=test -path=kv_secret -version=2 kv
vault secrets list -namespace=test
```

Confirm that `kv_secret/` appears in the list.

## Step 2: Import the Namespace into Terraform

Add the existing `test` namespace to Terraform state. The import block tells Terraform to adopt it rather than create it. Check that the plan proposes only an import before applying.

```bash
cat > main.tf <<'EOF'
terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "4.7.0"
    }
  }
}

provider "vault" {}

resource "vault_namespace" "parent" {
  path = "test"
}

import {
  to = vault_namespace.parent
  id = "test"
}
EOF

terraform init
terraform plan
```

The supplied run showed `Plan: 1 to import, 0 to add, 0 to change, 0 to destroy`. If your plan proposes creating or destroying anything, stop and check the target and namespace. Otherwise, apply the import:

```bash
terraform apply
```

Confirm that the namespace import completed successfully before continuing.

## Step 3: Plan the Mount Import

Keep the managed namespace in `main.tf`, replace its import block with a `vault_mount` resource and import block, and set `TERRAFORM_VAULT_NAMESPACE_IMPORT=test` for this plan. Terraform should import `kv_secret` without changing the already-managed `test` namespace. The unexpected namespace creation in the plan is the issue being reproduced.

```bash
cat > main.tf <<'EOF'
terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "4.7.0"
    }
  }
}

provider "vault" {}

resource "vault_namespace" "parent" {
  path = "test"
}

resource "vault_mount" "kv" {
  namespace = vault_namespace.parent.path
  path      = "kv_secret"
  type      = "kv"
  options = {
    version = "2"
  }
}

import {
  to = vault_mount.kv
  id = "kv_secret"
}
EOF

TERRAFORM_VAULT_NAMESPACE_IMPORT=test terraform plan
```

The supplied run with provider `4.7.0` showed this plan (namespace name adapted to `test`):

```text
# vault_mount.kv will be imported
# vault_namespace.parent will be created
Plan: 1 to import, 1 to add, 0 to change, 0 to destroy.
```

Do not apply this plan: it would attempt to create `test/test`.

## Step 4: Clean Up the Lab

Only clean up if you created `test` in step 1 on this disposable Vault lab. Disabling `kv_secret` deletes anything stored in that mount; destroying `test` removes all its contents. Before cleanup, remove the mount's `import` block from `main.tf`. Check the target and the mount, then disable it:

```bash
cd "$REPRO_DIR"
unset TERRAFORM_VAULT_NAMESPACE_IMPORT
vault status
vault secrets list -namespace=test
```

Confirm the target is your disposable lab and the listed `kv_secret/` mount is the one you created. Then disable it and preview the destroy plan:

```bash
vault secrets disable -namespace=test kv_secret
terraform plan -destroy
```

The plan should destroy only the namespace from step 1. Stop if it contains anything else. Otherwise, destroy that namespace and verify that `test/` is gone:

```bash
terraform destroy
vault namespace list
```

The temporary working directory contains Terraform state, which may contain sensitive information. Remove it only after confirming cleanup and following your normal secure-disposal practice.

## References

- [VAULT-34835](https://hashicorp.atlassian.net/browse/VAULT-34835) — customer report, triage decision, and linked feature request.
- [VAULT-51006](https://hashicorp.atlassian.net/browse/VAULT-51006) — EPIC for namespaced resource import improvements in the Vault provider.
- [FRB-6948](https://hashicorp.atlassian.net/browse/FRB-6948) - Feature request related to importing namespaced resources in the Vault provider.
- [Vault provider namespace import documentation](https://registry.terraform.io/providers/hashicorp/vault/latest/docs#importing-namespaced-resources) — import namespace is relative to the provider namespace and intended for import commands.
