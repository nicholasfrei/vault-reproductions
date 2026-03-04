# VSO KB: Kubernetes Secret Sync Fails with Special Characters in KV Keys

## Overview

This KB reproduces and explains a Vault Secrets Operator (VSO) sync failure when Vault KV keys contain characters that are invalid for Kubernetes Secret `data` keys (for example `@`).

Example failing KV entry:

- `test@test.com: test@test.com`

When VSO attempts to sync this key into a Kubernetes Secret, Kubernetes rejects it.

## Problem Statement

Kubernetes Secret `data` keys must match this regex:

- `[-._a-zA-Z0-9]+`

The character `@` is not allowed, so VSO sync fails if a KV key includes `@`.

## Preconditions

- Running Kubernetes cluster
- `kubectl`, `vault`, and `jq` installed
- VSO installed and healthy
- Vault KV v2 mount available
- Vault Kubernetes auth configured for VSO

## Reproduction

### 1) Seed Vault KV with an invalid Kubernetes key name

```bash
vault secrets enable -path=automation kv-v2 || true

vault kv put automation/QAAutomationITQEuser@test.com \
  "test@test.com"="test@test.com"
```

### 2) Create VSO resources

```bash
cat <<'EOF' >/tmp/vso-special-char-repro.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: ns002
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vso-auth
  namespace: ns002
---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultConnection
metadata:
  name: demo-vault-connection
  namespace: ns002
spec:
  address: https://vault.vault.svc:8200
  skipTLSVerify: true
---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: vso-kubernetes-auth
  namespace: ns002
spec:
  vaultConnectionRef: demo-vault-connection
  method: kubernetes
  mount: kubernetes
  kubernetes:
    role: vso-special-char-role
    serviceAccount: vso-auth
---
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: secret-automation
  namespace: ns002
spec:
  vaultAuthRef: vso-kubernetes-auth
  mount: automation
  path: QAAutomationITQEuser@test.com
  type: kv-v2
  refreshAfter: 30s
  destination:
    name: automation
    create: true
EOF

kubectl apply -f /tmp/vso-special-char-repro.yaml
```

### 3) Ensure Vault policy and role allow reads for VSO

```bash
cat <<'EOF' >/tmp/vso-special-char-policy.hcl
path "automation/data/QAAutomationITQEuser@test.com" {
  capabilities = ["read"]
}
EOF

vault policy write vso-special-char /tmp/vso-special-char-policy.hcl

vault write auth/kubernetes/role/vso-special-char-role \
  bound_service_account_names=vso-auth \
  bound_service_account_namespaces=ns002 \
  token_policies=vso-special-char \
  ttl=1h
```

### 4) Verify failure

```bash
kubectl describe vaultstaticsecret secret-automation -n ns002
kubectl logs -n vault-system deploy/vault-secrets-operator-controller-manager
```

Observed error:

```text
Failed to update k8s secret: Secret "automation" is invalid:
data[test@test.com]: Invalid value: "test@test.com":
a valid config key must consist of alphanumeric characters, '-', '_' or '.'
```

## Expected vs Observed

- **Expected:** Sync succeeds and key is automatically transformed (for example `test_test.com`).
- **Observed:** Sync fails because Kubernetes validates Secret keys before persistence and rejects `@`.

## Transformation Template Findings

Reference material used for this testing:

- [VSO Secret Transformation Documentation](https://developer.hashicorp.com/vault/docs/deploy/kubernetes/vso/secret-transformation)

### What was tested

A generic transformation approach such as:

```yaml
transformation:
  templates:
    credentials:
      text: |
        {{- range $k, $_ := .Secrets -}}
        {{ replace "@" "_" $k }}
        {{- end -}}
```

did not provide scalable, automatic key renaming for arbitrary source keys.

### Partial workaround (manual and not scalable)

VSO can be configured with:

- `transformation.excludes` to omit original invalid keys, and
- explicit template key names under `transformation.templates`.

This can work for individually known keys, but requires a per-key mapping and ongoing maintenance as keys change.

## Conclusion

For VSO sync into Kubernetes Secrets, keys containing `@` are not supported as-is. In tested configurations, there is no scalable, generic transformation that automatically rewrites all invalid source key names during sync.

## Recommended Paths Forward

1. Normalize key names before writing to Vault KV for VSO-managed paths.
2. If dynamic key normalization is required, render to files via Vault Agent templating instead of Kubernetes Secret `data` keys.
3. Re-evaluate operator choice if automatic broad key-name normalization is a hard requirement.

## Cleanup

```bash
kubectl delete -f /tmp/vso-special-char-repro.yaml

vault policy delete vso-special-char || true
vault delete auth/kubernetes/role/vso-special-char-role || true
vault kv metadata delete automation/QAAutomationITQEuser@test.com || true
```
