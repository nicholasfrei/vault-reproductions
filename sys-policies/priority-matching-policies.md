# Vault KB: Priority Matching in ACL Policies

## Problem Statement

Users often ask why a token can or cannot access a path when multiple ACL policy stanzas seem to match. This KB explains:

- how Vault chooses the winning policy path match
- when capabilities are unioned vs when they are not
- how to prove which policy is taking priority with repeatable CLI checks

## Key Behavior (Short Version)

Vault evaluates policy paths by specificity (priority matching).

- If the exact same path pattern appears in multiple attached policies, Vault unions capabilities from those identical patterns.
- If different path patterns match the same request path, Vault uses only the highest-priority (most-specific) matching pattern.

This is the source of most "why did this deny" reports.

## Priority Rules (How Vault Breaks Ties)

For two matching patterns `P1` and `P2`, `P1` is lower priority if:

1. The first wildcard (`+` or `*`) appears earlier in `P1`.
2. `P1` ends in `*` and `P2` does not.
3. `P1` has more `+` segments.
4. `P1` is shorter.
5. `P1` is lexicographically smaller.

Important notes:

- `*` in Vault ACL paths is a suffix glob, not regex.
- `*` is supported only as the final character in the policy path.
- `list` operations are prefix-oriented; policy path patterns for listing must reflect that.

## Quick Diagnostic Workflow

Use this to explain to customers exactly which policy effect they are observing.

1. List attached policies on the token.
2. Inspect all matching path stanzas across those policies.
3. Determine whether matches are identical patterns (union) or different patterns (single highest-priority winner).
4. Validate with `vault token capabilities`.

Commands:

```bash
vault token lookup
vault policy read <policy_name>
vault token capabilities <path>
```

For KV v2, evaluate the correct API path (`<mount>/data/...`, `<mount>/metadata/...`, etc.), not the human-friendly `kv get` shorthand.

## Example 1: Same Path Pattern in Multiple Policies (Capabilities Union)

Two policies both define the same path pattern:

```bash
cat > /tmp/app-read.hcl <<'EOF'
path "secret/data/apps/payments" {
    capabilities = ["read"]
}
EOF

cat > /tmp/app-patch.hcl <<'EOF'
path "secret/data/apps/payments" {
    capabilities = ["patch"]
}
EOF

vault policy write app-read /tmp/app-read.hcl
vault policy write app-patch /tmp/app-patch.hcl
```

Attach both to one token:

```bash
vault write auth/token/create policies="app-read" policies="app-patch"
```

Expected result:

- Effective capabilities on `secret/data/apps/payments` include both `read` and `patch`.

Verify:

```bash
vault token capabilities <token> secret/data/apps/payments
```

You should see both `read` and `patch` in the output, demonstrating that capabilities from identical path patterns are unioned.

## Example 2: Different Matching Patterns (Most Specific Wins)

Create and load both policies:

```bash
cat > /tmp/broad-read.hcl <<'EOF'
path "secret/data/apps/*" {
    capabilities = ["read"]
}
EOF

cat > /tmp/payments-deny.hcl <<'EOF'
path "secret/data/apps/payments" {
    capabilities = ["deny"]
}
EOF

vault policy write broad-read /tmp/broad-read.hcl
vault policy write payments-deny /tmp/payments-deny.hcl
```

Create token with both policies:

```bash
vault write auth/token/create policies="broad-read" policies="payments-deny"
```

Both patterns match `secret/data/apps/payments`, but they are different patterns.

Expected result:

- `secret/data/apps/payments` is denied, because the exact path match is higher priority than the glob.
- The broader `read` on `secret/data/apps/*` does not union with the exact-path stanza in this case.

Verify:

```bash
vault token capabilities <token> secret/data/apps/payments
```

You should see `deny` in the output, confirming that the more specific pattern took priority and blocked access.

```bash
vault token capabilities <token> secret/data/apps/test
```

This shows that the same token can read `secret/data/apps/test` (matching the broader pattern) but is denied on `secret/data/apps/payments` due to the more specific deny pattern.

## Example 3: Why a "More Detailed Looking" Pattern Can Still Lose

Compare:

- `secret/*`
- `secret/+/+/foo/*`

According to the priority rules, having more `+` segments lowers the priority. Therefore, `secret/+/+/foo/*` is actually **lower priority** than `secret/*`, even though it looks more specific and detailed.

Create and load both policies:

```bash
cat > /tmp/high-priority.hcl <<'EOF'
path "secret/*" {
    capabilities = ["read"]
}
EOF

cat > /tmp/low-priority.hcl <<'EOF'
path "secret/+/+/foo/*" {
    capabilities = ["deny"]
}
EOF

vault policy write high-priority /tmp/high-priority.hcl
vault policy write low-priority /tmp/low-priority.hcl
```

Create token with both policies:

```bash
vault write auth/token/create policies="high-priority" policies="low-priority"
```

Verify:

```bash
# Evaluate a request path that fits both policy patterns:
vault token capabilities <token> secret/app1/dev/foo/bar
```

You will see `read`. The `deny` capability in the `+/+` pattern is ignored because `secret/*` has fewer wildcard segments and thus takes precedence, regardless of visual complexity.

## Example 4: Namespace-Aware Path Expansion

**Scenario:**
You are operating with nested namespaces `ns1/ns2/ns3`.
- A policy in the `ns1/ns2/ns3` namespace grants `read` to: `secret/*`
- A policy in the `root` namespace issues a `deny` to: `ns1/ns2/ns3/secret/apps/*`

**How Vault Evaluates This:**
When dealing with namespaces, Vault resolves all paths to their effective absolute paths before applying priority rules. Internally, Vault expands the namespace-level `secret/*` policy to its absolute equivalent: `ns1/ns2/ns3/secret/*`.

If these policies interact (for example, through Sentinel EGPs or complex identity group combinations), Vault measures the fully resolved paths against each other. Because the first wildcard appears earlier in `ns1/ns2/ns3/secret/*` than it does in `ns1/ns2/ns3/secret/apps/*`, Vault considers the namespace policy to be **lower priority** (Rule 1). Thus, the root `deny` policy takes precedence.

**Simulating the Evaluation:**
To prove how Vault evaluates these resolved paths without needing complex cross-namespace identity setups, we can simulate the expanded paths directly in the root namespace:

```bash
# Root policy (absolute path containing the deny)
cat > /tmp/root-ns.hcl <<'EOF'
path "ns1/ns2/ns3/secret/apps/*" {
    capabilities = ["deny"]
}
EOF

# Namespace policy (simulating the internally expanded relative path)
cat > /tmp/local-ns-expanded.hcl <<'EOF'
path "ns1/ns2/ns3/secret/*" {
    capabilities = ["read"]
}
EOF

vault policy write root-ns /tmp/root-ns.hcl
vault policy write local-ns-expanded /tmp/local-ns-expanded.hcl
```

Create token with both simulated policies:

```bash
vault write auth/token/create policies="root-ns" policies="local-ns-expanded" 
```

Evaluate capabilities:

```bash
vault token capabilities <token> ns1/ns2/ns3/secret/apps/test
```

You will see `deny` because the fully resolved path `ns1/ns2/ns3/secret/apps/*` is more specific than `ns1/ns2/ns3/secret/*`.

## Common Pitfalls That Trigger Support Cases

- Assuming all matching stanzas union regardless of pattern differences.
- Forgetting that `deny` on a higher-priority matching pattern blocks access.
- Checking KV v2 paths incorrectly (for example `secret/foo` vs `secret/data/foo`).
- Using non-prefix path patterns while validating `list` capability.
- Treating `*` as a general regex wildcard.
- Thinking `+` is a wildcard instead of a segment wildcard that represents one folder path. 

## References

- [Vault Docs - Policies & Priority Matching](https://developer.hashicorp.com/vault/docs/concepts/policies#priority-matching)