# KB: Token Creation Nuances with Allowed Policies & Allowed Policies Glob

## Overview

This KB covers the `allowed_policies` and `allowed_policies_glob` parameters when creating Vault tokens via `auth/token/create/<role_name>`. It explains how these constraints interact, highlights common misconfigurations, and details why token creation errors occur when they are poorly formatted. 

This originates from a real support case where an enterprise customer faced downstream application failures due to a misunderstanding of Vault's policy constraints, and as a result this guide also demonstrates how to safely use glob patterns to manage large policy sets.

## Symptom

Token creation fails against a token role with an error similar to:

```bash
# 1) Create example policies
vault policy write net-gw-alpha-us-east-1-policy - <<'HCL'
path "sys/health" {
  capabilities = ["read"]
}
HCL

vault policy write platform-network-policy - <<'HCL'
path "sys/health" {
  capabilities = ["read"]
}
HCL

# 2) Create role that DOES NOT allow the alpha policy or the platform-network-policy
vault write auth/token/roles/gateway-role \
  allowed_policies="net-gw-bravo-us-east-1-policy,platform-firewall-policy,default"

# 3) Attempt token creation with a disallowed policy
vault write auth/token/create/gateway-role \
  policies="net-gw-alpha-us-east-1-policy,platform-network-policy"
```

```text
Code: 400. Errors:
* token policies (["net-gw-alpha-us-east-1-policy" "default" "platform-network-policy"]) must be subset of the role's allowed policies (...) or glob policies ([])
```

In upstream applications this is often wrapped as an internal error, but the root cause is the Vault role constraint check.

Expected result: Vault returns `Code: 400` because `net-gw-alpha-us-east-1-policy` is not allowed by the role.

## Auth Token Role Information

### 1) Policy not actually present in role allow-list

The requested policy must be allowed by at least one of:

- allowed_policies
- allowed_policies_glob

If neither matches, token creation is denied.

### 2) Incorrect list formatting for allowed_policies

A frequent issue is writing allowed_policies as a single space-separated string instead of a real list.

If this happens, Vault stores that long value as one list element, so subset checks fail even though names look visually present.

### 3) Regex is not supported

Regex is not supported for token role policy matching.

- allowed_policies requires explicit names
- allowed_policies_glob supports glob wildcards, not regex

## Quick Diagnosis

Read the role:

```bash
vault read auth/token/roles/gateway-role
```

Check these fields:

- allowed_policies
- allowed_policies_glob

If allowed_policies was written incorrectly, you will typically notice one very long element containing many policy names separated by spaces.

## Correct Configuration Patterns

### Option A: Explicit list with allowed_policies

Use comma-separated values in CLI shorthand:

```bash
vault write auth/token/roles/gateway-role \
  allowed_policies="net-gw-alpha-us-east-1-policy,platform-network-policy,default"
```

Or use JSON for safer automation:

```bash
vault write auth/token/roles/gateway-role \
  allowed_policies='["net-gw-alpha-us-east-1-policy","platform-network-policy","default"]'
```

### Option B: Pattern-based allow-list with allowed_policies_glob

Use glob patterns when many policy names share a prefix/suffix:

```bash
vault write auth/token/roles/gateway-role \
  allowed_policies_glob="net-gw-*-policy,platform-*-policy"
```

Notes:

- This is glob matching using wildcard characters like *.
- This is not regex. Patterns like [a-z0-9]+ are not supported.
- If both allowed_policies and allowed_policies_glob are set, a requested policy only needs to match one allow-list.

## Validation Steps

1. Read role config and confirm values were parsed as intended:

```bash
vault read auth/token/roles/gateway-role
```

2. Test token creation with representative policies:

```bash
vault write auth/token/create/gateway-role \
  policies="net-gw-alpha-us-east-1-policy,platform-network-policy"
```

3. Verify token policies in response include expected entries.

## Known Behavior and Gotchas

- Policy existing in Vault policy store does not automatically make it issuable by a token role.
- The role allow-list is an additional enforcement boundary.
- Using spaces instead of commas in CLI list shorthand can cause list fields to be stored as one string element.
- allowed_policies_glob patterns are for matching; they are not regex.
- **Default Policy Assignment:** If no policies are explicitly requested during token creation, Vault will automatically attach the baseline policies listed in `allowed_policies`. However, policies covered *only* by `allowed_policies_glob` will **not** be automatically added—they must be explicitly requested by the client.

## Recommended Practice

- For small, controlled sets: use explicit allowed_policies.
- For large naming-convention-driven sets: use allowed_policies_glob with strict prefixes.
- Keep default and baseline policies explicit in allowed_policies.

## References

- Vault Token Auth API: allowed_policies_glob
  - https://developer.hashicorp.com/vault/api-docs/auth/token#allowed_policies_glob