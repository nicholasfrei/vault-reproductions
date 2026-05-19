# Azure Secrets Sync: `panic: not struct` Bug in `1.21.4+ent` and `1.21.5+ent` Repro

## Overview

In Vault Enterprise `1.21.4+ent` and `1.21.5+ent`, writing a `sys/sync/destinations/azure-kv` destination that includes `disable_strict_networking=true` triggers a fatal panic: `panic: not struct`. The panic originates in `logical_system_sync_stores_ent.go` where `github.com/fatih/structs.New()` is called with a nil or non-struct value. 

This repro confirms the behavior on `1.21.4+ent` or `1.21.5+ent` and validates that `2.0.0+ent` resolves it.

## Objective

- Create the Azure prerequisites needed for the sync destination
- Activate Vault Secrets Sync on an existing `2.0.0+ent` Kubernetes cluster
- Create an Azure KV destination and sync association
- Verify the synced secret appears in Azure Key Vault

## Affected Versions

| Version | Behavior |
|---------|----------|
| `1.21.4+ent` and `1.21.5+ent` | Panics with `panic: not struct` |
| `2.0.0+ent` | Fixed - works as expected |

## Prerequisites

- Vault Enterprise `2.0.0+ent`
- Vault Enterprise license
- Azure account with these permissions [docs](https://docs.prod.secops.hashicorp.services/doormat/azure/secrets_engine/):
  - `Application.ReadWrite.OwnedBy` at the tenant level
  - `GroupMember.ReadWrite.All` at the tenant level
  - `User Access Admin` at the subscription level 
- Access to the [Azure Portal](https://portal.azure.com)

## Azure Setup

You will collect four values during this process to use later in the Vault destination configuration:

| Value | Where to find it |
|-------|-----------------|
| `client_id` | App Registration > Overview > Application (client) ID |
| `client_secret` | App Registration > Certificates & secrets > client secret value |
| `tenant_id` | App Registration > Overview > Directory (tenant) ID |
| `key_vault_uri` | Key Vault > Overview > Vault URI |

### 1. Create a Resource Group (if needed)

1. Go to [portal.azure.com](https://portal.azure.com) and search for "Resource groups".
2. Click "Create".
3. Fill in the subscription, resource group name (e.g., `vault-secrets-sync-rg`), and region.
4. Click "Review + create", then "Create".

### 2. Create an App Registration

1. Search for "Microsoft Entra ID" (formerly Azure Active Directory) in the portal.
2. In the left menu select "App registrations", then "New registration".
3. Set the name to `vault-secrets-sync-demo`. Leave all other settings at their defaults.
4. Click "Register".
5. On the Overview page, note the "Application (client) ID" and "Directory (tenant) ID". You will need both when configuring the Vault destination.

### 3. Generate a Client Secret

1. In the App Registration, open "Certificates & secrets" in the left menu.
2. Under "Client secrets", click "New client secret".
3. Add a description (e.g., `vault-sync`) and set an expiry appropriate for your environment.
4. Click "Add".
5. Copy the "Value" field immediately. It is only shown once and cannot be retrieved later.

### 4. Create an Azure Key Vault

Vault Secrets Sync requires the Key Vault to use Azure role-based access control (RBAC). Access policy-based Key Vaults are not supported.

1. Search for "Key vaults" in the portal, then click "Create".
2. Select your subscription and the resource group from step 1.
3. Set a unique vault name (e.g., `vault-sync-demo-kv`) and choose a region.
4. On the "Access configuration" tab, select "Azure role-based access control" under "Permission model".
5. Click "Review + create", then "Create".
6. Once deployed, open the Key Vault. On the Overview page, note the "Vault URI" (e.g., `https://vault-sync-demo-kv.vault.azure.net/`).

### 5. Assign the Key Vault Secrets Officer Role to the App Registration

1. In the Key Vault, open "Access control (IAM)" in the left menu.
2. Click "Add" > "Add role assignment".
3. Search for and select the "Key Vault Secrets Officer" role, then click "Next".
4. Under "Members", click "Select members". Search for `vault-secrets-sync-demo` (the App Registration name) and select it.
5. Click "Review + assign" twice to confirm.

Role propagation in Azure typically takes 1–2 minutes. Continue once the assignment appears in the "Role assignments" tab.

## Steps

### 1. Verify Vault Cluster Health

```bash
vault status
```

Expected output:

```text
Key                      Value
---                      -----
Seal Type                <anything>
Initialized              true
Sealed                   false
...
Version                  2.0.0+ent
...
HA Enabled               true
HA Cluster               https://<vault_addr>:8201
HA Mode                  active
```

### 2. Activate Secrets Sync

Secrets Sync must be explicitly activated before destinations can be configured. This is a one-time operation per cluster.

```bash
vault write -f sys/activation-flags/secrets-sync/activate
```

Expected output:

```text
Key            Value
---            -----
activated      [secrets-sync]
unactivated    [oauth-resource-server secrets-import]
```

### 3. Enable KV v2 and Write a Test Secret

```bash
vault secrets enable -path=kv kv-v2

vault kv put kv/test/azure-sync-test \
  username=svc-account \
  password=changeme123
```

Expected output:

```text
Success! Enabled the kv-v2 secrets engine at: kv/

======= Secret Path =======
kv/data/test/azure-sync-test

======= Metadata =======
Key              Value
---              -----
created_time     <timestamp>
version          1
```

### 4. Create the Azure KV Sync Destination

Replace the placeholder values with the outputs from the Azure Setup section above.

On `1.21.5+ent` this command triggers `panic: not struct` and crashes the Vault process.

```bash
vault write sys/sync/destinations/azure-kv/my-azure-kv \
  client_id="<application-client-id>" \
  client_secret="<client-secret-value>" \
  tenant_id="<directory-tenant-id>" \
  key_vault_uri="<key-vault-uri>" \
  granularity="secret-key" \
  secret_name_template="{{ .SecretKey }}" \
  disable_strict_networking=true
```

Expected output on `2.0.0+ent`:

```text
Key                   Value
---                   -----
connection_details    map[client_id:<client-id> key_vault_uri:https://vault-sync-demo-kv.vault.azure.net/ tenant_id:<tenant-id>]
name                  my-azure-kv
options               map[disable_strict_networking:true granularity:secret-key secret_name_template:{{ .SecretKey }}]
type                  azure-kv
```

Expected panic on `1.21.4+ent` and `1.21.5+ent` (reproduced by sending the request through a standby node):

```text
panic: not struct

goroutine 52281 [running]:
github.com/fatih/structs.strctVal({0xb7671a0?, 0x0?})
	/go-mod-cache/github.com/fatih/structs@v1.1.0/structs.go:437 +0xa8
github.com/fatih/structs.New(...)
	/go-mod-cache/github.com/fatih/structs@v1.1.0/structs.go:30
github.com/hashicorp/vault/vault.(*SecretsSyncBackend).storeCreateUpdateHandler(0xc0063fd200, {0x10481b68, 0xc07dc21d10}, 0xc02a165208, 0xc072c18340)
	/build/vault/logical_system_sync_stores_ent.go:622 +0xb7d
github.com/hashicorp/vault/sdk/framework.(*Backend).HandleRequest(0xc0063fd680, {0x10481b68, 0xc07dc21d10}, 0xc02a165208)
	/build/sdk/framework/backend.go:331 +0xb88
github.com/hashicorp/vault/vault.(*Router).routeCommon(0xc0032eefc0, {0x10481b68, 0xc07dc21d10}, 0xc02a165208, 0x0)
	/build/vault/router.go:808 +0x185c
github.com/hashicorp/vault/vault.(*Router).Route(...)
	/build/vault/router.go:569
github.com/hashicorp/vault/vault.(*replicationServiceHandler).ForwardingRequestCommon(0xc00b732700, {0x10481b30, 0xc073f26f90}, 0xc0480d8380, 0x0)
	/build/vault/replication_rpc_ent.go:879 +0x625
github.com/hashicorp/vault/vault.(*standbyReplicationServiceHandler).ForwardingRequest(0xc00ba1e660, {0x10481b30, 0xc073f26f30}, 0xc0480d8380)
	/build/vault/replication_standby_rpc_ent.go:490 +0x85
```

### 5. Associate the Test Secret with the Destination

```bash
vault write sys/sync/destinations/azure-kv/my-azure-kv/associations/set \
  mount=kv \
  secret_name=test/azure-sync-test
```

Expected output:

```text
Key                    Value
---                    -----
associated_secrets     map[kv/test/azure-sync-test:map[accessor:<accessor> secret_name:test/azure-sync-test sync_status:SYNCED]]
store_name             my-azure-kv
store_type             azure-kv
```

## Validation

### Confirm Sync Status

```bash
vault read sys/sync/destinations/azure-kv/my-azure-kv/associations
```

The `sync_status` field should show `SYNCED` for each associated secret.

### Confirm the Secret Appears in Azure Key Vault

1. Open the Key Vault (`vault-sync-demo-kv`) in the Azure Portal.
2. In the left menu select "Objects" > "Secrets".
3. The synced secret should appear. Its name follows the `secret_name_template` configured on the destination. The default template produces names in the format `<mount-accessor>_<secret-path>` with `/` replaced by `_`.
4. Click the secret name, then the current version, and click "Show Secret Value" to verify the contents.

## Cleanup

### Remove the Sync Association

```bash
vault write sys/sync/destinations/azure-kv/my-azure-kv/associations/remove \
  mount=kv \
  secret_name=test/azure-sync-test
```

Vault Secrets Sync does not automatically delete secrets from the external destination when an association is removed. Delete the secret from Azure Key Vault manually if it is no longer needed.

### Delete the Sync Destination

```bash
vault delete sys/sync/destinations/azure-kv/my-azure-kv
```

### Remove the KV Mount and Test Data

```bash
vault kv metadata delete kv/test/azure-sync-test
vault secrets disable kv
```

### Azure Cleanup

1. Open "Key vaults" in the portal, select `vault-sync-demo-kv`, and click "Delete". Confirm the deletion. To permanently remove it and skip the soft-delete retention period, open "Manage deleted vaults" and purge it.
2. Open "Microsoft Entra ID" > "App registrations", find `vault-secrets-sync-demo`, and click "Delete".
3. If the resource group was created solely for this repro, open "Resource groups", select `vault-secrets-sync-rg`, and click "Delete resource group".

## References

- [Vault Secrets Sync — Azure Key Vault](https://developer.hashicorp.com/vault/docs/sync/azurekv)
- [Vault Secrets Sync — Activation](https://developer.hashicorp.com/vault/docs/sync#activating-secrets-sync)
