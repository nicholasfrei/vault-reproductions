# Vault Reproductions

This repository is a vault (wink) of various scenarios I've worked with during my time as a Senior Support Engineer. The goal with this project is to share various scripts, guides, and reproductions for different Vault plugins. Some of these are based on real support cases or incidents, while others are smaller scripts to assist with learning Vault. 

I hope you find this repository helpful in your journey with Vault. 

<img src="./images/vault-primary-logo.png" alt="Vault Primary Logo" width="400"/>

----

## Start Here

If you are new to this repo, use this quick path:

1. Pick a category from [Scenario Index](#scenario-index) based on the issue type (`auth/`, `secrets/`, `kubernetes/`, `sys/`, `sys/seal/`, `sys/replication/`, etc.).
2. Open the linked runbook/KB and complete the preconditions listed in that file before running commands.
3. Follow the validation and cleanup steps so your lab stays reproducible between runs.

Helpful Vault external links:

- [Vault Official Documentation](https://developer.hashicorp.com/vault/docs)
- [Vault Tutorials](https://developer.hashicorp.com/vault/tutorials)
- [Vault Certification Exams](https://developer.hashicorp.com/certifications/security-automation)
- [Documentation source](https://github.com/hashicorp/web-unified-docs)
- [Vault OSS Repository](https://github.com/hashicorp/vault)
- [Vault Enterprise Repository](https://github.com/hashicorp/vault-enterprise)

----

## Prerequisites

Most scenarios use this baseline local lab setup:

- `kubectl`, `helm`, `minikube`
- Docker (`Docker Desktop` or Docker Engine)
- `jq`

Common optional tools (scenario-dependent):

- `gpg`
- `unzip` and `wget`/`curl`
- `ldapsearch` and `nc`
- `psql`
- `sqlplus`

----

## Project Structure

```text
vault-reproductions/
├── auth/ 
├── certification/
├── images/
├── kubernetes/
│   ├── vault-csi-provider/
│   └── vso/
├── linux/
│   ├── logrotate/
├── secrets/
├── setup/
├── sys/
│   ├── audit/
│   ├── health/
│   ├── policies/
│   ├── raw/
│   ├── replication/
│   ├── rotate/
│   └── seal/
├── telemetry/
└── vault-mcp-server/
```

----

## Scenario Index

Legend: `runbook` = procedural, `kb` = break-fix analysis, `repro` = focused behavior demo, `guide` = broader walkthrough.

### AI Tools

#### IBM Bob

- [IBM Bob Getting Started Guide](ai-tools/00-ibm-bob-getting-started.md)
  `guide` `ai-tools` `bob`
  <details>
  <summary>Details</summary>

  - Learning-path overview for new IBM Bob users, with links to the first three recommended guides.
  - Covers installation, project instructions, and skills as a progressive onboarding flow.
  </details>

- [IBM Bob Guide #1 - Install Bob, Bobshell, and Open Your First Repository](ai-tools/01-install-ibm-bob-guide.md)
  `guide` `ai-tools` `bob`
  <details>
  <summary>Details</summary>

  - Step-by-step setup guide for downloading Bob, installing bobshell, opening a repository, and reviewing usage analytics.
  - Includes references for Bob IDE quickstart, Bob Shell docs, and Bob token guidance.
  </details>

- [IBM Bob Guide #2 - Create AGENTS.md and Project Rules](ai-tools/02-create-agents-guide.md)
  `guide` `ai-tools` `bob`
  <details>
  <summary>Details</summary>

  - Beginner guide for creating a repo-level `AGENTS.md` file and teaching Bob how to work in a project.
  - Covers starter examples, project-specific rules, `/init`, and mode-specific instruction files.
  </details>

- [IBM Bob Guide #3 - Skills and Templates Guide](ai-tools/03-create-skills-guide.md)
  `guide` `ai-tools` `bob`
  <details>
  <summary>Details</summary>

  - Beginner-friendly guide for understanding Bob skills, including layout, minimum file format, and sample templates.
  - Serves as Guide #3 in the Bob learning path after installation and project instruction setup.
  </details>

### Auth

#### <img src="https://cdn.simpleicons.org/jsonwebtokens" alt="JWT" width="18" /> JWT

- [JWT Authentication Setup and Login Script](auth/jwt/jwt-authentication-setup-and-login.sh)
  `script` `auth` `jwt`
  <details>
  <summary>Details</summary>

  - Configures Vault JWT auth with a local RSA key pair and issuer binding.
  - Creates per-user JWT roles, signs demo JWTs, and validates login for each configured user.
  - Optionally creates and reads a KV v2 demo secret to confirm post-login policy access.
  </details>

- [JWT Bound Claims Glob Runbook](auth/jwt/jwt-bound-claims-glob-runbook.md)
  `runbook` `auth` `jwt` `namespaces`
  <details>
  <summary>Details</summary>

  - Reproduces JWT claim validation failures for nested namespace paths when `bound_claims_type` uses exact string matching.
  - Demonstrates the fix with `bound_claims_type="glob"` and wildcard `namespace_path` patterns.
  - Includes case-sensitivity checks, token-claim decoding, and cleanup commands.
  </details>

#### <img src="https://cdn.simpleicons.org/kubernetes" alt="Kubernetes" width="18" /> Kubernetes

- [Kubernetes Auth User Creation and Login Script](auth/kubernetes/create-kubernetes-users-and-login.sh)
  `script` `auth` `kubernetes` `identity`
  <details>
  <summary>Details</summary>

  - Creates Kubernetes service accounts, configures Vault Kubernetes auth, and tests login flow.
  - Useful for evaluating how Vault creates and maps identities during Kubernetes auth.
  - Includes behavior validation related to entities and aliases.
  </details>

#### <img src="https://icons.veryicon.com/png/o/business/cloud-desktop/personal-ldap.png" alt="OpenLDAP" width="18" /> LDAP

- [OpenLDAP LDAP Auth Reproduction](auth/ldap/openldap-ldap-auth-repro.md)
  `repro` `auth` `ldap` `kubernetes`
  <details>
  <summary>Details</summary>

  - End-to-end OpenLDAP + Vault LDAP auth runbook with Docker-hosted LDAP and Kubernetes-hosted Vault.
  - Includes generation of 200 sample users, group mapping tests, and nested-group inheritance behavior checks.
  </details>

#### <img src="https://cdn.simpleicons.org/vault" alt="Vault" width="18" /> Token

- [Token Role `allowed_policies` vs `allowed_policies_glob` KB](auth/token/token-role-allowed-policies-glob-kb.md)
  `kb` `auth` `token` `policies`
  <details>
  <summary>Details</summary>

  - Covers token role failures where requested token policies are not a subset of `allowed_policies` or `allowed_policies_glob`.
  - Clarifies that token roles support glob patterns (not regex) and includes practical examples.
  </details>

- [Generate a New Root Token Using Unseal Keys Runbook](auth/token/generate-root-token-from-unseal-keys-runbook.md)
  `runbook` `auth` `token` `recovery`
  <details>
  <summary>Details</summary>

  - Step-by-step runbook for generating a new Vault root token when the original has been lost, using existing Shamir unseal key shares.
  </details>

#### <img src="https://cdn.simpleicons.org/vault" alt="Vault" width="18" /> Userpass

- [Userpass Entity Metadata Dynamic Policy Repro](auth/userpass/userpass-entity-metadata-dynamic-policy-repro.md)
  `repro` `auth` `userpass` `identity`
  <details>
  <summary>Details</summary>

  - Local reproduction for dynamic policy templating using entity metadata.
  - Demonstrates immediate access changes on active tokens when entity metadata changes.
  </details>

- [Userpass Authentication Setup Script](auth/userpass/userpass-authentication-setup.sh)
  `script` `auth` `userpass` `identity`
  <details>
  <summary>Details</summary>

  - Enables userpass auth, creates test users, and validates login/token behavior.
  - Useful for observing identity handling when many local auth users are created and used.
  - Includes behavior validation related to entities and aliases.
  </details>

### Certification

#### Vault Associate Cert

- [Vault Associate Exam Guide](certification/vault-associate-cert/vault-associate-exam-guide.md)
  `guide` `certification` `associate`
  <details>
  <summary>Details</summary>

  - Guide covering the Vault Associate Exam: format, rubric, and external resources.
  </details>

#### Vault Professional Cert

- [Vault Professional Exam Guide](certification/vault-professional-cert/vault-professional-exam-guide.md)
  `guide` `certification` `professional`
  <details>
  <summary>Details</summary>

  - Guide covering the Vault Professional Exam: format, rubric, and lab scenarios.
  </details>

- [Lab 1: Transit Auto-Unseal and Node Join](certification/vault-professional-cert/lab-01-transit-auto-unseal-and-node-join.md)
  `runbook` `certification` `professional`
  <details>
  <summary>Details</summary>

  - Hands-on runbook for configuring a transit-backed auto-unseal flow and joining a node to a cluster.
  </details>

- [Lab 2: AppRole + response wrapping + database secrets engine](certification/vault-professional-cert/lab-02-approle-wrapping-and-postgresql.md)
  `runbook` `certification` `professional`
  <details>
  <summary>Details</summary>

  - Hands-on runbook for AppRole login with wrapped `secret_id`, JSON output capture, and PostgreSQL dynamic credentials validation.
  </details>

- [Lab 3: Vault Agent + AppRole auto-auth + templating](certification/vault-professional-cert/lab-03-vault-agent-approle-templating.md)
  `runbook` `certification` `professional`
  <details>
  <summary>Details</summary>

  - Hands-on runbook for configuring Vault Agent with AppRole auto-auth, validating `secret_id` retention, and rendering a template with dynamic KV v2 secrets.
  </details>

- [Lab 4: Performance replication with path filtering](certification/vault-professional-cert/lab-04-pr-replication-path-filtering.md)
  `runbook` `certification` `professional`
  <details>
  <summary>Details</summary>

  - Practical PR setup and verification flow focused on primary/secondary behavior and path filter validation.
  </details>

- [Lab 5: Policies, namespaces, and KV v2 operations](certification/vault-professional-cert/lab-05-policy-kvv2-namespaces.md)
  `runbook` `certification` `professional`
  <details>
  <summary>Details</summary>

  - Traditional runbook to practice namespace-aware login context, policy inheritance boundaries, and KV v2 path precision tests.
  </details>

### Kubernetes

- [Liveness Probe KB](kubernetes/liveness-probe-kb.md)
  `kb` `kubernetes` `probes`
  <details>
  <summary>Details</summary>

  - Demonstrates automatic Vault pod recovery when TLS certificates expire, using Kubernetes liveness probes.
  </details>

- [Vault Raft Quorum Break and Restore Runbook](kubernetes/vault-raft-quorum-break-and-restore-runbook.md)
  `runbook` `kubernetes` `raft`
  <details>
  <summary>Details</summary>

  - Reproduces quorum-loss by scaling a Vault StatefulSet down to one pod, then restores service with single-node raft peer recovery and scale-out validation.
  </details>

#### <img src="https://cdn.simpleicons.org/kubernetes" alt="Kubernetes" width="18" /> Vault CSI Provider

- [Vault CSI Provider TLS CA Bundle Runbook](kubernetes/vault-csi-provider/vault-csi-provider-tls-ca-bundle-runbook.md)
  `runbook` `kubernetes` `csi`
  <details>
  <summary>Details</summary>

  - Reproduces and fixes CSI login failures caused by an untrusted Vault TLS issuer.
  - Shows how to mount the CA bundle into both the CSI provider and the Vault Agent sidecar, then align `SecretProviderClass` with `vaultCACertPath`.
  </details>

#### <img src="https://cdn.simpleicons.org/kubernetes" alt="Kubernetes" width="18" /> VSO K8s Auth Static Dynamic

- [VSO Kubernetes Auth Static and Dynamic Repro](kubernetes/vso-k8s-auth-static-dynamic/vso-k8s-auth-static-dynamic-repro.md)
  `repro` `kubernetes` `vso`
  <details>
  <summary>Details</summary>

  - Reproduces Vault Secrets Operator sync flows for static KV v2 secrets and dynamic database credentials using Vault Kubernetes authentication.
  - Includes policy and role setup, secret rotation verification, and failure injection by breaking/restoring Kubernetes auth role bindings.
  </details>

- [VSO Special Character Secret Keys KB](kubernetes/vso-special-character-secret-keys-kb.md)
  `kb` `kubernetes` `vso`
  <details>
  <summary>Details</summary>

  - Documents VSO sync failures when KV keys include Kubernetes-invalid characters such as `@`.
  - Includes a runnable repro, expected vs observed behavior, and workaround/architecture guidance.
  </details>

- [VSO AKS UDP DNS Race KB](kubernetes/vso-aks-udp-dns-race-kb.md)
  `kb` `kubernetes` `vso`
  <details>
  <summary>Details</summary>

  - Documents intermittent VSO DNS timeout failures in AKS (`read udp ... :53: i/o timeout`) after initial successful reconciles. This was a customer incident where all application pods lost connectivity to Vault after a certain period of time, and the root cause was traced back to VSO DNS timeouts due to AKS UDP conntrack behavior.
  - Covers UDP conntrack race hypothesis, validation commands, and mitigations (LocalDNS and/or shorter refresh intervals).
  </details>

### Linux

- [Vault Logrotate KB](linux/vault-logrotate-kb.md)
  `kb` `linux` `logrotate`
  <details>
  <summary>Details</summary>

  - Practical Linux/systemd-focused guidance for Vault logrotate configuration and troubleshooting.
  - Includes directive-by-directive explanations, safer rotation recommendations, and validation steps.
  </details>

### Secrets

#### <img src="https://cdn.simpleicons.org/jfrog" alt="JFrog" width="18" /> Artifactory

- [Artifactory Plugin Registration Script](secrets/artifactory/artifactory-plugin-registration.sh)
  `script` `secrets` `artifactory`
  <details>
  <summary>Details</summary>

  - Amazon Linux setup script for Vault Enterprise + JFrog Artifactory secrets plugin registration.
  - Includes plugin checksum validation and flattened plugin directory layout to avoid execution path errors.
  </details>

#### <img src="https://icons.veryicon.com/png/o/application/awesome-common-free-open-source-icon/aws-12.png" alt="AWS" width="18" /> AWS

- [AWS Secrets Engine Upgrade Findings KB](secrets/aws/aws-secrets-engine-upgrade-findings-kb.md)
  `kb` `secrets` `aws`
  <details>
  <summary>Details</summary>

  - Discusses real-life errors faced by enterprise customers found in v1.19.x for `sts_endpoint`, `iam_endpoint`, and rotation schedule/window(s).
  </details>

#### Database

- [Oracle Database Secrets Engine Repro](secrets/database/oracle-db/oracle-database-secrets-engine-repro.md)
  `repro` `secrets` `database`
  <details>
  <summary>Details</summary>

  - Rapid Oracle environment setup for testing Vault database plugin behavior with dynamic and static credentials.
  </details>

- [PostgreSQL Database Secrets Engine Repro](secrets/database/postgresql-db/postgresql-database-secrets-engine-repro.md)
  `repro` `secrets` `database`
  <details>
  <summary>Details</summary>

  - PostgreSQL + Vault database secrets engine setup covering dynamic credentials, static role rotation, and custom password policies.
  - Useful for validating credential lifecycle, lease revocation, and rotation timing behavior.
  </details>

- [PostgreSQL Static Role Denial of Service Repro](secrets/database/postgresql-db/postgresql-static-role-denial-of-service-repro.md)
  `repro` `secrets` `database`
  <details>
  <summary>Details</summary>

  - Reproduces static role rotation pressure when the backing PostgreSQL target is unavailable or decommissioned.
  - Useful for incident response drills and understanding cleanup/recovery patterns for stale static roles.
  </details>

- [RabbitMQ Secrets Engine Repro](secrets/database/rabbitmq-db/rabbitmq-secrets-engine-repro.md)
  `repro` `secrets` `database`
  <details>
  <summary>Details</summary>

  - Simple RabbitMQ + Vault secrets engine runbook for dynamic credential issuance and lease revocation validation.
  - Assumes an already-operational Vault cluster in Kubernetes and uses a local RabbitMQ container for testing.
  </details>

- [AppRole + Snowflake Database Secrets Engine Runbook](secrets/database/snowflake-db/approle-snowflake-db-runbook.md)
  `runbook` `secrets` `database`
  <details>
  <summary>Details</summary>

  - End-to-end setup for Vault database secrets engine with Snowflake using RSA key-pair authentication and static role rotation.
  - Covers Snowflake service account creation, AppRole auth configuration, credential rotation verification, and optional SnowSQL connection validation.
  </details>

#### <img src="https://cdn.simpleicons.org/vault" alt="Vault" width="18" /> KV

- [KV v1 Secret Recovery Runbook](secrets/kv/kv-v1-secret-recovery-runbook.md)
  `runbook` `secrets` `kv`
  <details>
  <summary>Details</summary>

  - Step-by-step reproduction for Vault Enterprise secret recovery using a loaded Raft snapshot.
  - Covers secret deletion/overwrite simulation, snapshot load status checks, `vault recover`, and cleanup.
  </details>

- [KV v2 Soft-Delete, Destroy, Undelete, and Recovery Runbook](secrets/kv/kv-v2-soft-delete-destroy-undelete-recovery-runbook.md)
  `runbook` `secrets` `kv`
  <details>
  <summary>Details</summary>

  - Step-by-step lifecycle validation for KV v2 versioned secrets.
  - Covers soft-delete, undelete, permanent destroy behavior, optional metadata delete, and cleanup.
  </details>

- [KV Path Migration Runbook (Same Mount)](secrets/kv/kv-path-migration-runbook.md)
  `runbook` `secrets` `kv`
  <details>
  <summary>Details</summary>

  - Instructions on how to copy a folder subtree and all secrets to a new path within the same KV mount.
  - Includes a recursive script, dry-run mode, validation checks, and cleanup guidance.
  - Clarifies when to use replication/snapshots versus manual copy and notes metadata/version-history limitations.
  </details>

#### <img src="https://icons.veryicon.com/png/o/business/cloud-desktop/personal-ldap.png" alt="OpenLDAP" width="18" /> LDAP

- [LDAP Secrets Engine Setup Repro](secrets/ldap/setup-ldap-secrets-engine-repro.md)
  `repro` `secrets` `ldap`
  <details>
  <summary>Details</summary>

  - OpenLDAP + Vault LDAP secrets engine setup focused on bind account and static-role password rotation timing.
  - Uses [secrets/ldap/openldap-deployment.yaml](secrets/ldap/openldap-deployment.yaml) as the backing Kubernetes manifest.
  </details>

- [LDAP UI Capabilities Self Bug Repro](secrets/ldap/ldap-ui-capabilities-self-bug.md)
  `repro` `secrets` `ldap`
  <details>
  <summary>Details</summary>

  - Reproduces a Vault UI regression where the LDAP library set `check-out` action is visible in `1.20.4`, missing in `1.20.7` through `1.20.10` and `1.21.5`, and restored in `2.0.0`.
  - Includes OpenLDAP container setup, scoped policy creation, UI navigation steps, and version-specific screenshots.
  </details>

- [RHDS + Vault LDAP Secrets Engine Reproduction](secrets/ldap/red-hat-directory-server/rhds-ldap-integration-repro.md)
  `repro` `secrets` `ldap`
  <details>
  <summary>Details</summary>

  - End-to-end reproduction using 389 Directory Server (open source RHDS equivalent) with the Vault LDAP secrets engine on Vault 1.16.7.
  - Covers static-role creation for 10 pre-existing LDAP users, automatic and manual `rotate-role` validation, and `rotate-root` bind-account rotation.
  </details>

#### <img src="https://cdn.simpleicons.org/letsencrypt" alt="PKI" width="18" /> PKI

- [CMPv2 PKI Integration Guide](secrets/pki/cmpv2/cmpv2-pki-integration-guide.md)
  `guide` `secrets` `pki`
  <details>
  <summary>Details</summary>

  - Markdown-only runbook for Vault PKI CMPv2 integration and proxy behavior validation.
  - Includes concrete expected output blocks from a successful direct + proxied CMP IR repro.
  </details>

- [Vault Proxy TLS Behavior Repro](secrets/pki/cmpv2/vault-proxy-tls-behavior-repro.md)
  `repro` `secrets` `pki`
  <details>
  <summary>Details</summary>

  - Reproduces HTTP client traffic into a local proxy with TLS-only Vault upstream.
  - Validates that Vault can stay TLS-only while a front proxy handles plaintext listener and HTTPS re-encryption.
  </details>

#### TOTP

- [TOTP Secrets Engine Repro](secrets/totp/totp-secrets-engine-repro.md)
  `repro` `secrets` `totp`
  <details>
  <summary>Details</summary>

  - Reproduction runbook for the Vault TOTP secrets engine, including setup and validation flow.
  </details>

### Setup

- [Vault Cluster Init Script](setup/init.sh)
  `script` `setup` `cluster`
  <details>
  <summary>Details</summary>

  - Installs Vault via Helm (HA + Raft, 3 pods), initializes with 5 total key shares and threshold 3, saves init output to `setup/init.json`, unseals all nodes, and logs into `vault-0` with the root token.
  </details>

- [Vault PGP Key Setup Script](setup/setup-pgp-keys-for-vault.sh)
  `script` `setup` `pgp`
  <details>
  <summary>Details</summary>

  - Generates PGP key pairs, copies public keys into the Vault pod, and runs `vault operator init` with PGP-encrypted unseal keys. Targets `vault-0` in namespace `vault` (configurable).
  </details>

- [Vault Sandbox Cleanup Script](setup/cleanup.sh)
  `script` `setup` `cleanup`
  <details>
  <summary>Details</summary>

  - Cleans up sandbox state between runs: uninstalls the Vault Helm release, deletes the `vault` namespace, deletes the Minikube `vault` profile, and removes `setup/init.json`.
  </details>

### System Backend (sys/)

#### Audit

- [Vault Audit Log JQ Queries KB](sys/audit/vault-audit-jq-queries-kb.md)
  `kb` `sys` `audit`
  <details>
  <summary>Details</summary>

  - Practical `jq` query cookbook for Vault audit logs to identify hot namespaces, busy paths, root usage, failing auth flows, and noisy clients.
  </details>

#### Health

- [sys/health Best Practices KB](sys/health/sys-health-best-practices-kb.md)
  `kb` `sys` `health`
  <details>
  <summary>Details</summary>

  - Covers how `sys/health` status codes and query parameters work, including `standbycode`, `performancestandbycode`, `drsecondarycode`, and the boolean `standbyok`/`perfstandbyok` flags.
  </details>

- [Consul Health Check Misconfiguration with `sys/health`](sys/health/consul-health-check-misconfiguration-kb.md)
  `kb` `sys` `health` `consul` `replication`
  <details>
  <summary>Details</summary>

  - Documents a production incident where `standbycode=503` in a static Consul health check removed all performance standbys from the load balancer pool during an election, concentrating ~7× baseline traffic onto the new active node.
  - Covers the lease restoration gate that blocked standbys from re-promoting to performance standby, the resulting audit sink timeout cascade (`event not processed by enough sink nodes`), and how the two factors extended the outage beyond a normal election window.
  </details>

- [AWS Auto Scaling Runbook for Vault `sys/health`](sys/health/aws-asg-sys-health-runbook.md)
  `runbook` `sys` `health`
  <details>
  <summary>Details</summary>

  - Step-by-step AWS CLI runbook to create an ALB target group and Auto Scaling Group using Vault `sys/health` endpoint checks for automated unhealthy-instance replacement.
  </details>

#### Policies

- [Sentinel EGP and RGP Governing Policies KB](sys/policies/sentinel-egp-rgp-governing-policies-kb.md)
  `kb` `sys` `policies`
  <details>
  <summary>Details</summary>

  - Break-fix KB for understanding and validating Sentinel Endpoint Governing Policies (EGP) and Role Governing Policies (RGP).
  - Includes practical policy examples, denial signatures, and validation/cleanup commands.
  </details>

- [Priority Matching in ACL Policies KB](sys/policies/priority-matching-policies-kb.md)
  `kb` `sys` `policies`
  <details>
  <summary>Details</summary>

  - Actionable KB explaining how Vault determines the winning path when multiple policies match a request.
  - Covers capability union vs. exact-match priority rules, namespace expansion, and common wild-card pitfalls.
  </details>

#### Raw

- [Vault sys/raw Endpoint KB](sys/raw/sys-raw-kb.md)
  `kb` `sys` `raw`
  <details>
  <summary>Details</summary>

  - KB for working with Vault's raw storage endpoint safely and understanding when it is appropriate to use it.
  - Includes background on `raw_storage_endpoint`, example raw reads, and cautions about bypassing normal validation.
  </details>

- [Vault sys/raw Inspector Script](sys/raw/sys-raw-inspector.sh)
  `script` `sys` `raw`
  <details>
  <summary>Details</summary>

  - Bash utility for walking logical/auth storage under `/sys/raw` and exporting an ASCII tree.
  - Includes recursive search mode for locating UUIDs or other strings inside raw storage responses without using Python.
  </details>

#### Replication

- [Vault Enterprise Replication Runbook (PR + DR)](sys/replication/vault-enterprise-replication-pr-dr-runbook.md)
  `runbook` `sys` `replication`
  <details>
  <summary>Details</summary>

  - Troubleshooting guide for already-configured Performance Replication and Disaster Recovery replication clusters.
  - Covers merkle sync/diff issues, failover/failback commands, and merkle corruption remediations.
  </details>

- [Merkle Corruption Reindex KB](sys/replication/vault-replication-merkle-corruption-reindex-kb.md)
  `kb` `sys` `replication`
  <details>
  <summary>Details</summary>

  - KB for resolving PR/DR replication stuck in `merkle-diff`/`merkle-sync` due to corrupted primary merkle trees.
  - Covers primary-first reindex strategy, write-lock expectations, validation checkpoints, and rollback cautions.
  </details>

- [Logshipper Buffer vs. `trailing_logs` — Replication vs. HA Lag KB](sys/replication/logshipper-vs-trailing-logs-kb.md)
  `kb` `sys` `replication` `raft` `enterprise`
  <details>
  <summary>Details</summary>

  - Explains the architectural distinction between `trailing_logs` (intracluster Raft HA) and `logshipper_buffer_length` (intercluster Enterprise replication WAL shipping).
  - Covers failure modes, lag diagnosis via `sys/replication/status`, and tuning recommendations for both parameters.
  </details>

#### Raft

- [Performance Secondary Raft Snapshot Loop — High Lease Volume KB](sys/raft/raft-snapshot-loop-high-lease-volume-kb.md)
  `kb` `sys` `raft` `enterprise`
  <details>
  <summary>Details</summary>

  - Documents a real incident where a follower node on a performance secondary cluster entered a permanent Raft snapshot loop due to extreme memory pressure and 6M+ active leases.
  - Covers triage path (ruling out intercluster replication, confirming intracluster Raft lag), why a clean node rejoin did not break the loop, and the role of `trailing_logs` tuning as a preventive measure.
  - Includes observed metrics: 40 GB `vault.db`, 1.5-hour snapshot cycles, 175k index lag, and sustained 90%+ RAM utilization with 10+ GB swap.
  </details>

#### Rotate

- [Vault Encryption Key Rotation + Rekey Runbook](sys/rotate/vault-encryption-key-rotation-and-rekey-runbook.md)
  `runbook` `sys` `rotate`
  <details>
  <summary>Details</summary>

  - Step-by-step runbook for rotating the Vault encryption key term (`sys/rotate`) and rekeying Shamir unseal shares (`vault operator rekey`).
  - Includes least-privilege policy example, command syntax gotchas, and post-change validation checks.
  </details>

#### Seal

##### AWSKMS

- [AWS KMS Auto-Unseal Runbook (EC2 + Vault Enterprise)](sys/seal/awskms/awskms-auto-unseal-runbook.md)
  `runbook` `sys` `seal`
  <details>
  <summary>Details</summary>

  - Single-node EC2 (Amazon Linux 2023) setup for Vault Enterprise with `awskms` seal and `raft` storage.
  - Includes license setup, systemd service configuration, restart validation, and cleanup guidance.
  </details>

##### Azure

- [Azure Key Vault Auto-Unseal Runbook (Linux VM + Vault Enterprise)](sys/seal/azure/azurekeyvault-auto-unseal-runbook.md)
  `runbook` `sys` `seal`
  <details>
  <summary>Details</summary>

  - Single-node Azure Ubuntu 22.04 VM setup for Vault Enterprise with `azurekeyvault` seal and `raft` storage.
  - Covers App Registration creation, client secret generation, Key Vault Crypto User role assignment, and seal stanza configuration.
  </details>

- [Azure Key Vault Auto-Unseal: US Gov Cloud Bug (`go-kms-wrapping` ≤ v2.0.14)](sys/seal/azure/azurekeyvault-auto-unseal-gov-cloud.md)
  `kb` `sys` `seal`
  <details>
  <summary>Details</summary>

  - Bug in `go-kms-wrapping` where the Azure AD authentication endpoint is hard-coded to public cloud, causing Vault startup failures for US Government Cloud tenants. Filed as [VAULT-44389](https://hashicorp.atlassian.net/browse/VAULT-44389).
  - Covers two independent issues: an invalid `environment` config value and a hard-coded auth endpoint; both affect US Government Cloud tenants.
  - Affected: all Vault versions using `go-kms-wrapping/wrappers/azurekeyvault/v2` <= v2.0.14; workarounds available.
  </details>

##### Transit

- [Transit Auto-Unseal Runbook](sys/seal/transit/transit-auto-unseal-runbook.md)
  `runbook` `sys` `seal`
  <details>
  <summary>Details</summary>

  - Local reproduction for Vault transit-based auto-unseal using two dev servers (transit + auto-unseal).
  - Includes a mock HCL config file (`vault-transit-auto-unseal.hcl`) and step-by-step startup, init, restart, and validation flow.
  </details>

- [KB: Circular Transit Auto-Unseal Dependency (Double Transit)](sys/seal/transit/double-transit-autounseal-dependency-kb.md)
  `kb` `sys` `seal`
  <details>
  <summary>Details</summary>

  - Documents a support case where two Vault clusters were configured to transit-unseal each other.
  </details>

#### Sync

- [Azure KV Secrets Sync `panic: not struct` Repro](sys/sync/azure-kv-secrets-sync-panic-repro.md)
  `repro` `sys` `sync` `azure` `enterprise`
  <details>
  <summary>Details</summary>

  - Reproduces a fatal `panic: not struct` in Vault `1.21.5+ent` triggered by writing a `sys/sync/destinations/azure-kv` destination with `disable_strict_networking=true`.
  - Includes Azure App Registration, Key Vault, and RBAC role setup using the Azure CLI.
  - Covers Secrets Sync activation, KV v2 test data, sync destination creation, association, and validation that the secret appears in Azure Key Vault.
  - Confirms the panic is resolved in `2.0.0+ent`.
  </details>

### Telemetry

- [Vault Telemetry Grafana Repro](telemetry/vault-telemetry-grafana-repro.md)
  `repro` `telemetry` `grafana`
  <details>
  <summary>Details</summary>

  - Configures Vault telemetry with Prometheus scraping and a local Grafana dashboard using `kube-prometheus-stack`.
  - Includes end-to-end setup and validation steps for metrics targets, Prometheus queries, and Grafana access.
  </details>

### Vault MCP Server

- [Vault MCP Server Guide](vault-mcp-server/vault-mcp-server-guide.md)
  `guide` `vault-mcp-server` `integration`
  <details>
  <summary>Details</summary>

  - Connects `vault-mcp-server` to an existing Kubernetes Vault cluster via port-forward.
  - Covers binary install, policy and token creation, and VS Code / Claude Desktop MCP client configuration.
  - Includes a policy file scoped to KV v2, mount management, and PKI operations.
  </details>

----

## Known Bugs & Regressions

- [Azure Key Vault Auto-Unseal: US Gov Cloud Bug (`go-kms-wrapping` ≤ v2.0.14)](sys/seal/azure/azurekeyvault-auto-unseal-gov-cloud.md)
	- Bug in `go-kms-wrapping` where the Azure AD authentication endpoint is hard-coded to public cloud, causing Vault startup failures for US Government Cloud tenants. Filed as [VAULT-44389](https://hashicorp.atlassian.net/browse/VAULT-44389).
	- Covers two independent issues: an invalid `environment` config value and a hard-coded auth endpoint; both affect US Government Cloud tenants.
	- Affected: all Vault versions using `go-kms-wrapping/wrappers/azurekeyvault/v2` ≤ v2.0.14; workarounds available.

- [AWS Secrets Engine Upgrade Findings (`1.19.1` → `1.19.9/1.19.10`)](secrets/aws/aws-secrets-engine-upgrade-findings-kb.md)
	- Multiple bugs introduced and inadvertently reintroduced across Vault `1.19.x`: STS client initialization failures, root config write timeouts, IAM signature/region failures, and `rotation_schedule`/window regressions in `1.19.9`.
	- Impacted large enterprise customers across multiple support tickets.

- [LDAP Secrets Engine UI `check-out` Regression in `1.20.6`–`1.20.10` and `1.21.5`](secrets/ldap/ldap-ui-capabilities-self-bug.md)
	- Vault UI regression in `1.20.6`–`1.20.10` and `1.21.5` where the LDAP Library Set `check-out` action disappears from the browser GUI for scoped users.
	- Resolved in `1.20.11`, `1.21.6`, `2.0.0` and onward.

- [Azure KV Secrets Sync `panic: not struct` (`1.21.5+ent`)](sys/sync/azure-kv-secrets-sync-panic-repro.md)
	- `panic: not struct` in `storeCreateUpdateHandler` when writing a `sys/sync/destinations/azure-kv` destination with `disable_strict_networking=true` on `1.21.5+ent`.
	- The request is forwarded via gRPC from a standby node; `github.com/fatih/structs.New()` receives a nil value at `logical_system_sync_stores_ent.go:622`.
	- Resolved in `2.0.0+ent`.

----

## TODO / Roadmap

Planned runbooks and KBs are tracked in [TODO.md](TODO.md). Refactoring some of the runbooks to be used in GitHub Codespaces.
