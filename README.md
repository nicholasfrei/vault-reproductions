# Vault Reproductions

This repository is a vault (wink) of various scenarios I've worked with during my time as a Senior Support Engineer. The goal is to share various scripts, guides, and reproductions for different Vault plugins. Some of these are based on real support cases or incidents, while others are smaller scripts to assist with learning Vault. 

## Table of contents

- [Prerequisites](#prerequisites)
- [Available scenarios](#available-scenarios)
	- [Authentication Mounts](#authentication-mounts)
	- [Secrets Engines](#secrets-engines)
	- [Vault MCP Server](#vault-mcp-server)
	- [Vault Setup](#vault-setup)
	- [Seal / Unseal](#seal--unseal)
	- [Linux / Platform Behavior](#linux--platform-behavior)
	- [Kubernetes / Platform Behavior](#kubernetes--platform-behavior)
	- [Telemetry](#telemetry)

## How to use this repository

1. Find the plugin you're interested in.
2. Reference various KB's or Runbook's based on your need.
3. Follow the instructions in the file.
4. Voilà.

## Prerequisites

Most runbooks use these core tools:

- Homebrew (or any package manager)
- `kubectl`, `helm`, `minikube`
- Docker (`Docker Desktop` or Docker Engine)
- `jq`

Some scenarios also require:

- `gpg`
- `unzip` and `wget`/`curl`
- `ldapsearch` and `nc`
- `psql`
- `sqlplus`

### Quick install (Homebrew)

```bash
brew install jq kubectl helm minikube gnupg wget
```

If you do not use Homebrew, install equivalent packages with your OS package manager.

## Available scenarios

### Authentication Mounts
- [Userpass Entity Metadata Dynamic Policy Repro](auth-userpass/userpass-entity-metadata-dynamic-policy-repro.md)
	- Local reproduction for dynamic policy templating using entity metadata.
	- Demonstrates immediate access changes on active tokens when entity metadata changes.

- [Userpass Authentication Setup Script](auth-userpass/userpass-authentication-setup.sh)
	- Enables userpass auth, creates test users, and validates login/token behavior.
	- Useful for observing identity handling when many local auth users are created and used.
	- Includes behavior validation related to entities and aliases.

- [Kubernetes Auth User Creation and Login Script](auth-kubernetes/create-kubernetes-users-and-login.sh)
	- Creates Kubernetes service accounts, configures Vault Kubernetes auth, and tests login flow.
	- Useful for evaluating how Vault creates and maps identities during Kubernetes auth.
	- Includes behavior validation related to entities and aliases.

- [JWT Authentication Setup and Login Script](auth-jwt/jwt-authentication-setup-and-login.sh)
	- Configures Vault JWT auth with a local RSA key pair and issuer binding.
	- Creates per-user JWT roles, signs demo JWTs, and validates login for each configured user.
	- Optionally creates and reads a KV v2 demo secret to confirm post-login policy access.

- [JWT Bound Claims Glob Runbook](auth-jwt/jwt-bound-claims-glob-runbook.md)
	- Reproduces JWT claim validation failures for nested namespace paths when `bound_claims_type` uses exact string matching.
	- Demonstrates the fix with `bound_claims_type="glob"` and wildcard `namespace_path` patterns.
	- Includes case-sensitivity checks, token-claim decoding, and cleanup commands.

### Secrets Engines
- [Artifactory Plugin Registration Script](secrets-artifactory/artifactory-plugin-registration.sh)
	- Amazon Linux setup script for Vault Enterprise + JFrog Artifactory secrets plugin registration.
	- Includes plugin checksum validation and flattened plugin directory layout to avoid execution path errors.

- [LDAP Secrets Engine Setup Repro](secrets-ldap/setup-ldap-secrets-engine-repro.md)
	- OpenLDAP + Vault LDAP secrets engine setup focused on bind account and static-role password rotation timing.
	- Uses [secrets-ldap/openldap-deployment.yaml](secrets-ldap/openldap-deployment.yaml) as the backing Kubernetes manifest.

- [Oracle Database Plugin Setup](secrets-oracle-db/oracle-database-plugin-setup.md)
	- Rapid Oracle environment setup for testing Vault database plugin behavior with dynamic and static credentials.

- [CMPv2 PKI Integration Guide](secrets-pki-cmpv2/cmpv2-pki-integration-guide.md)
	- Markdown-only runbook for Vault PKI CMPv2 integration and proxy behavior validation.
	- Includes concrete expected output blocks from a successful direct + proxied CMP IR repro.

- [RabbitMQ Secrets Engine Repro](secrets-rabbitmq-db/rabbitmq-secrets-engine-repro.md)
	- Simple RabbitMQ + Vault secrets engine runbook for dynamic credential issuance and lease revocation validation.
	- Assumes an already-operational Vault cluster in Kubernetes and uses a local RabbitMQ container for testing.

- [AWS Secrets Engine Upgrade Findings KB](secrets-aws/aws-secrets-engine-upgrade-findings-kb.md)
    - Discusses real-life errors faced by enterprise customers found in v1.19.x for `sts_endpoint`, `iam_endpoint`, and rotation schedule/window(s).

- [TOTP Secrets Engine Repro](secrets-totp/totp-secrets-engine-repro.md)
	- Reproduction runbook for the Vault TOTP secrets engine, including setup and validation flow.

- PostgreSQL database plugin scenarios
	- [PostgreSQL Database Secrets Engine Repro](secrets-postgresql-db/postgresql-database-secrets-engine-repro.md)
		- PostgreSQL + Vault database secrets engine setup covering dynamic credentials, static role rotation, and custom password policies.
		- Useful for validating credential lifecycle, lease revocation, and rotation timing behavior.
	- [PostgreSQL Static Role Denial of Service Repro](secrets-postgresql-db/postgresql-static-role-denial-of-service-repro.md)
		- Reproduces static role rotation pressure when the backing PostgreSQL target is unavailable or decommissioned.
		- Useful for incident response drills and understanding cleanup/recovery patterns for stale static roles.

### Vault MCP Server

- [Vault MCP Server Setup](vault-mcp-server/vault-mcp-server-setup.md)
	- Connects `vault-mcp-server` to an existing Kubernetes Vault cluster via port-forward.
	- Covers binary install, policy and token creation, and VS Code / Claude Desktop MCP client configuration.
	- Includes a policy file scoped to KV v2, mount management, and PKI operations.

### Vault Setup

- [Vault Cluster Init Script](setup/init.sh)
	- Installs Vault via Helm (HA + Raft, 3 pods), initializes with 5 total key shares and threshold 3, saves init output to `setup/init.json`, unseals all nodes, and logs into `vault-0` with the root token.

- [Vault PGP Key Setup Script](setup/setup-pgp-keys-for-vault.sh)
	- Generates PGP key pairs, copies public keys into the Vault pod, and runs `vault operator init` with PGP-encrypted unseal keys. Targets `vault-0` in namespace `vault` (configurable).

- [Vault Encryption Key Rotation + Rekey Runbook](setup/vault-encryption-key-rotation-and-rekey-runbook.md)
	- Step-by-step runbook for rotating the Vault encryption key term (`sys/rotate`) and rekeying Shamir unseal shares (`vault operator rekey`).
	- Includes least-privilege policy example, command syntax gotchas, and post-change validation checks.

- [Vault Sandbox Cleanup Script](setup/cleanup.sh)
	- Cleans up sandbox state between runs: uninstalls the Vault Helm release, deletes the `vault` namespace, deletes the Minikube `vault` profile, and removes `setup/init.json`.

### Seal / Unseal

- [Transit Auto-Unseal Runbook](seal-transit/transit-auto-unseal-runbook.md)
	- Local reproduction for Vault transit-based auto-unseal using two dev servers (transit + auto-unseal).
	- Includes a mock HCL config file (`vault-transit-auto-unseal.hcl`) and step-by-step startup, init, restart, and validation flow.

### Linux / Platform Behavior

- [Vault Logrotate KB](linux/vault-logrotate-kb.md)
	- Practical Linux/systemd-focused guidance for Vault logrotate configuration and troubleshooting.
	- Includes directive-by-directive explanations, safer rotation recommendations, and validation steps.

- [Merkle Corruption Reindex KB](linux/vault-replication-merkle-corruption-reindex-kb.md)
	- Runbook for resolving PR/DR replication stuck in `merkle-diff`/`merkle-sync` due to corrupted primary merkle trees.
	- Covers primary-first reindex strategy, write-lock expectations, validation checkpoints, and rollback cautions.

### Kubernetes / Platform Behavior

- [Liveness Probe KB](kubernetes/liveness-probe-kb.md)
	- Demonstrates automatic Vault pod recovery when TLS certificates expire, using Kubernetes liveness probes.

- [Vault Raft Quorum Break and Restore Runbook](kubernetes/vault-raft-quorum-break-and-restore-runbook.md)
	- Reproduces quorum-loss by scaling a Vault StatefulSet down to one pod, then restores service with single-node raft peer recovery and scale-out validation.

- [Vault Proxy TLS Behavior Repro](kubernetes/proxy-tls-behavior/vault-proxy-tls-behavior-repro.md)
	- Reproduces HTTP client traffic into a local proxy with TLS-only Vault upstream.
	- Validates that Vault can stay TLS-only while a front proxy handles plaintext listener and HTTPS re-encryption.

- [VSO Kubernetes Auth Static and Dynamic Repro](kubernetes/vso-k8s-auth-static-dynamic/vso-k8s-auth-static-dynamic-repro.md)
	- Reproduces Vault Secrets Operator sync flows for static KV v2 secrets and dynamic database credentials using Vault Kubernetes authentication.
	- Includes policy and role setup, secret rotation verification, and failure injection by breaking/restoring Kubernetes auth role bindings.

- [VSO Special Character Secret Keys KB](kubernetes/vso-special-character-secret-keys-kb.md)
	- Documents VSO sync failures when KV keys include Kubernetes-invalid characters such as `@`.
	- Includes a runnable repro, expected vs observed behavior, and workaround/architecture guidance.

- [VSO AKS UDP DNS Race KB](kubernetes/vso-aks-udp-dns-race-kb.md)
	- Documents intermittent VSO DNS timeout failures in AKS (`read udp ... :53: i/o timeout`) after initial successful reconciles. This was a customer incident where all application pods lost connectivity to Vault after a certain period of time, and the root cause was traced back to VSO DNS timeouts due to AKS UDP conntrack behavior.
	- Covers UDP conntrack race hypothesis, validation commands, and mitigations (LocalDNS and/or shorter refresh intervals).

### Telemetry

- [Vault Telemetry Grafana Repro](telemetry/vault-telemetry-grafana-repro.md)
	- Configures Vault telemetry with Prometheus scraping and a local Grafana dashboard using `kube-prometheus-stack`.
	- Includes end-to-end setup and validation steps for metrics targets, Prometheus queries, and Grafana access.


## TODO Runbooks / KBs to Add

- **Replication (Enterprise)**
  - [ ] Performance Replication setup, failover, and common troubleshooting patterns.
  - [ ] DR Replication setup, promotion workflow, failback workflow, and resync behavior.
  - [ ] Secondary stuck behind WAL / replication lag diagnosis and recovery.
  - [ ] Region loss simulation and service restoration timeline runbook.

- **Seal / Unseal**
  - [ ] Multi-seal and Seal HA runbook (config patterns, startup order, and failure modes).
  - [ ] Auto-unseal migration (Shamir -> KMS/HSM) with rollback considerations.

- **Raft / Storage**
  - [ ] Integrated storage autopilot behavior, dead server cleanup, and peer replacement.
  - [ ] Snapshot/restore validation runbook (single cluster and cross-cluster restore checks).

- **Auth Methods**
  - [ ] OIDC auth deep-dive repro (groups claim mapping, bound claims, and redirect URI issues).
  - [ ] AppRole hardening and incident-response runbook (secret-id rotation and token cleanup).
	- Also lease explosion with approle (this is a common ent issue that we run into)

- **Secrets Engines**
  - [ ] KV v2 soft-delete/destroy/undelete behavior and recovery expectations.
  - [ ] Secret mount recovery / restore 

- **PKI**
  - [ ] Intermediate rotation, CRL/OCSP behavior (tidy, etc), and outage mitigation runbook.

- **Namespaces (Enterprise)**
  - [ ] Parent/child namespace policy inheritance and token scope gotchas.

- **Audit / Security**
  - [ ] Audit device performance impact and log integrity validation checklist.

- **Kubernetes**
  - [ ] Vault injector webhook troubleshooting (cert rotation, startup ordering, and mutation failures).

- **Terraform / Vault Provider**
	- [ ] Terraform Vault provider setup and authentication patterns (token, AppRole, JWT/OIDC, Kubernetes auth).
	- [ ] Terraform Vault provider troubleshooting runbook (namespace issues, token expiry, policy denies, and state drift handling).