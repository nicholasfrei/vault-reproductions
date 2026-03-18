## Lab 5: Policies, namespaces, and KV v2 operations

### Overview / Objective

This covers the hybrid scenario for the Vault Professional Exam. You will have access to a VM and have to answer multiple-choice questions about policy path matching, token scope, and namespace behavior.

It focuses on:

- Parent/child namespace boundaries
- KV v2 policy path precision (`data/` and `metadata/`)
- Token scope differences when logging in at root namespace vs child namespace
- Common denial patterns
- Confirm token access with `+` and `*` wildcards in the policy path

---

### Preconditions

- Vault Enterprise is running and unsealed.
- You have a root token.
- `vault` CLI is installed and authenticated.

Confirm baseline status:

```bash
vault status
vault token lookup
```

Expected result:

```text
Sealed          false
```

---

### Steps

### 1) Create parent and child namespaces

Create a parent namespace and one child namespace used for policy tests.

```bash
vault namespace create platform
vault namespace create -namespace=platform team1
```

Verify namespace creation:

```bash
vault namespace list
vault namespace list -namespace=platform
```

Expected result:

```text
Keys
----
platform/

Keys
----
team1/
```

---

### 2) Enable KV v2 in the child namespace and seed test data

All data for this lab lives in `platform/team1`.

```bash
vault secrets enable -namespace=platform/team1 -path=kv kv-v2
vault kv put -namespace=platform/team1 kv/app/config username="app-user" password="lab-password"
```

Verify the seed secret:

```bash
vault kv get -namespace=platform/team1 kv/app/config
```

---

### 3) Create the same KV v2 policy in child and root namespaces

Write a least-privilege child policy that allows read/list only for one app path.

```bash
cat <<'EOF' > /tmp/team1-kv-read.hcl
path "kv/data/app/*" {
  capabilities = ["read"]
}

path "kv/metadata/app/*" {
  capabilities = ["read", "list"]
}
EOF
```

Apply the same policy name and HCL in both child and root:

```bash
vault policy write -namespace=platform/team1 team1-kv-read /tmp/team1-kv-read.hcl
vault policy write team1-kv-read /tmp/team1-kv-read.hcl
# verify the policy is applied in both namespaces
vault policy read -namespace=platform/team1 team1-kv-read
vault policy read team1-kv-read
```

Comparison intent for this lab:

- The policy text is identical in both namespaces.
- The login namespace determines token scope and how policy paths are evaluated.
- This is why `alice` can have the same policy name but different access outcomes.

---

### 4) Configure userpass in root and child to test login context

Create one login path in root and one in child to show token scope differences.

```bash
vault auth enable userpass || true
vault auth enable -namespace=platform/team1 userpass || true
```

Create user in root namespace:
- expected behavior: login in root issues a root-scoped token, so reads in `platform/team1` are denied even with the same policy name
```bash
vault write auth/userpass/users/alice password="rootpass123" policies="team1-kv-read"
```

Create child user bound to child policy:

```bash
vault write -namespace=platform/team1 auth/userpass/users/alice \
  password="childpass123" \
  policies="team1-kv-read"
```

---

### 5) Test login in root namespace (expected deny on child KV)

Log in without `-namespace` to get a root-namespace token.

```bash
vault login -method=userpass username=alice password="rootpass123"
vault token lookup
```

Try reading child data (expected deny):

```bash
vault kv get -namespace=platform/team1 kv/app/config
```

Expected error pattern:

```text
Code: 403. Errors:
* permission denied
```

Why this matters: same username and same policy name do not mean same scope; namespace context at login determines token scope.

---

### 6) Test login in child namespace (expected success on child KV)

Log in to child namespace explicitly.

```bash
vault login -namespace=platform/team1 -method=userpass username=alice password="childpass123"
vault token lookup -namespace=platform/team1
```

Read and list should now work for allowed path:

```bash
vault kv get -namespace=platform/team1 kv/app/config
vault kv list -namespace=platform/team1 kv/app
```

Negative test for path precision (expected deny):

```bash
vault kv get -namespace=platform/team1 kv/other/config
```

Expected error pattern:

```text
Code: 403. Errors:
* permission denied
```

---

### 7) Optional policy gotcha test: omit `metadata/` and observe list failures

This reproduces a common policy mistake: read works, list fails.

```bash
cat <<'EOF' > /tmp/team1-read-only-data.hcl
path "kv/data/app/*" {
  capabilities = ["read"]
}
EOF

vault policy write -namespace=platform/team1 team1-read-only-data /tmp/team1-read-only-data.hcl
vault write -namespace=platform/team1 auth/userpass/users/alice \
  password="childpass123" \
  policies="team1-read-only-data"
```

Retest:

```bash
vault kv get -namespace=platform/team1 kv/app/config
vault kv list -namespace=platform/team1 kv/app
```

Expected behavior:

- `kv get` succeeds
- `kv list` fails with permission denied (missing `kv/metadata/...` policy path)

Rollback note:

```bash
vault write -namespace=platform/team1 auth/userpass/users/alice \
  password="childpass123" \
  policies="team1-kv-read"
```

---

### Validation

Validation is complete when all are true:

- Root login user (`alice`) cannot read child namespace KV path.
- Child login user (`alice` in `platform/team1`) can read/list allowed KV path.
- Policy precision test reproduces expected list denial when `metadata/` path is omitted.

Useful final checks:

```bash
vault token lookup
vault token lookup -namespace=platform/team1
vault policy read -namespace=platform/team1 team1-kv-read
```

---

### Cleanup

Delete users, auth mounts, policies, and namespaces used in this lab.

```bash
vault delete auth/userpass/users/alice || true
vault auth disable userpass || true

vault delete -namespace=platform/team1 auth/userpass/users/alice || true
vault auth disable -namespace=platform/team1 userpass || true

vault policy delete team1-kv-read || true
vault policy delete -namespace=platform/team1 team1-kv-read || true
vault policy delete -namespace=platform/team1 team1-read-only-data || true

vault secrets disable -namespace=platform/team1 kv || true

vault namespace delete -namespace=platform team1 || true
vault namespace delete platform || true
```

---

### Policy path wildcard reference (`+` and `*`)

Vault ACL path matching supports two common wildcard patterns:

- `+` matches exactly one path segment between slashes.
- `*` is a glob suffix used at the end of a policy path to match any remaining characters.

Quick examples:

```hcl
# Match one segment: "team-a" or "team-b", but not "team/a/b"
# e.g. kv/data/team-a/config or kv/data/team-b/config
# but not kv/data/team/a/config or kv/data/team/b/config
path "kv/data/+/config" {
  capabilities = ["read"]
}

# Match everything below app/
path "kv/data/app/*" {
  capabilities = ["read"]
}

# KV v2 list requires metadata path coverage
path "kv/metadata/app/*" {
  capabilities = ["list"]
}
```

### References

- Namespace concepts: [Vault namespaces](https://developer.hashicorp.com/vault/docs/enterprise/namespaces)
- KV v2 API path behavior: [KV secrets engine (v2)](https://developer.hashicorp.com/vault/api-docs/secret/kv/kv-v2)
- ACL policies: [Vault policies](https://developer.hashicorp.com/vault/docs/concepts/policies)
