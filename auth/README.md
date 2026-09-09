# Auth

Vault auth methods: AWS, JWT, Kubernetes, LDAP, token, and userpass.

Lab prerequisites are in the [root README](../README.md). Confirmed version-specific defects are in [KNOWN_BUGS.md](../KNOWN_BUGS.md).

Legend: `runbook` = procedural, `kb` = break-fix analysis, `repro` = focused behavior demo, `guide` = broader walkthrough, `script` = executable is the primary deliverable.

## AWS

- [Terraform Provider AWS Auth in `1.10.11`](aws/terraform-provider-aws-auth-put-runbook.md)
  `runbook` `auth` `aws` `terraform`
  <details>
  <summary>Details</summary>

  - Reproduces the regression introduced in Vault Terraform Provider v5.7.0 where `auth_login` with `method = "aws"` sends a `PUT` to `auth/aws/login`, causing Vault to reject the request with a `400` error.
  - Documents the workaround (pin to v5.6.0) or upgrade vault to `1.15.x` and newer
   </details>

## Cloud Foundry

- [Global Plugin Reload Cleanup: OOM and Quorum Loss at Namespace Scale](cf/global-plugin-reload-cleanup-kb.md)
  `kb` `auth` `cf` `plugins` `raft`
  <details>
  <summary>Details</summary>

   - Root-cause analysis of how a supported `-scope=global` CF plugin reload, issued once per namespace, caused OOM and full quorum loss on a Vault Enterprise cluster with zero client traffic.
   - Documents the delayed-cleanup mechanism (per-request timers, a full-barrier scan, and un-pruned request records inherited by each new Raft leader) and the pre-fix/post-fix stress evidence.
  </details>

## <img src="https://cdn.simpleicons.org/jsonwebtokens" alt="JWT" width="18" /> JWT

- [JWT Authentication Setup and Login Script](jwt/jwt-authentication-setup-and-login.sh)
  `script` `auth` `jwt`
  <details>
  <summary>Details</summary>

  - Configures Vault JWT auth with a local RSA key pair and issuer binding.
  - Creates per-user JWT roles, signs demo JWTs, and validates login for each configured user.
  - Optionally creates and reads a KV v2 demo secret to confirm post-login policy access.
  </details>

- [JWT Bound Claims Glob Runbook](jwt/jwt-bound-claims-glob-runbook.md)
  `runbook` `auth` `jwt` `namespaces`
  <details>
  <summary>Details</summary>

  - Reproduces JWT claim validation failures for nested namespace paths when `bound_claims_type` uses exact string matching.
  - Demonstrates the fix with `bound_claims_type="glob"` and wildcard `namespace_path` patterns.
  - Includes case-sensitivity checks, token-claim decoding, and cleanup commands.
  </details>

## <img src="https://cdn.simpleicons.org/kubernetes" alt="Kubernetes" width="18" /> Kubernetes

- [Kubernetes Auth User Creation and Login Script](kubernetes/create-kubernetes-users-and-login.sh)
  `script` `auth` `kubernetes` `identity`
  <details>
  <summary>Details</summary>

  - Creates Kubernetes service accounts, configures Vault Kubernetes auth, and tests login flow.
  - Useful for evaluating how Vault creates and maps identities during Kubernetes auth.
  - Includes behavior validation related to entities and aliases.
  </details>

## <img src="https://icons.veryicon.com/png/o/business/cloud-desktop/personal-ldap.png" alt="OpenLDAP" width="18" /> LDAP

- [OpenLDAP LDAP Auth Reproduction](ldap/openldap-ldap-auth-repro.md)
  `repro` `auth` `ldap` `kubernetes`
  <details>
  <summary>Details</summary>

  - End-to-end OpenLDAP + Vault LDAP auth runbook with Docker-hosted LDAP and Kubernetes-hosted Vault.
  - Includes generation of 200 sample users, group mapping tests, and nested-group inheritance behavior checks.
  </details>

## <img src="https://cdn.simpleicons.org/vault" alt="Vault" width="18" /> Token

- [Token Role `allowed_policies` vs `allowed_policies_glob` KB](token/token-role-allowed-policies-glob-kb.md)
  `kb` `auth` `token` `policies`
  <details>
  <summary>Details</summary>

  - Covers token role failures where requested token policies are not a subset of `allowed_policies` or `allowed_policies_glob`.
  - Clarifies that token roles support glob patterns (not regex) and includes practical examples.
  </details>

- [Generate a New Root Token Using Unseal Keys Runbook](token/generate-root-token-from-unseal-keys-runbook.md)
  `runbook` `auth` `token` `recovery`
  <details>
  <summary>Details</summary>

  - Step-by-step runbook for generating a new Vault root token when the original has been lost, using existing Shamir unseal key shares.
  </details>

## <img src="https://cdn.simpleicons.org/vault" alt="Vault" width="18" /> Userpass

- [Userpass Entity Metadata Dynamic Policy Repro](userpass/userpass-entity-metadata-dynamic-policy-repro.md)
  `repro` `auth` `userpass` `identity`
  <details>
  <summary>Details</summary>

  - Local reproduction for dynamic policy templating using entity metadata.
  - Demonstrates immediate access changes on active tokens when entity metadata changes.
  </details>

- [Userpass Authentication Setup Script](userpass/userpass-authentication-setup.sh)
  `script` `auth` `userpass` `identity`
  <details>
  <summary>Details</summary>

  - Enables userpass auth, creates test users, and validates login/token behavior.
  - Useful for observing identity handling when many local auth users are created and used.
  - Includes behavior validation related to entities and aliases.
  </details>
