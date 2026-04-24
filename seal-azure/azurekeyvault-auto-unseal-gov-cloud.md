# Azure Auto Unseal: US Government Cloud Bug in `go-kms-wrapping` v2.0.14 and Earlier [Draft]

I worked with a customer who was deploying Vault on AKS in the Azure US Government Cloud and configuring Azure Key Vault Auto Unseal. Vault was failing to start on every attempt. We ended up hitting both of the issues documented here in sequence: first, a startup failure caused by an invalid `environment` config value — the customer had used a string from a different HashiCorp library that doesn't apply to the seal config — and then, after correcting that, a second failure caused by a bug in `go-kms-wrapping` where the Azure authentication endpoint is hard-coded to the public cloud and never updated for Gov Cloud tenants. 

This document covers both issues, their root causes, and workarounds. This has been filed as [VAULT-44389](https://hashicorp.atlassian.net/browse/VAULT-44389).

- Component: Azure Key Vault Auto Unseal (`seal "azurekeyvault"`) - (also impacts Azure Managed Keys `/sys/managed-keys/azurekeyvault`)
- Severity: High — Vault will not start  
- Affected versions: All Vault versions using `go-kms-wrapping/wrappers/azurekeyvault/v2` ≤ v2.0.14 (no fixed version available as of this writing; use the workarounds below)

---

## Symptoms

Vault fails to start with one or both of the following errors:

Issue 1 — Invalid `environment` value

```text
error parsing Seal configuration: autorest/azure: There is no cloud environment
matching the name "..."
```

Issue 2 — Hard-coded Azure authentication endpoint

```text
error parsing Seal configuration: error fetching Azure Key Vault wrapper key information:
ClientSecretCredential: unable to resolve an endpoint
```

---

## Root Cause

There are two independent issues, both triggered when configuring Azure Auto Unseal for US Government Cloud.

### Issue 1 — Invalid `environment` value

If the environment value is incorrect, Vault fails to unseal vault with the error `autorest/azure: There is no cloud environment matching the name "..."`.

The `environment` parameter is passed to `azure.EnvironmentFromName()` from the `go-autorest/autorest/azure` library. This function upper-cases the input and does a map lookup:

| Config value | Lookup key | Valid? |
|---|---|---|
| `AzureUsGovernment` | `AZUREUSGOVERNMENT` | Yes — use this |
| `AzureUSGovernmentCloud` | `AZUREUSGOVERNMENTCLOUD` | Works today, but marked `//TODO: deprecate` in source |
| `AzureGovernment` | `AZUREGOVERNMENT` | No — referenced in HashiCorp's older `armcore` fork of the Azure SDK |
| `USGovernment` | `USGOVERNMENT` | No — used by HashiCorp's `go-azure-sdk` library for Terraform |
| `AzurePublicCloud` | `AZUREPUBLICCLOUD` | Yes (public cloud) |
| `AzureCloud` | `AZURECLOUD` | Yes (public cloud) |

#### Summary of environment name confusion

- The correct value for US Government Cloud is `AzureUsGovernment`. 
- `AzureUSGovernmentCloud` still works today but its lookup key is [marked for deprecation](https://github.com/Azure/go-autorest/blob/2fa44cb18b8338d7fa4f749bb798d6cbb3d9ba0c/autorest/azure/environments.go#L34) in `go-autorest` and should be avoided in new configurations. 

- `AzureGovernment` is used in HashiCorp's older `armcore` fork of the Azure SDK ([`sdk/armcore/connection.go`](https://github.com/hashicorp/azure-sdk-for-go/blob/5f5b9952f37b2085f3ba6844f129f1d66fd6d7f9/sdk/armcore/connection.go#L14)) defines a Go constant (as seen below). This is the ARM management endpoint URL, not an environment name string. The Vault `environment` config key takes an environment name passed to `go-autorest`'s `EnvironmentFromName()`, which does a map lookup against a fixed set of keys. `AZUREGOVERNMENT` is not one of those keys and returns the "no cloud environment matching the name" error.

```go
// AzureGovernment is the Azure Resource Manager US government cloud endpoint.
AzureGovernment = "https://management.usgovcloudapi.net/"
```

- `USGovernment`: HashiCorp's separate `go-azure-sdk` library (used by the Terraform Azure provider and Vault's Azure auth/secrets engines) defines its own environment system in [`sdk/environments/azure_gov.go`](https://github.com/hashicorp/go-azure-sdk/blob/main/sdk/environments/azure_gov.go):

```go
// hashicorp/go-azure-sdk — NOT used by Vault auto unseal
const AzureUSGovernmentCloud = "USGovernment"
// LoginEndpoint: "https://login.microsoftonline.us"
```

  - The constant is named `AzureUSGovernmentCloud` but its string value is `"USGovernment"`. Customers familiar with Terraform or Vault's Azure auth method may try this value in the seal config. `go-autorest`'s lookup map has no `USGOVERNMENT` key, so this also fails.

**Key takeaway:** Three different HashiCorp/Azure libraries each use different string identifiers for the same US Government Cloud. Only `go-autorest`'s values are relevant for Vault's seal `environment` parameter.

### Issue 2 — Authentication endpoint hard-coded to Azure Public Cloud

If you use the correct environment value, Vault still fails with `ClientSecretCredential: unable to resolve an endpoint` due to a bug in the go-kms-wrapping library. This is a bug in `go-kms-wrapping` ≤ v2.0.14.

When `tenant_id`, `client_id`, and `client_secret` are all provided in the seal config, the wrapper creates an Azure credential using `azidentity.NewClientSecretCredential` with `nil` options:

```go
// go-kms-wrapping/wrappers/azurekeyvault/azurekeyvault.go (https://github.com/hashicorp/go-kms-wrapping/blob/f5cd57511b44f3f0d5a22e9b787c68992aa03516/wrappers/azurekeyvault/azurekeyvault.go#L301)
cred, err = azidentity.NewClientSecretCredential(v.tenantID, v.clientID, v.clientSecret, nil)
//                                                                                        ^^^
//  nil → zero-value ClientSecretCredentialOptions
//      → zero-value azcore.ClientOptions.Cloud (cloud.Configuration{})
//      → setAuthorityHost() sees empty ActiveDirectoryAuthorityHost
//      → no AZURE_AUTHORITY_HOST env var set
//      → falls back to cloud.AzurePublic = "https://login.microsoftonline.com/"
```

The `environment` config value controls only the Key Vault DNS suffix (e.g. `vault.usgovcloudapi.net`). It is never propagated to the `azidentity` credential options. As a result, the client always tries to obtain a token from `login.microsoftonline.com` (Azure Public Cloud) instead of `login.microsoftonline.us`, which fails for US Gov tenants.

Call chain detail: Inside `azidentity`, `NewClientSecretCredential` delegates to `newConfidentialClient`, which calls `setAuthorityHost(opts.Cloud)`. That function implements a three-level priority chain ([`azidentity/azidentity.go`](https://github.com/Azure/azure-sdk-for-go/blob/main/sdk/azidentity/azidentity.go)):

```text
1. opts.Cloud.ActiveDirectoryAuthorityHost  — set explicitly by caller
2. AZURE_AUTHORITY_HOST env var             — checked even when opts is nil/zero
3. cloud.AzurePublic (default)             → "https://login.microsoftonline.com/"
```

Because `go-kms-wrapping` passes `nil`, step 1 is always empty. If `AZURE_AUTHORITY_HOST` is not set, step 3 wins and the credential is locked to the public cloud login endpoint. Critically, `AZURE_AUTHORITY_HOST` (step 2) is checked by `setAuthorityHost` regardless of whether the credential was constructed with `nil` or explicit options — this matters for how Option B works (see below).

The correct fix would be for the library to map `v.environment.ActiveDirectoryEndpoint` to an `azcore` cloud configuration and pass it to the credential.

The `azcore/cloud` package already ships the right configuration ([`sdk/azcore/cloud/cloud.go`](https://github.com/Azure/azure-sdk-for-go/blob/main/sdk/azcore/cloud/cloud.go)):

```go
// Already available in azcore — AzureGovernment sets the correct auth host
AzureGovernment = Configuration{
    ActiveDirectoryAuthorityHost: "https://login.microsoftonline.us/",
    ...
}
```

Importantly, `go-kms-wrapping`'s `go.mod` already depends on `azcore v1.17.0`, so `cloud.AzureGovernment` is available right now. The library just isn't using it. The fix:

```go
// What the library should do (not current behavior)
import "github.com/Azure/azure-sdk-for-go/sdk/azcore/cloud"

opts := &azidentity.ClientSecretCredentialOptions{
    ClientOptions: azcore.ClientOptions{
        Cloud: cloud.AzureGovernment, // → login.microsoftonline.us
    },
}
cred, err = azidentity.NewClientSecretCredential(v.tenantID, v.clientID, v.clientSecret, opts)
```

---

## Confirmed Workaround

### Use environment variables with `AZURE_AUTHORITY_HOST`

Leave credentials out of the HCL config and instead set environment variables. The `azidentity.EnvironmentCredential` code path is cloud-aware and respects `AZURE_AUTHORITY_HOST`.

```bash
export AZURE_TENANT_ID="<your-tenant-id>"
export AZURE_CLIENT_ID="<your-client-id>"
export AZURE_CLIENT_SECRET="<your-client-secret>"
export AZURE_AUTHORITY_HOST="https://login.microsoftonline.us/"
```

```hcl
seal "azurekeyvault" {
  vault_name  = "your-keyvault-name"
  key_name    = "your-key-name"
  environment = "AzureUsGovernment"
}
```

How this works: Because `AZURE_AUTHORITY_HOST` is checked in `setAuthorityHost` at priority level 2 — before the public cloud default but regardless of how the credential is constructed — it is respected even when `NewClientSecretCredential` is called with `nil` options. This means Option B has two valid forms:

  - Credentials in env vars only (as shown above): The wrapper falls through to `azidentity.NewDefaultAzureCredential`, which chains through `EnvironmentCredential`. Both code paths call `setAuthorityHost` and will pick up `AZURE_AUTHORITY_HOST`.
  - Credentials in HCL + `AZURE_AUTHORITY_HOST` set: The wrapper calls `NewClientSecretCredential(nil)`, `setAuthorityHost` fires, finds `AZURE_AUTHORITY_HOST`, and uses `login.microsoftonline.us`. This also works — but keeping credentials in HCL is less portable and not recommended.

In both forms, `environment = "AzureUsGovernment"` in HCL is still required for the correct Key Vault DNS suffix.

### Storing credentials securely on AKS (Vault Helm chart)

If you are deploying Vault on AKS using the [Vault Helm chart](https://developer.hashicorp.com/vault/docs/deploy/kubernetes/helm), avoid setting these environment variables directly in your `values.yaml` or Kubernetes manifests, as that would expose the credentials in plain text. Instead, store them in a Kubernetes Secret and reference it via [`server.extraSecretEnvironmentVars`](https://developer.hashicorp.com/vault/docs/deploy/kubernetes/helm/configuration#extrasecretenvironmentvars).

Create the Kubernetes Secret:

```bash
kubectl create secret generic vault-azure-unseal-creds \
  --namespace vault \
  --from-literal=AZURE_TENANT_ID="<your-tenant-id>" \
  --from-literal=AZURE_CLIENT_ID="<your-client-id>" \
  --from-literal=AZURE_CLIENT_SECRET="<your-client-secret>" \
  --from-literal=AZURE_AUTHORITY_HOST="https://login.microsoftonline.us/"
```

Then reference the secret in your Helm values:

```yaml
server:
  extraSecretEnvironmentVars:
    - envName: AZURE_TENANT_ID
      secretName: vault-azure-unseal-creds
      secretKey: AZURE_TENANT_ID
    - envName: AZURE_CLIENT_ID
      secretName: vault-azure-unseal-creds
      secretKey: AZURE_CLIENT_ID
    - envName: AZURE_CLIENT_SECRET
      secretName: vault-azure-unseal-creds
      secretKey: AZURE_CLIENT_SECRET
    - envName: AZURE_AUTHORITY_HOST
      secretName: vault-azure-unseal-creds
      secretKey: AZURE_AUTHORITY_HOST
```

The seal stanza in your Vault HCL config (passed via `server.ha.config` or `server.standalone.config`) still requires only the non-sensitive values:

```hcl
seal "azurekeyvault" {
  vault_name  = "your-keyvault-name"
  key_name    = "your-key-name"
  environment = "AzureUsGovernment"
}
```

`extraSecretEnvironmentVars` injects the values from the Kubernetes Secret directly into the Vault pod's environment at runtime. The credentials are never written to the chart values, ConfigMaps, or manifests.

---

## Upstream fix

The root fix belongs in the `go-kms-wrapping` library. The azurekeyvault wrapper should map `environment.ActiveDirectoryEndpoint` to an `azcore` cloud config and pass it through to `NewClientSecretCredential` / `NewDefaultAzureCredential`.

Note: The same bug also affects Azure Managed Keys (`/sys/managed-keys/azurekeyvault`). The enterprise wrapper (`go-kms-wrapping-enterprise/wrappers/azurekeyvault`) delegates its `SetConfig` directly to the OSS `SetConfig` and does not override credential creation, so `getKeyVaultClient` in the OSS code is the single code path for both features.

---

## Relevant code locations

| File | Description |
|---|---|
| [`internalshared/configutil/kms.go`](https://github.com/hashicorp/vault-enterprise/blob/main/internalshared/configutil/kms.go) | `GetAzureKeyVaultKMSFunc` — builds the wrapper from HCL config |
| [`internalshared/configutil/env_var_util.go`](https://github.com/hashicorp/vault-enterprise/blob/main/internalshared/configutil/env_var_util.go) | Maps `AZURE_ENVIRONMENT` env var to the `environment` config key |
| [`go-kms-wrapping/.../azurekeyvault.go`](https://github.com/hashicorp/go-kms-wrapping/blob/main/wrappers/azurekeyvault/azurekeyvault.go) | Wrapper `SetConfig` and `getKeyVaultClient` — source of bug |
| [`go-autorest/.../environments.go`](https://github.com/Azure/go-autorest/blob/master/autorest/azure/environments.go) | `EnvironmentFromName` lookup map — source of valid environment name values |
| [`go-azure-sdk/.../azure_gov.go`](https://github.com/hashicorp/go-azure-sdk/blob/main/sdk/environments/azure_gov.go) | HashiCorp's separate Azure SDK (Terraform/Vault auth); uses `"USGovernment"` — not used by auto unseal |
| [`hashicorp/azure-sdk-for-go armcore/connection.go`](https://github.com/hashicorp/azure-sdk-for-go/blob/5f5b9952f37b2085f3ba6844f129f1d66fd6d7f9/sdk/armcore/connection.go#L14) | Old HashiCorp ARM fork; defines `AzureGovernment` as an endpoint URL constant — not an environment name |

---

## Valid `environment` values

| Value | Cloud |
|---|---|
| `AzureCloud` / `AzurePublicCloud` | Azure Public Cloud (default) |
| `AzureUsGovernment` | Azure US Government (preferred) |
| `AzureUSGovernmentCloud` | Azure US Government (soon to be deprecated, avoid in new configs) |
| `AzureChinaCloud` | Azure China |
| `AzureGermanCloud` | Azure Germany |
