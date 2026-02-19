# OpenLDAP + Vault LDAP Secrets Engine Reproduction

This guide sets up OpenLDAP in Kubernetes and configures Vault v1.20.6 LDAP secrets engine rotation for:
- the bind account (`cn=admin,dc=example,dc=org`)
- a custom LDAP user (`cn=vault-bind,ou=People,dc=example,dc=org`)

It is intended for reproduction/testing only.

## Goal

- Deploy OpenLDAP in Kubernetes
- Bootstrap a custom LDAP user
- Configure Vault LDAP secrets engine at mount path `openldap`
- Validate `rotation_period` behavior relative to `last_vault_rotation`

## Step 1: Deploy OpenLDAP in Kubernetes

Apply [openldap-deployment.yaml](openldap-deployment.yaml):

```bash
kubectl apply -f openldap-deployment.yaml
```

Verify connectivity from Vault pod:

```bash
kubectl exec -ti vault-0 -n vault -- sh
nc -zv openldap-service.vault.svc.cluster.local 389
```

## Step 2: Configure Vault LDAP Secrets Engine

Note: this repro uses mount path `openldap`, so all API paths below use the `openldap/...` prefix.

### 1) Enable the engine

```bash
vault secrets enable -path=openldap ldap
```

### 2) Configure bind credentials

```bash
vault write openldap/config \
  binddn="cn=admin,dc=example,dc=org" \
  bindpass="admin" \
  url="ldap://openldap-service.vault.svc.cluster.local:389" \
  password_policy="default" \
  rotation_period="60s" \
  schema="openldap"
```

The `cn=admin` account in this OpenLDAP image has enough privileges for rotation in this test setup.

### 3) Configure static role for custom user

```bash
vault write openldap/static-role/vault-bind \
  dn="cn=vault-bind,ou=People,dc=example,dc=org" \
  username="vault-bind" \
  rotation_period="60s" \
  password_policy="default"
```

If you receive LDAP error `32` (No such object), verify the DN exactly matches the LDIF entry.

## Step 3: Verify Rotation and Timestamps

### 1) Check initial bind account state

```bash
vault read openldap/config
```

Look for:
- `last_vault_rotation`
- `password_last_set` (if present in your version)

### 2) Wait and re-check

```bash
sleep 65
vault read openldap/config
```

### 3) Manual rotation test for bind account

```bash
vault write -f openldap/rotate-root
vault read openldap/config
```

Then:

```bash
sleep 30
# re-write config if needed during testing
vault write openldap/config rotation_period="60s" ...
sleep 35
vault read openldap/config
```

Expected: rotation should be relative to `last_vault_rotation`, not simply config write time.

### 4) Verify static role rotation

```bash
vault read openldap/static-role/vault-bind
sleep 65
vault read openldap/static-role/vault-bind
```

If supported in your Vault version, trigger manual static-role rotation:

```bash
vault write -f openldap/rotate-role/vault-bind
vault read openldap/static-role/vault-bind
```

## Expected Vault 1.20.6 Behavior

Vault tracks `last_vault_rotation` and periodically evaluates:

`(now - last_vault_rotation) > rotation_period`

When true, Vault rotates and updates `last_vault_rotation`.

Rotation timing is relative to `last_vault_rotation`, not strictly to config update time (unless a config update also triggers an immediate rotation event).

## Troubleshooting LDAP Error 32

Validate user existence from Vault pod:

```bash
ldapsearch -x \
  -H ldap://openldap-service.vault.svc.cluster.local:389 \
  -D "cn=admin,dc=example,dc=org" -w admin \
  -b "ou=People,dc=example,dc=org" "(cn=vault-bind)"
```

If no entry is returned, fix either:
- LDIF bootstrap data
- the static role `dn` value

## Notes

- This repro uses simple credentials (`admin` / `initial-password`) and is not production-hardened.
- For production, use secrets management for credentials, TLS for LDAP transport, and persistence controls for LDAP data.