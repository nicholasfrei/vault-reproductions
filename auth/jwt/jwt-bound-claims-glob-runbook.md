# Vault JWT `bound_claims_type=glob` Runbook (Kubernetes Cluster)

## Objective

Reproduce and explain why JWT logins can fail with:

`error validating claims: claim "namespace_path" does not match any associated bound claim values`

Then validate the fix using `bound_claims_type="glob"` for hierarchical paths such as GitLab `namespace_path`, using an existing Vault deployment in Kubernetes.

## Scenario Context

After upgrading Vault, a JWT role that previously used parent group style matching (for example `Databases`) started failing for projects in nested groups (for example `databases/graphdb/aws`).

Key behavior to remember:

- `bound_claims_type="string"` requires exact claim value matches
- `bound_claims_type="glob"` allows wildcard matching (for example `databases/*`)
- Matching is case-sensitive

## Prerequisites

- a running Vault cluster in Kubernetes
- `kubectl`, `jq`, and `openssl` installed locally
- Vault pod is already logged in with a token that can manage auth methods, policies, and roles

## Shell context used in this runbook

- Run Vault administrative commands from inside the Vault pod shell (assume you are already `kubectl exec`'d into the pod).
- Run JWT generation and login attempts from your local shell.

## Step 1: Check Vault Status

Quick connectivity check:

```bash
vault status
```

Expected result: Vault status is returned successfully.

## Step 2: Generate local key pair and configure JWT auth in Vault

Generate keys locally:

```bash
openssl genrsa -out jwt-private.pem 2048
openssl rsa -in jwt-private.pem -pubout -out jwt-public.pem
```

Upload the public key into the Vault pod:

```bash
kubectl exec -i vault-0 -n vault -- sh -c "cat > /tmp/jwt-public.pem" < jwt-public.pem
```

Enable JWT auth at a dedicated path and configure it:

```bash
vault auth enable -path=jwt-test jwt

vault write "auth/jwt-test/config" \
  bound_issuer="https://code.test.com" \
  jwt_supported_algs="RS256" \
  jwt_validation_pubkeys=@/tmp/jwt-public.pem
```

Expected result: `auth/jwt-test/config` is written successfully.

## Step 3: Create role with exact string matching (failure case)

Write a minimal demo policy:

```bash
cat > /tmp/read-secrets.hcl <<'EOF'
path "secret/data/*" {
  capabilities = ["read"]
}
EOF

vault policy write read-secrets /tmp/read-secrets.hcl
```

Create the JWT role with `bound_claims_type="string"`:

```bash
vault write auth/jwt-test/role/read-secrets - <<EOF
{
  "role_type": "jwt",
  "user_claim": "user_email",
  "bound_audiences": ["https://code.test.com"],
  "bound_claims_type": "string",
  "bound_claims": {
    "namespace_path": "Databases"
  },
  "token_policies": ["read-secrets"]
}
EOF
```

Generate a JWT locally that simulates a nested GitLab path:

```bash
NOW="$(date +%s)"
EXP="$((NOW + 3600))"
HEADER='{"alg":"RS256","typ":"JWT"}'
PAYLOAD="$(jq -cn \
  --arg iss "https://code.test.com" \
  --arg aud "https://code.test.com" \
  --arg email "svc@example.com" \
  --arg ns "databases/graphdb/aws" \
  --argjson iat "$NOW" \
  --argjson exp "$EXP" \
  '{iss:$iss,aud:$aud,user_email:$email,namespace_path:$ns,iat:$iat,exp:$exp}')"

HEADER_B64="$(printf '%s' "$HEADER" | openssl base64 -A | tr '+/' '-_' | tr -d '=')"
PAYLOAD_B64="$(printf '%s' "$PAYLOAD" | openssl base64 -A | tr '+/' '-_' | tr -d '=')"
SIGNING_INPUT="${HEADER_B64}.${PAYLOAD_B64}"
SIG_B64="$(printf '%s' "$SIGNING_INPUT" | openssl dgst -sha256 -sign jwt-private.pem | openssl base64 -A | tr '+/' '-_' | tr -d '=')"
JWT_TOKEN="${SIGNING_INPUT}.${SIG_B64}"
```

Attempt login:

```bash
kubectl exec vault-0 -n vault -- vault write "auth/jwt-test/login" role="read-secrets" jwt="$JWT_TOKEN"
```

```text
Error writing data to auth/jwt-test/login: Error making API request.

URL: PUT http://127.0.0.1:8200/v1/auth/jwt-test/login
Code: 400. Errors:

* error validating claims: claim "namespace_path" does not match any associated bound claim values
command terminated with exit code 2
```
Observed result (expected for this step): login fails with a claim validation error because `Databases` is not an exact match for `databases/graphdb/aws`.

## Step 4: Switch to glob matching (fix)

Update the role:

```bash
vault write auth/jwt-test/role/read-secrets - <<EOF
{
  "role_type": "jwt",
  "user_claim": "user_email",
  "bound_audiences": ["https://code.test.com"],
  "bound_claims_type": "glob",
  "bound_claims": {
    "namespace_path": "databases/*"
  },
  "token_policies": ["read-secrets"]
}
EOF
```

Retry login with the same JWT:

```bash
kubectl exec vault-0 -n vault -- vault write "auth/jwt-test/login" role="read-secrets" jwt="$JWT_TOKEN"
```

Output:

```text
Key                  Value
---                  -----
token                <token>
token_accessor       mIaW5sl9998K4wNGd6c4UNSb
token_duration       768h
token_renewable      true
token_policies       ["default" "read-secrets"]
identity_policies    []
policies             ["default" "read-secrets"]
token_meta_role      read-secrets
```

Expected result: login succeeds and returns an auth token.

## Step 5: Validate case sensitivity quickly

Change the role to a capitalized path:

```bash
vault write auth/jwt-test/role/read-secrets - <<EOF
{
  "role_type": "jwt",
  "user_claim": "user_email",
  "bound_audiences": ["https://code.test.com"],
  "bound_claims_type": "glob",
  "bound_claims": {
    "namespace_path": "Databases/*"
  },
  "token_policies": ["read-secrets"]
}
EOF
```

Retry login:

```bash
kubectl exec vault-0 -n vault -- vault write "auth/jwt-test/login" role="read-secrets" jwt="$JWT_TOKEN"
```

Output:

```text
Error writing data to auth/jwt-test/login: Error making API request.

URL: PUT http://127.0.0.1:8200/v1/auth/jwt-test/login
Code: 400. Errors:

* error validating claims: claim "namespace_path" does not match any associated bound claim values
command terminated with exit code 2
```
Observed result: login fails again because matching is case-sensitive (`Databases/*` does not match `databases/graphdb/aws`).

## Troubleshooting: inspect the token claim directly

Decode payload locally:

```bash
echo "$JWT_TOKEN" | cut -d '.' -f 2 | base64 -d
```

Decode token from jwt.io
- Paste the JWT into https://jwt.io/ and verify the decoded payload matches the expected claim values, especially `namespace_path`.

## Cleanup

Delete role and policy:

```bash
vault delete "auth/jwt-test/role/read-secrets"
vault policy delete read-secrets
```

Disable the auth mount if this runbook used a dedicated temporary path:

```bash
vault auth disable jwt-test
```

Remove temp files:

```bash
kubectl exec vault-0 -n vault -- rm -f /tmp/jwt-public.pem /tmp/read-secrets.hcl
rm -f jwt-private.pem jwt-public.pem
```

## Conclusion

Use `bound_claims_type="glob"` when claim values represent hierarchical namespace paths and you need wildcard matching across subgroups or projects. Keep `bound_claims_type="string"` only when exact value equality is desired.
