# Dynamic Policy Reproduction (Userpass + Entity Metadata)

## Objective

Reproduce and validate dynamic policy behavior in Vault where policy templates reference identity metadata, and access changes immediately for an already-issued token when metadata changes.

This guide uses entity metadata as the primary path because it is simpler and more reliable than accessor-specific alias templating for a local repro.

## What this proves

- policy templates are evaluated at request time
- existing user tokens are affected by identity metadata updates
- access can be revoked/granted without forcing token rotation or re-login

## Prerequisites

- Vault binary installed locally
- two terminal windows (user session and admin/root session)

## Step 1: Start local Vault

Terminal 1:

```bash
vault server -dev -dev-root-token-id=root
```

Terminal 2:

```bash
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='root'
```

## Step 2: Create test secrets

```bash
vault secrets enable -path=test kv-v2

vault kv put test/dev/my-secret value='I am a DEV secret'
vault kv put test/uat/my-secret value='I am a UAT secret'
```

## Step 3: Configure userpass and user

```bash
vault auth enable userpass
vault write auth/userpass/users/testuser password='password'
```

## Step 4: Create dynamic policy using entity metadata

Create file `dynamic-policy-entity.hcl`:

```hcl
path "test/metadata/*" {
  capabilities = ["list"]
}

path "test/data/{{identity.entity.metadata.environment}}/*" {
  capabilities = ["read"]
}

path "test/data/{{identity.entity.metadata.environment}}" {
  capabilities = ["read"]
}
```

Write and attach policy:

```bash
vault policy write dynamic-repro - < dynamic-policy-entity.hcl
vault write auth/userpass/users/testuser policies='dynamic-repro'
```

## Step 5: Create identity by logging in once

In user terminal:

```bash
vault login -method=userpass username=testuser password=password
vault token lookup
```

Copy `entity_id` from `vault token lookup` output.

## Step 6: Set initial entity metadata to dev

In root/admin terminal:

```bash
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='root'

ENTITY_ID='<ENTITY_ID_FROM_TOKEN_LOOKUP>'
vault write identity/entity/id/$ENTITY_ID metadata=environment=dev
vault read identity/entity/id/$ENTITY_ID
```

Expected: `metadata` contains `environment: dev`.

## Step 7: Validate baseline behavior with same user token

In user terminal (no new login):

```bash
vault kv get test/dev/my-secret
```

Expected: success.

```bash
vault kv get test/uat/my-secret
```

Expected: permission denied.

## Step 8: Change metadata to uat and verify immediate effect

In root/admin terminal:

```bash
vault write identity/entity/id/$ENTITY_ID metadata=environment=uat
```

Back in user terminal, using same token and no re-login:

```bash
vault kv get test/dev/my-secret
```

Expected: permission denied.

```bash
vault kv get test/uat/my-secret
```

Expected: success.

## Optional: capability introspection

From user terminal:

```bash
vault write sys/capabilities-self path='test/data/dev/my-secret'
vault write sys/capabilities-self path='test/data/uat/my-secret'
```

## Optional appendix: alias metadata variant

If you want to reproduce with alias metadata, use:

- template path: `{{identity.entity.aliases.<MOUNT_ACCESSOR>.metadata.environment}}`
- write alias metadata via `custom_metadata`, not `metadata`

Example write:

```bash
vault write identity/entity-alias/id/<ALIAS_ID> custom_metadata=environment=dev
```

Notes:
- alias-based templating is accessor-specific and easier to misconfigure
- accessor mismatch leads to empty template resolution and permission denied
- entity metadata is generally the cleaner baseline for dynamic policy repros

## Troubleshooting quick checks

1. Token has wrong policy

```bash
vault token lookup
vault read auth/userpass/users/testuser
```

2. KV v2 path mismatch

Policy must target `test/data/...` for reads.

3. Metadata not present

```bash
vault read identity/entity/id/$ENTITY_ID
```

4. Access still denied

```bash
vault read sys/policy/dynamic-repro
vault write sys/capabilities-self path='test/data/dev/my-secret'
```

## Conclusion

This reproduction confirms that dynamic policy templates are evaluated at request time. Changing entity metadata updates effective authorization immediately for existing tokens.
