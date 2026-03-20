# OpenLDAP LDAP Auth Reproduction (Vault + Kubernetes)

This runbook deploys a local OpenLDAP instance and a Vault instance in Kubernetes, and validates LDAP auth logins and group-to-policy mapping behavior. It is a useful reference for understanding how Vault LDAP auth works and how to configure it.

It creates a repeatable LDAP directory with:
- 200 sample users
- multiple direct groups (`vault-admins`, `vault-readers`, `vault-ops`)
- nested group examples (`vault-engineering` includes `vault-readers` and `vault-ops`)

It then validates Vault LDAP auth logins and group-to-policy mapping behavior.

## Prerequisites

- Docker
- Vault CLI
- `kubectl` configured to your existing cluster
- `ldapsearch` (optional, used for validation from host)

## Environment Setup

### 1. Hostname Expectations

For this setup, OpenLDAP runs in Docker on your host (`0.0.0.0:389`):

- Vault (running in Kubernetes) connects to `host.minikube.internal`
- Host-side LDAP checks connect to `localhost`

### 2. Start an OpenLDAP Container

Run this command to start a clean OpenLDAP lab instance.

```bash
docker run -d \
  --name openldap-vault \
  -e LDAP_ORGANISATION="Vault Test Org" \
  -e LDAP_DOMAIN="example.org" \
  -e LDAP_ADMIN_PASSWORD="admin" \
  -p 389:389 \
  osixia/openldap:1.5.0
```

Run this command to verify the container is running.

```bash
docker ps | grep openldap-vault
```

Run this command to validate base LDAP connectivity.

```bash
ldapsearch -x -H ldap://localhost:389 -D "cn=admin,dc=example,dc=org" -w admin -b "dc=example,dc=org" "(objectClass=*)"
```

Expected result: LDAP entries are returned and the command exits successfully.

### 3. Generate Bulk LDAP Data (Users + Groups)

Run this command to generate deterministic LDIF data with 200 users and multiple groups.

```bash
cat > openldap-bulk.ldif <<'EOF'
dn: ou=People,dc=example,dc=org
objectClass: organizationalUnit
ou: People

dn: ou=Groups,dc=example,dc=org
objectClass: organizationalUnit
ou: Groups

EOF

for i in $(seq -w 1 200); do
  cat >> openldap-bulk.ldif <<EOF
dn: uid=user${i},ou=People,dc=example,dc=org
objectClass: inetOrgPerson
objectClass: organizationalPerson
objectClass: person
objectClass: top
cn: User ${i}
sn: User${i}
uid: user${i}
mail: user${i}@example.org
userPassword: Passw0rd!

EOF
done

cat >> openldap-bulk.ldif <<'EOF'
dn: cn=vault-readers,ou=Groups,dc=example,dc=org
objectClass: groupOfNames
cn: vault-readers
member: uid=user001,ou=People,dc=example,dc=org
member: uid=user002,ou=People,dc=example,dc=org
member: uid=user003,ou=People,dc=example,dc=org

dn: cn=vault-ops,ou=Groups,dc=example,dc=org
objectClass: groupOfNames
cn: vault-ops
member: uid=user004,ou=People,dc=example,dc=org
member: uid=user005,ou=People,dc=example,dc=org

dn: cn=vault-admins,ou=Groups,dc=example,dc=org
objectClass: groupOfNames
cn: vault-admins
member: uid=user010,ou=People,dc=example,dc=org
member: uid=user011,ou=People,dc=example,dc=org

dn: cn=vault-engineering,ou=Groups,dc=example,dc=org
objectClass: groupOfNames
cn: vault-engineering
member: cn=vault-readers,ou=Groups,dc=example,dc=org
member: cn=vault-ops,ou=Groups,dc=example,dc=org

EOF
```

Run this command to import the LDIF into OpenLDAP.

```bash
docker exec -i openldap-vault ldapadd -x \
  -H ldap://localhost:389 \
  -D "cn=admin,dc=example,dc=org" \
  -w admin \
  -f /dev/stdin < openldap-bulk.ldif
```

Expected result: output shows `adding new entry` for `ou=People`, `ou=Groups`, users, and groups.

### 4. Connect to Vault Pod

Run this command to enter the Vault pod shell.

```bash
kubectl exec -n vault vault-0 -ti -- sh
```

Expected result: you have a shell inside the Vault pod and can run `vault` commands.

## Configure LDAP Auth in Vault

### 1. Enable LDAP Auth

Run this command to enable LDAP auth at the default path.

```bash
vault auth enable ldap
```

Expected result: `Success! Enabled ldap auth method at: ldap/`.

### 2. Configure LDAP Connection

Run this command to configure Vault LDAP auth against the host-side OpenLDAP container.

```bash
vault write auth/ldap/config \
  url="ldap://host.minikube.internal:389" \
  binddn="cn=admin,dc=example,dc=org" \
  bindpass="admin" \
  userdn="ou=People,dc=example,dc=org" \
  userattr="uid" \
  groupdn="ou=Groups,dc=example,dc=org" \
  groupfilter="(&(objectClass=groupOfNames)(member={{.UserDN}}))" \
  groupattr="cn"
```

Run this command to verify LDAP auth config is readable.

```bash
vault read auth/ldap/config
```

Expected result: config is returned with expected `url`, `userdn`, `groupdn`, and `groupfilter`.

### 3. Create Policies for Group Mapping

Run this command to create minimal test policies.

```bash
cat > ldap-reader.hcl <<'EOF'
path "secret/data/ldap-demo" {
  capabilities = ["read"]
}
EOF

cat > ldap-admin.hcl <<'EOF'
path "secret/data/ldap-demo" {
  capabilities = ["create", "update", "read", "delete", "list"]
}
EOF

vault policy write ldap-reader ldap-reader.hcl
vault policy write ldap-admin ldap-admin.hcl
```

Expected result: both policy writes return `Success! Uploaded policy`.

### 4. Map LDAP Groups to Vault Policies

Run this command to map groups to policies.

```bash
vault write auth/ldap/groups/vault-readers policies="ldap-reader"
vault write auth/ldap/groups/vault-admins policies="ldap-admin"
vault write auth/ldap/groups/vault-ops policies="ldap-reader"
```

Run this command to verify one mapping quickly.

```bash
vault read auth/ldap/groups/vault-readers
```

Expected result: returned object includes policy `ldap-reader`.

## Testing LDAP Logins

### 1. Test a Reader Login

Run this command to authenticate as a user in `vault-readers`.

```bash
vault login -method=ldap username=user001 password=Passw0rd!
```

Expected result: login succeeds and token policies include `ldap-reader`.

### 2. Test an Admin Login

Run this command to authenticate as a user in `vault-admins`.

```bash
vault login -method=ldap username=user010 password=Passw0rd!
```

Expected result: login succeeds and token policies include `ldap-admin`.

### 3. Test a User with No Group Mapping

Run this command to authenticate as a user not present in mapped groups.

```bash
vault login -method=ldap username=user150 password=Passw0rd!
```

Expected result: login succeeds but token has only default policy (no `ldap-reader`/`ldap-admin`).

### 4. Validate Access Differences

Run this command to create a test secret as an admin user token.

```bash
vault kv put secret/ldap-demo value="ldap-auth-repro"
```

Run this command to confirm a reader token can read but not write.

```bash
vault kv get secret/ldap-demo
vault kv put secret/ldap-demo value="should-fail-for-reader"
```

Expected result: read succeeds, write fails with `permission denied`.

## Testing Nested Group Behavior (Group Inheritance)

### 1. Show Nested Group Example in LDAP

Run this command from your host shell to verify `vault-engineering` contains group DNs, not user DNs.

```bash
ldapsearch -x \
  -H ldap://localhost:389 \
  -D "cn=admin,dc=example,dc=org" -w admin \
  -b "ou=Groups,dc=example,dc=org" "(cn=vault-engineering)"
```

Expected result: members are `cn=vault-readers,...` and `cn=vault-ops,...`.

### 2. Understand Default Vault Behavior Here

With this runbook's `groupfilter`, Vault matches groups where `member={{.UserDN}}`.

That means nested parent groups are not expanded automatically in this basic OpenLDAP setup.

### 3. Optional: Flatten Membership for Inheritance-Like Testing

Run this command from your host shell to add direct user membership into `vault-engineering`.

```bash
cat > openldap-engineering-flatten.ldif <<'EOF'
dn: cn=vault-engineering,ou=Groups,dc=example,dc=org
changetype: modify
add: member
member: uid=user001,ou=People,dc=example,dc=org
-
add: member
member: uid=user004,ou=People,dc=example,dc=org
EOF

docker exec -i openldap-vault ldapmodify -x \
  -H ldap://localhost:389 \
  -D "cn=admin,dc=example,dc=org" \
  -w admin \
  -f /dev/stdin < openldap-engineering-flatten.ldif
```

Run this command in Vault pod shell to map the parent group and validate login results.

```bash
vault write auth/ldap/groups/vault-engineering policies="ldap-reader"
vault login -method=ldap username=user001 password=Passw0rd!
```

Expected result: `user001` now receives policy from `vault-engineering` because membership is direct.

## Verification Checklist

- OpenLDAP container is reachable from host and Vault pod
- Vault LDAP auth config is readable and points to `host.minikube.internal`
- Reader/admin users can authenticate successfully
- Group mappings apply expected policies
- Non-mapped users authenticate without mapped policies
- Nested-group parent mapping does not apply unless membership is flattened

## Cleanup

The following actions are destructive and remove this LDAP auth repro data.

Run this command in Vault pod shell to remove auth and policies.

```bash
vault auth disable ldap
vault policy delete ldap-reader
vault policy delete ldap-admin
```

Run this command on host to remove OpenLDAP container and local temp files.

```bash
docker stop openldap-vault
docker rm openldap-vault
rm -f openldap-bulk.ldif openldap-engineering-flatten.ldif
```

## Notes

- This runbook uses plaintext LDAP (`ldap://`) and simple passwords for local reproduction only.
  - For production, use `ldaps://` or StartTLS, stronger bind account handling, and stricter policy scope.
- If you need true recursive group inheritance behavior (for example AD matching-rule style), validate against your directory implementation rather than relying on this basic OpenLDAP pattern.
