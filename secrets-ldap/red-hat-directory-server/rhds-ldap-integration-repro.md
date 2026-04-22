# RHDS + Vault LDAP Secrets Engine Reproduction (Vault 1.16.7)

This runbook is intended to reproduce an integration with Red Hat Directory Server (RHDS) and the Vault LDAP secrets engine. The reproduction uses the open source 389 Directory Server (389ds) image which is functionally similar for testing purposes (and free).

Version Mapping:

    RHDS 12 → 389-ds 2.0.x
    RHDS 11 → 389-ds 1.4.x
    RHDS 10 → 389-ds 1.3.x

## Goal

- See compatibility with LDAP secrets engine & 389ds
    - Configure Vault 1.16.7 LDAP secrets engine
    - Manage 10 pre-existing LDAP users as Vault static roles
    - Validate automatic rotation and manual `rotate-role`
    - Validate `rotate-root` command
- Confirm old credentials fail and newly issued credentials succeed

## Prerequisites

- Vault CLI authenticated to Vault `1.16.7`
- Docker running on macOS
- `ldapadd`, `ldapsearch`, `ldapwhoami`
- Vault token with permissions to manage LDAP secrets engine and password policies
- `rhds-bootstrap.ldif` in this directory

## Step 1: Start 389ds and Create the LDAP Suffix

Use the upstream 389ds container image:

```bash
docker run -d \
  --name ds389-vault-repro \
  -p 3389:3389 \
  -p 3636:3636 \
  -e DS_DM_PASSWORD='DirectoryManagerPass1' \
  -e DS_SUFFIX_NAME='example.org' \
  389ds/dirsrv:latest
```

Confirm container health:

```bash
docker ps --filter name=ds389-vault-repro
```

Create the LDAP backend and suffix used by this reproduction:

```bash
docker exec ds389-vault-repro \
  dsconf localhost backend create \
  --suffix "dc=example,dc=org" \
  --be-name userroot \
  --create-suffix
```

Confirm LDAP is reachable from macOS by querying the root DSE:

```bash
ldapsearch -x \
  -H "ldap://127.0.0.1:3389" \
  -D "cn=Directory Manager" \
  -w 'DirectoryManagerPass1' \
  -b "" \
  -s base \
  "(objectClass=*)" namingContexts
```

Expected output includes `namingContexts: dc=example,dc=org`.

Do not continue until the suffix is returned from the root DSE query.

## Step 2: Load the Directory Data and Embedded ACLs

Skip the bootstrap import only if this lab's OUs, service account, users, and access-control instructions already exist.

Load OUs, service account, users `app01` through `app10`, and the service-account ACLs needed for static-role import and password rotation:

```bash
ldapadd -x \
  -H "ldap://127.0.0.1:3389" \
  -D "cn=Directory Manager" \
  -w 'DirectoryManagerPass1' \
  -f rhds-bootstrap.ldif
```

Verify users exist:

```bash
ldapsearch -x \
  -H "ldap://127.0.0.1:3389" \
  -D "cn=Directory Manager" \
  -w 'DirectoryManagerPass1' \
  -b "ou=people,dc=example,dc=org" \
  "(uid=app*)" dn uid
```

The bootstrap LDIF loads the OUs, service account, application users, and ACI rules under the backend and suffix created in Step 1.

Optional pre-check:

```bash
ldapwhoami -x \
  -H "ldap://127.0.0.1:3389" \
  -D "uid=app01,ou=people,dc=example,dc=org" \
  -w 'App01InitialPass1'
```

If the user search returns no entries, stop here and correct the bootstrap data before continuing.

Verify the Vault bind account can see managed users before configuring the LDAP secrets engine:

```bash
ldapsearch -x \
  -H "ldap://127.0.0.1:3389" \
  -D "uid=vault-svc,ou=svc,dc=example,dc=org" \
  -w 'VaultSvcInitialPass1' \
  -b "ou=people,dc=example,dc=org" \
  "(uid=app01)" dn uid
```

If this search returns no entries, Vault static-role creation will fail with `expected one matching entry, but received 0`.

Do not continue until the `vault-svc` bind account can search for `app01` successfully.

## Step 3: Configure the Vault Password Policy and LDAP Engine

Create an alphanumeric password policy:

```bash
cat > /tmp/ds389-alnum-policy.hcl <<'EOF'
length = 24

rule "charset" {
  charset = "abcdefghijklmnopqrstuvwxyz"
  min-chars = 1
}

rule "charset" {
  charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  min-chars = 1
}

rule "charset" {
  charset = "0123456789"
  min-chars = 1
}
EOF

vault write sys/policies/password/ds389-alnum policy=@/tmp/ds389-alnum-policy.hcl
vault read sys/policies/password/ds389-alnum
```

Enable and configure LDAP secrets engine:

```bash
vault secrets enable -path="ds389" ldap

vault write ds389/config \
  binddn="uid=vault-svc,ou=svc,dc=example,dc=org" \
  bindpass="VaultSvcInitialPass1" \
  url="ldap://host.docker.internal:3389" \
  userdn="dc=example,dc=org" \
  userattr="uid" \
  schema="openldap" \
  password_policy="ds389-alnum" \
  request_timeout="30s"

vault read ds389/config
```

`userdn` is set to `dc=example,dc=org` rather than `ou=people,dc=example,dc=org`. This single search base covers both the bind account (`ou=svc`) and the managed users (`ou=people`), so no config changes are needed between root rotation and static-role management.

## Step 4: Validate Root Rotation

Run this before creating static roles. Because Step 3 set `userdn` to `dc=example,dc=org`, Vault can already locate the bind account (`uid=vault-svc,ou=svc`) during root rotation — no config changes are needed.

`rotate-root` rotates the bind account's password in LDAP and stores the new credential internally. The new password is never returned by Vault, so verification is done by confirming that subsequent operations using the bind account continue to succeed.

Verify the bind account is reachable before rotating:

```bash
ldapsearch -x \
  -H "ldap://127.0.0.1:3389" \
  -D "uid=vault-svc,ou=svc,dc=example,dc=org" \
  -w 'VaultSvcInitialPass1' \
  -b "dc=example,dc=org" \
  "(uid=vault-svc)" dn uid
```

Rotate the LDAP root credential:

```bash
vault write -f ds389/rotate-root
```

Expected output: `Success! Data written to: ds389/rotate-root`

If the command succeeds, Vault's internal bind credential is valid. Successful static-role creation in Step 5 further confirms the rotated credential works end-to-end.

Do not continue if `rotate-root` returns an error.

## Step 5: Create Static Roles for `app01` Through `app10`

Creating static roles imports each account and rotates its password immediately.

```bash
for i in $(seq -w 1 10); do
  vault write "ds389/static-role/app${i}" \
    username="app${i}" \
    dn="uid=app${i},ou=people,dc=example,dc=org" \
    rotation_period="60s"
done

vault list ds389/static-role
vault read ds389/static-role/app01
```

If role creation returns `No such object`, verify the target user DN exists under `ou=people,dc=example,dc=org` before retrying. If role creation returns `expected one matching entry, but received 0`, return to Step 2 and re-verify the bootstrap import and bind-account search.

## Step 6: Validate the Current Vault Credentials

Read one credential set:

```bash
vault read ds389/static-cred/app01
```

If the role exists but no password is returned, force the first rotation and then re-read the credential:

```bash
vault write -f ds389/rotate-role/app01
vault read ds389/static-cred/app01
```

Validate all 10 current Vault-issued credentials with LDAP bind:

```bash
for i in $(seq -w 1 10); do
  password=$(vault read -field=password "ds389/static-cred/app${i}")
  ldapwhoami -x \
    -H "ldap://127.0.0.1:3389" \
    -D "uid=app${i},ou=people,dc=example,dc=org" \
    -w "$password" > /dev/null
  echo "app${i}: bind succeeded"
done
```

If any bind fails with `Invalid Credentials`, re-read the current password from `ds389/static-cred/appXX` and verify you are using the correct DN for that user.

## Step 7: Validate Automatic Rotation

Capture rotation timestamps before and after rotation to confirm rotation occured as expected:

```bash
for i in $(seq -w 1 10); do
  echo -n "app${i}: "
  vault read -field=last_vault_rotation "ds389/static-cred/app${i}"
done

sleep 65

for i in $(seq -w 1 10); do
  echo -n "app${i}: "
  vault read -field=last_vault_rotation "ds389/static-cred/app${i}"
done
```

Validate the newly rotated passwords:

```bash
for i in $(seq -w 1 10); do
  password=$(vault read -field=password "ds389/static-cred/app${i}")
  ldapwhoami -x \
    -H "ldap://127.0.0.1:3389" \
    -D "uid=app${i},ou=people,dc=example,dc=org" \
    -w "$password" > /dev/null
  echo "app${i}: bind succeeded after automatic rotation"
done
```

389ds may store passwords in hashed form. Validate rotation by binding with `ldapwhoami`, not by comparing the `userPassword` attribute value directly.

## Step 8: Validate Manual Rotation

Rotate one role first and verify password changed:

```bash
old_password=$(vault read -field=password ds389/static-cred/app01)
old_rotation=$(vault read -field=last_vault_rotation ds389/static-cred/app01)

vault write -f ds389/rotate-role/app01

new_password=$(vault read -field=password ds389/static-cred/app01)
new_rotation=$(vault read -field=last_vault_rotation ds389/static-cred/app01)

printf 'old rotation: %s\nnew rotation: %s\n' "$old_rotation" "$new_rotation"
test "$old_password" != "$new_password" && echo "password changed"
```

Old password should fail:

```bash
ldapwhoami -x \
  -H "ldap://127.0.0.1:3389" \
  -D "uid=app01,ou=people,dc=example,dc=org" \
  -w "$old_password"
```

New password should succeed:

```bash
ldapwhoami -x \
  -H "ldap://127.0.0.1:3389" \
  -D "uid=app01,ou=people,dc=example,dc=org" \
  -w "$new_password"
```

Rotate all roles on demand and validate all binds:

```bash
for i in $(seq -w 1 10); do
  vault write -f "ds389/rotate-role/app${i}"
done

for i in $(seq -w 1 10); do
  password=$(vault read -field=password "ds389/static-cred/app${i}")
  ldapwhoami -x \
    -H "ldap://127.0.0.1:3389" \
    -D "uid=app${i},ou=people,dc=example,dc=org" \
    -w "$password" > /dev/null
  echo "app${i}: bind succeeded after manual rotation"
done
```

## Notes on Events/Webhooks for Vault 1.16.7

For Vault 1.16.7, prioritize static-role validation. LDAP-specific event notification types were introduced after 1.16.x, so do not expect `ldap/rotate`-style event types here.

## Cleanup

Disable LDAP secrets mount:

```bash
vault secrets disable ds389
```

Remove password policy if desired:

```bash
vault delete sys/policies/password/ds389-alnum
```

Stop and remove 389ds container:

```bash
docker rm -f ds389-vault-repro
```

Removing the container discards the lab directory data, including the imported users and embedded ACLs.

## References

- https://developer.hashicorp.com/vault/docs/v1.16.x/secrets/ldap
- https://developer.hashicorp.com/vault/api-docs/v1.16.x/secret/ldap
- https://developer.hashicorp.com/vault/docs/v1.16.x/concepts/password-policies
- https://developer.hashicorp.com/vault/docs/concepts/events#subscribing-to-event-notifications
