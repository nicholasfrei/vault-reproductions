# Vault KB: Sentinel EGP and RGP Governing Policies (Common Patterns)

## Problem Statement / Introduction

Sentinel extends Vault policy enforcement beyond ACL path capability checks. This KB covers two Sentinel policy types:

- Endpoint Governing Policy (`EGP`): rules applied to request paths/endpoints
- Role Governing Policy (`RGP`): rules applied based on caller identity/token context

In practice, operators use EGPs to gate what can happen on specific API paths (for example, role naming constraints or endpoint-level guardrails), and use RGPs to gate who can perform sensitive actions based on identity attributes (for example, entity metadata or group-driven controls).

This KB is based on recurring internal support patterns where Vault admins require dynamic policy logic beyond ACL path matching (for example: naming standards, namespace control, or identity-attribute-based decisions).

Common use cases:

- role/path governance standards are difficult to enforce with ACL policies alone
- policy denials are hard to triage when EGP and RGP scope/attachment are misunderstood

## Preconditions

- Vault Enterprise (or HCP Vault Dedicated) with Sentinel support
- operator token with permissions for:
  - `sys/policies/egp/*`
  - `sys/policies/rgp/*`
  - identity APIs used in this guide
- `vault`, `jq`, and `base64` available

## EGP vs RGP Comparison

- EGP:
  - attached to paths via `paths=...`
  - evaluated for matching request paths
  - best for endpoint/path governance controls
- RGP:
  - attached to token/identity policy context (for example via identity group policy membership)
  - evaluated based on caller identity/token attributes
  - can be used to enforce MFA or other security policies based on identity attributes
  - best for persona/role-based conditional controls

## Findings / Error Signatures / Diagnostics

Typical denial signatures:

```text
egp standard policy "<namespace>/<policy>.sentinel" evaluation resulted in denial
permission denied
```

```text
rgp standard policy "<namespace>/<policy>.sentinel" evaluation resulted in denial
permission denied
```

Quick diagnostic reads:

```bash
vault read sys/policies/egp/restrict-role-name
vault read sys/policies/rgp/rgp-admin-guard
vault token lookup
vault read -format=json identity/entity/id/<entity_id>
```

### Customer Case: JWT auth `max_lease_ttl` parse failure on `sys/auth/jwt/tune`

Below is a customer case where an EGP was configured on the `sys/auth/jwt/tune` endpoint to restrict `max_lease_ttl` values, but the policy logic did not handle hour-only inputs correctly, leading to a parsing error and request denial. I worked with this customer to identify the root cause, implement a temporary workaround, and provide recommendations for improving the EGP logic to handle this case defensively.

Customer request:

```bash
vault write -namespace=ns_cloud_security sys/auth/jwt/tune \
  max_lease_ttl="720h" \
  listing_visibility="unauth"
```

Error response:

```text
egp standard policy "root/restrict_ttls_of_auth_methods" evaluation resulted in denial
root/restrict_ttls_of_auth_methods:45:15: strconv.ParseInt: parsing "": invalid syntax
permission denied
```

Why this happened:

- the EGP logic splits `max_lease_ttl` by `h`, `m`, and `s`
- when value is `720h`, splitting on `h` yields `["720", ""]`
- the code path later tries to parse an empty string as an integer for seconds (`int("")`), which raises `strconv.ParseInt: parsing "": invalid syntax`

Incorrect line in the customer's EGP (reference):

```sentinel
seconds = int(strings.split(split_mlttl_by_minutes[0], "s")[0])
```

This line is unsafe in the `else` branch when `split_mlttl_by_minutes[0]` is empty after splitting an hour-only input such as `720h`.

Impact:

- request is denied even though `720h` (30 days) is below the 1-year threshold
- this was a policy parsing bug, not a TTL threshold violation

What I shared with the customer:

- provided a format that included minutes (or seconds), so parsing does not hit an empty token
- for one month, use `720h0m` (or `720h0m0s`)

Example:

```bash
vault write -namespace=ns_cloud_security sys/auth/jwt/tune \
  max_lease_ttl="720h0m" \
  listing_visibility="unauth"
```

If the auth method is being enabled (not tuned) and the same EGP applies, use the same duration format in auth enable configuration so the EGP parser receives a non-empty minutes/seconds segment.

Future cleanup / recommendation:

- keep the temporary workaround (`720h0m`) for immediate progress
- update the Sentinel policy logic to handle hour-only/minute-only inputs defensively so valid inputs like `720h` do not fail parsing

## Sample EGP and RGP policies with validation steps are included in the next section.

### 1) Create an EGP

Create policy file:

```bash
cat > restrict-role-name.sentinel <<'EOF'
import "strings"

main = rule {
  strings.has_prefix(strings.split(request.path, "/")[-1], "vault.ci-")
}
EOF
```

Register EGP (hard deny if rule fails):

```bash
EGP_POLICY=$(base64 -i restrict-role-name.sentinel)

vault write sys/policies/egp/restrict-role-name \
  policy="${EGP_POLICY}" \
  paths="auth/approle/role/*" \
  enforcement_level="hard-mandatory"
```

Validate policy registration:

```bash
vault read sys/policies/egp/restrict-role-name
```

### 2) Validate EGP behavior

Expected denial (name does not start with `vault.ci-`):

```bash
vault write auth/approle/role/appdev token_policies="default"
```

Expected success:

```bash
vault write auth/approle/role/vault.ci-dev-app1 token_policies="default"
```

### 3) Create an RGP

Create policy file:

```bash
cat > rgp-admin-guard.sentinel <<'EOF'
import "strings"

precond = rule {
  strings.has_prefix(request.path, "sys/policies/acl/admin")
}

main = rule when precond {
  identity.entity.metadata.role is "Team Lead"
}
EOF
```

Register RGP:

```bash
RGP_POLICY=$(base64 -i rgp-admin-guard.sentinel)

vault write sys/policies/rgp/rgp-admin-guard \
  policy="${RGP_POLICY}" \
  enforcement_level="hard-mandatory"
```

Read back policy:

```bash
vault read sys/policies/rgp/rgp-admin-guard
```

### 4) Attach RGP through identity group policy membership

Example (attach `rgp-admin-guard` policy to a group):

```bash
vault write identity/group name="sysops" \
  policies="default,rgp-admin-guard" \
  member_entity_ids="<entity_id_1>,<entity_id_2>"
```

Expected behavior:

- entity with `metadata.role=Team Lead` can perform guarded admin policy path action
- entity without required metadata is denied with RGP evaluation message

## Validation

Use this checklist:

1. EGP path scope is correct (`paths=...` matches target endpoint).
2. EGP denial occurs for non-compliant request path/name.
3. RGP is attached through effective policy context (token/group/entity path).
4. Identity metadata used by RGP exists on the caller entity.
5. `vault token lookup` and entity reads confirm expected identity linkage.

If behavior does not match expectation, first check:

- wrong mount/path in EGP `paths`
- RGP not actually attached to effective token policy set
- missing entity alias or metadata key mismatch (case-sensitive)

## Cleanup

```bash
vault delete sys/policies/egp/restrict-role-name
vault delete sys/policies/rgp/rgp-admin-guard
vault delete auth/approle/role/appdev
vault delete auth/approle/role/vault.ci-dev-app1
vault delete identity/group/name/sysops
rm -f restrict-role-name.sentinel rgp-admin-guard.sentinel
```

## References

- [Vault Sentinel tutorial (EGP + RGP)](https://developer.hashicorp.com/vault/tutorials/policies/sentinel)
- [Vault Sentinel docs](https://developer.hashicorp.com/vault/docs/enterprise/sentinel)
- [Vault sys/policies API docs](https://developer.hashicorp.com/vault/api-docs/system/policies)
- [EGP Generic Sentinel policy to restrict the role name](https://support.hashicorp.com/hc/en-us/articles/22584029418003-EGP-Generic-Sentinel-policy-to-restrict-the-role-name)
- [Managing Vault Namespace Manipulation Using Sentinel Policies](https://support.hashicorp.com/hc/en-us/articles/9016703678739-Managing-Vault-Namespace-Manipulation-Using-Sentinel-Policies)
- [How-to mock a Sentinel http import](https://support.hashicorp.com/hc/en-us/articles/25494868244755-How-to-mock-a-Sentinel-http-import)
