# LDAP Secrets Engine - Dynamic Role Uppercase Name Bug Reproduction up to `2.0.4`

This reproduction demonstrates a bug in the Vault LDAP secrets engine where dynamic roles created with ALL CAPS for the role name behave inconsistently. This issue exists across multiple Vault versions including `1.16.x`, `1.19.x`, and `1.21.4+ent`. Static roles are not affected.

## Overview

- Role creation with an uppercase name succeeds and returns no error.
- The role appears in `vault list ldap/role` 
- `vault read ldap/role/UPPERCASE_ROLE` returns `No value found`.
- `vault delete ldap/role/UPPERCASE_ROLE` returns success but the role remains listed.
- `vault read ldap/creds/UPPERCASE_ROLE` returns `No value found`.
- The role entry is confirmed present in `sys/raw` under the uppercase key.
- Orphaned metadata cannot be cleaned up via normal CLI operations.

## Objective

Confirm the broken lifecycle (create → list → read → delete → list) for an LDAP dynamic role whose name contains uppercase characters, and verify the entry's presence in raw storage.

## Prerequisites

- Vault `1.21.4+ent` (or any affected version) running in Kubernetes, accessible via `kubectl exec`.
- OpenLDAP container reachable from the Vault pod (this repro uses `ldap://host.docker.internal:389`).
- LDAP secrets engine already enabled and configured at the `ldap/` mount path.
- Root or highly privileged Vault token with access to `sys/raw/`.
- LDIF files for dynamic role creation (see Step 1 below).

The LDAP secrets engine must already be configured. If starting from scratch, run:

```bash
vault secrets enable ldap

vault write ldap/config \
    binddn="cn=admin,dc=example,dc=org" \
    bindpass='SuperSecretPassword!' \
    url="ldap://host.docker.internal:389" \
    userdn="ou=service-accounts,dc=example,dc=org"
```

Verify the config was applied:

```bash
vault read ldap/config
```

## Step 1: Create the LDIF Files

Dynamic roles require three LDIF templates. Write them inside the Vault pod before creating roles. Note that omitting these files returns a `500` error even though the role name itself is accepted — `creation_ldif` is required.

```bash
cat << 'EOF' > /tmp/creation.ldif
dn: cn={{.Username}},ou=service-accounts,dc=example,dc=org
objectClass: inetOrgPerson
objectClass: organizationalPerson
objectClass: person
cn: {{.Username}}
sn: {{.Username}}
uid: {{.Username}}
userPassword: {{.Password}}
EOF
```

```bash
cat << 'EOF' > /tmp/deletion.ldif
dn: cn={{.Username}},ou=service-accounts,dc=example,dc=org
changetype: delete
EOF
```

```bash
cat << 'EOF' > /tmp/rollback.ldif
dn: cn={{.Username}},ou=service-accounts,dc=example,dc=org
changetype: delete
EOF
```

## Step 2: Create a Lowercase Role (Baseline)

First establish a working baseline with an all-lowercase role name to confirm normal behavior.

```bash
vault write ldap/role/dev-role \
    creation_ldif=@/tmp/creation.ldif \
    deletion_ldif=@/tmp/deletion.ldif \
    rollback_ldif=@/tmp/rollback.ldif \
    default_ttl=15m \
    max_ttl=1h
```

Expected output:

```text
Success! Data written to: ldap/role/dev-role
```

Verify the lowercase role reads back correctly:

```bash
vault read ldap/role/dev-role
```

Expected output:

```text
Key              Value
---              -----
creation_ldif    dn: cn={{.Username}},ou=service-accounts,dc=example,dc=org
                 objectClass: inetOrgPerson
                 objectClass: organizationalPerson
                 objectClass: person
                 cn: {{.Username}}
                 sn: {{.Username}}
                 uid: {{.Username}}
                 userPassword: {{.Password}}
default_ttl      15m
deletion_ldif    dn: cn={{.Username}},ou=service-accounts,dc=example,dc=org
                 changetype: delete
max_ttl          1h
rollback_ldif    dn: cn={{.Username}},ou=service-accounts,dc=example,dc=org
                 changetype: delete
username_template    n/a
```

## Step 3: Create an Uppercase Role

Create a second role using the same LDIF files, this time with uppercase characters in the role name.

```bash
vault write ldap/role/NEW_ROLE \
    creation_ldif=@/tmp/creation.ldif \
    deletion_ldif=@/tmp/deletion.ldif \
    rollback_ldif=@/tmp/rollback.ldif \
    default_ttl=15m \
    max_ttl=1h
```

Expected output (creation succeeds with no error):

```text
Success! Data written to: ldap/role/NEW_ROLE
```

## Step 4: Observe the Bug

### 4a. List shows both roles

```bash
vault list ldap/role
```

Expected output (uppercase role appears alongside the lowercase baseline):

```text
Keys
----
NEW_ROLE
dev-role
```

### 4b. Read fails for the uppercase role

```bash
vault read ldap/role/NEW_ROLE
```

Expected output:

```text
No value found at ldap/role/NEW_ROLE
```

The lowercase role still reads correctly, confirming this is isolated to uppercase names:

```bash
vault read ldap/role/dev-role
```

### 4c. Credential generation fails

```bash
vault read ldap/creds/NEW_ROLE
```

Expected output:

```text
No value found at ldap/creds/NEW_ROLE
```

### 4d. Delete reports success but role persists

```bash
vault delete ldap/role/NEW_ROLE
```

Expected output:

```text
Success! Data deleted (if it existed) at: ldap/role/NEW_ROLE
```

Re-list to confirm the role has not been removed:

```bash
vault list ldap/role
```

Expected output (`NEW_ROLE` still present after deletion):

```text
Keys
----
NEW_ROLE
dev-role
```

## Step 5: Confirm the Entry in Raw Storage

This step confirms the role data was written to storage successfully under the uppercase key in `sys/raw`. First, find the mount UUID. Retrieve it from the mount config:

```bash
vault read sys/mounts/ldap -format=json
```

Expected output (truncated):

```text
{
  "data": {
    ...
    "uuid": "202daf2b-92b9-9b7a-6a19-e8eb3933d049"
  }
}
```

List the raw logical mounts to find the correct UUID prefix:

```bash
vault list sys/raw/logical
```

Expected output:

```text
Keys
----
202daf2b-92b9-9b7a-6a19-e8eb3933d049/
<sample_uuid>/
<sample_uuid>/
```

List the role keys under the LDAP mount UUID:

```bash
vault list sys/raw/logical/<uuid>/role/
```

Expected output (both roles present in storage):

```text
Keys
----
NEW_ROLE
dev-role
```

Read the raw entry for the uppercase role to confirm the data is intact:

```bash
vault read sys/raw/logical/<uuid>/role/NEW_ROLE
```

Expected output:

```text
Key      Value
---      -----
value    {"name":"NEW_ROLE","creation_ldif":"dn: cn={{.Username}},...","deletion_ldif":"...","rollback_ldif":"...","default_ttl":900000000000,"max_ttl":3600000000000}
```

The data is present. The bug is in the read and delete code paths, which normalize the role name to lowercase before performing the storage lookup. Since the key was written with its original casing (`NEW_ROLE`), the lowercased lookup (`new_role`) finds nothing.

## Cleanup

The lowercase role can be deleted normally:

```bash
vault delete ldap/role/dev-role
```

## Additional Notes

- Static roles (`ldap/static-role/`) are not affected. The static role write path normalizes the name to lowercase before storage, so the key and all subsequent lookups are consistent.
- The dynamic role write path does not normalize the name, storing it with original casing. All subsequent read, delete, and creds lookups normalize the name to lowercase, causing a key miss every time.
- Because `vault delete` is also affected, the list index entry is never cleaned up, making the orphan permanent without raw storage access.
- `vault list ldap/role` reflects the list index, not a direct storage scan, which is why the uppercase entry appears in list output even when the actual storage key read fails.

## References

- [Vault LDAP Secrets Engine - Dynamic Roles](https://developer.hashicorp.com/vault/docs/secrets/ldap#dynamic-roles)
- [Vault LDAP Secrets Engine API](https://developer.hashicorp.com/vault/api-docs/secret/ldap)
