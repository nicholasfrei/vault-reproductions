# VSO + Kubernetes Auth Repro (Static + Dynamic Secrets)

## Overview

This runbook demonstrates how to use the Vault Secrets Operator (VSO) with Vault Kubernetes authentication to sync:

- A static secret from KV v2 (`VaultStaticSecret`)
- A dynamic secret from the database secrets engine (`VaultDynamicSecret`)

The two manifests created for this scenario are:

- `vso-static-secret.yaml`
- `vso-dynamic-secret.yaml`

## What this proves

1. VSO can authenticate to Vault using `auth/kubernetes`.
2. VSO can sync static KV data into a Kubernetes Secret.
3. VSO can sync dynamic leased credentials into a Kubernetes Secret.
4. Secret sync fails and recovers predictably when Kubernetes auth role bindings are broken and restored.

## Prerequisites

- Running Kubernetes cluster
- `kubectl`, `helm`, and `vault` CLI access
- Vault reachable from cluster workloads
- VSO installed in the cluster
- Vault Kubernetes auth method enabled and configured
- A working database secrets engine setup for dynamic creds
  - This runbook uses PostgreSQL examples for dynamic secrets.
  - If needed, reuse your setup from `secrets-postgresql-db/postgresql-database-secrets-engine-repro.md`.

## 1) Install VSO (if not already installed)

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

kubectl create namespace vault-system || true

helm upgrade --install vault-secrets-operator hashicorp/vault-secrets-operator \
  -n vault-system \
  --wait
```

Verify CRDs exist:

```bash
kubectl get crd | rg "secrets.hashicorp.com"
```

## 2) Create namespace + service accounts from manifests

Apply both manifests now (safe to reapply):

```bash
kubectl apply -f kubernetes/vso-k8s-auth-static-dynamic/vso-static-secret.yaml
kubectl apply -f kubernetes/vso-k8s-auth-static-dynamic/vso-dynamic-secret.yaml
```

## 3) Configure Vault policies for VSO

Create static and dynamic policies:

```bash
cat <<'EOF' >/tmp/vso-static-policy.hcl
path "kvv2/data/demo/app" {
  capabilities = ["read"]
}
EOF

cat <<'EOF' >/tmp/vso-dynamic-policy.hcl
path "database/creds/app-role" {
  capabilities = ["read"]
}
EOF
```

Write policies:

```bash
vault policy write vso-static /tmp/vso-static-policy.hcl
vault policy write vso-dynamic /tmp/vso-dynamic-policy.hcl
```

## 4) Configure Kubernetes auth roles for VSO

Bind each Vault role to its ServiceAccount in `demo-app`:

```bash
vault write auth/kubernetes/role/vso-static-role \
  bound_service_account_names=vso-static-auth \
  bound_service_account_namespaces=demo-app \
  token_policies=vso-static \
  ttl=1h

vault write auth/kubernetes/role/vso-dynamic-role \
  bound_service_account_names=vso-dynamic-auth \
  bound_service_account_namespaces=demo-app \
  token_policies=vso-dynamic \
  ttl=1h
```

## 5) Create static KV test data

```bash
vault secrets enable -path=kvv2 kv-v2 || true

vault kv put kvv2/demo/app \
  username="app-user" \
  password="app-pass-v1" \
  feature_flag="true"
```

## 6) Configure dynamic database role (PostgreSQL example)

This assumes:

- The `database/` secrets engine is enabled.
- A database connection already exists at `database/config/postgresql`.
- A DB user with enough privileges exists for Vault to create and revoke users.

Create/update the dynamic role used by `VaultDynamicSecret` (`database/creds/app-role`):

```bash
vault write database/roles/app-role \
  db_name=postgresql \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
  revocation_statements="REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM \"{{name}}\"; DROP ROLE IF EXISTS \"{{name}}\";" \
  default_ttl="1m" \
  max_ttl="5m"
```

## 7) Re-apply VSO resources

If you applied earlier, reapply after Vault-side configuration:

```bash
kubectl apply -f kubernetes/vso-k8s-auth-static-dynamic/vso-static-secret.yaml
kubectl apply -f kubernetes/vso-k8s-auth-static-dynamic/vso-dynamic-secret.yaml
```

## 8) Verify static secret sync

Check the Kubernetes secret populated by `VaultStaticSecret`:

```bash
kubectl get secret app-static-secret -n demo-app -o jsonpath='{.data}' | jq
```

Decode one field:

```bash
kubectl get secret app-static-secret -n demo-app -o jsonpath='{.data.username}' | base64 --decode; echo
```

## 9) Verify dynamic secret sync

Check the Kubernetes secret populated by `VaultDynamicSecret`:

```bash
kubectl get secret app-dynamic-db-secret -n demo-app -o jsonpath='{.data}' | jq
```

Decode fields:

```bash
kubectl get secret app-dynamic-db-secret -n demo-app -o jsonpath='{.data.username}' | base64 --decode; echo
kubectl get secret app-dynamic-db-secret -n demo-app -o jsonpath='{.data.password}' | base64 --decode; echo
```

Wait ~60-90 seconds and read again. With short TTL settings, username/password should rotate.

## 10) Validate static update propagation

Update KV value:

```bash
vault kv put kvv2/demo/app \
  username="app-user" \
  password="app-pass-v2" \
  feature_flag="false"
```

Wait at least `refreshAfter` (30s), then verify:

```bash
kubectl get secret app-static-secret -n demo-app -o jsonpath='{.data.password}' | base64 --decode; echo
kubectl get secret app-static-secret -n demo-app -o jsonpath='{.data.feature_flag}' | base64 --decode; echo
```

## 11) Failure injection: break and restore Kubernetes auth role binding

Break static role by changing bound namespace:

```bash
vault write auth/kubernetes/role/vso-static-role \
  bound_service_account_names=vso-static-auth \
  bound_service_account_namespaces=wrong-namespace \
  token_policies=vso-static \
  ttl=1h
```

Watch VSO status/events:

```bash
kubectl get vaultstaticsecret -n demo-app
kubectl describe vaultstaticsecret app-static-config -n demo-app
```

Restore:

```bash
vault write auth/kubernetes/role/vso-static-role \
  bound_service_account_names=vso-static-auth \
  bound_service_account_namespaces=demo-app \
  token_policies=vso-static \
  ttl=1h
```

## Troubleshooting quick checks

- Confirm VSO controllers are healthy:
  ```bash
  kubectl get pods -n vault-system
  ```
- Check VSO controller logs:
  ```bash
  kubectl logs -n vault-system deploy/vault-secrets-operator-controller-manager
  ```
- Confirm Vault auth mount and roles:
  ```bash
  vault auth list
  vault read auth/kubernetes/role/vso-static-role
  vault read auth/kubernetes/role/vso-dynamic-role
  ```
- Confirm synced secret resources:
  ```bash
  kubectl get vaultauth,vaultconnection,vaultstaticsecret,vaultdynamicsecret -n demo-app
  ```

## Cleanup

```bash
kubectl delete -f kubernetes/vso-k8s-auth-static-dynamic/vso-static-secret.yaml
kubectl delete -f kubernetes/vso-k8s-auth-static-dynamic/vso-dynamic-secret.yaml

vault policy delete vso-static || true
vault policy delete vso-dynamic || true
vault delete auth/kubernetes/role/vso-static-role || true
vault delete auth/kubernetes/role/vso-dynamic-role || true
vault delete database/roles/app-role || true
```

