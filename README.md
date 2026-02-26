# Vault Reproductions

This repository is a vault (wink) of various scenarios I've worked with during my time as a Senior Support Engineer. The goal is to share various scripts, guides, and reproductions for different Vault plugins. Some of these are based on real support cases or incidents, while others are smaller scripts to assist with learning Vault. 

## What this project is for

- Build repeatable scenarios for learning and troubleshooting
- Quickly spin up environments to test specific Vault behaviors

## Prerequisites

- Homebrew
- kubectl
- helm
- minikube
- docker (Docker Desktop or Docker Engine)
- jq

### Additional tools used by specific scenarios

- gpg 
- unzip + wget/curl
- ldapsearch + nc 
- psql 
- sqlplus 


### Quick install (macOS via Homebrew)

```bash
brew install jq kubectl helm minikube vault gnupg wget
```

If you do not use Homebrew, install equivalent packages with your OS package manager.

## Available scenarios

### Authentication Mounts
- [auth-userpass/userpass-entity-metadata-dynamic-policy-repro.md](auth-userpass/userpass-entity-metadata-dynamic-policy-repro.md)
	- Local reproduction for dynamic policy templating using entity metadata.
	- Demonstrates immediate access changes on active tokens when entity metadata changes.

- [auth-userpass/userpass-authentication-setup.sh](auth-userpass/userpass-authentication-setup.sh)
	- Enables userpass auth, creates test users, and validates login/token behavior.
	- Useful for observing identity handling when many local auth users are created and used.
	- Includes behavior validation related to entities and aliases.

- [auth-kubernetes/create-kubernetes-users-and-login.sh](auth-kubernetes/create-kubernetes-users-and-login.sh)
	- Creates Kubernetes service accounts, configures Vault Kubernetes auth, and tests login flow.
	- Useful for evaluating how Vault creates and maps identities during Kubernetes auth.
	- Includes behavior validation related to entities and aliases.

### Secrets Engines
- [secrets-artifactory/artifactory-plugin-registration.sh](secrets-artifactory/artifactory-plugin-registration.sh)
	- Amazon Linux setup script for Vault Enterprise + JFrog Artifactory secrets plugin registration.
	- Includes plugin checksum validation and flattened plugin directory layout to avoid execution path errors.

- [secrets-ldap/setup-ldap-secrets-engine-repro.md](secrets-ldap/setup-ldap-secrets-engine-repro.md)
	- OpenLDAP + Vault LDAP secrets engine setup focused on bind account and static-role password rotation timing.
	- Uses [secrets-ldap/openldap-deployment.yaml](secrets-ldap/openldap-deployment.yaml) as the backing Kubernetes manifest.

- [secrets-oracle-db/oracle-database-plugin-setup.md](secrets-oracle-db/oracle-database-plugin-setup.md)
	- Rapid Oracle environment setup for testing Vault database plugin behavior with dynamic and static credentials.

- [secrets-pki-cmpv2/cmpv2-pki-integration-guide.md](secrets-pki-cmpv2/cmpv2-pki-integration-guide.md)
	- Markdown-only runbook for Vault PKI CMPv2 integration and proxy behavior validation.
	- Includes concrete expected output blocks from a successful direct + proxied CMP IR repro.

- PostgreSQL database plugin scenarios
	- [secrets-postgresql-db/postgresql-database-secrets-engine-repro.md](secrets-postgresql-db/postgresql-database-secrets-engine-repro.md)
		- PostgreSQL + Vault database secrets engine setup covering dynamic credentials, static role rotation, and custom password policies.
		- Useful for validating credential lifecycle, lease revocation, and rotation timing behavior.
	- [secrets-postgresql-db/postgresql-static-role-denial-of-service-repro.md](secrets-postgresql-db/postgresql-static-role-denial-of-service-repro.md)
		- Reproduces static role rotation pressure when the backing PostgreSQL target is unavailable or decommissioned.
		- Useful for incident response drills and understanding cleanup/recovery patterns for stale static roles.

### Vault MCP Server

- [vault-mcp-server/vault-mcp-server-setup.md](vault-mcp-server/vault-mcp-server-setup.md)
	- Connects `vault-mcp-server` to an existing Kubernetes Vault cluster via port-forward.
	- Covers binary install, policy and token creation, and VS Code / Claude Desktop MCP client configuration.
	- Includes a policy file scoped to KV v2, mount management, and PKI operations.

### Vault Setup

- [setup/initialize-and-unseal-vault-cluster.sh](setup/initialize-and-unseal-vault-cluster.sh)
	- Installs Vault via Helm (HA + Raft, 3 pods), initializes with 5 total key shares and threshold 3, saves init output to `init.json`, unseals all nodes, and logs into `vault-0` with the root token.

- [setup/setup-pgp-keys-for-vault.sh](setup/setup-pgp-keys-for-vault.sh)
	- Generates PGP key pairs, copies public keys into the Vault pod, and runs `vault operator init` with PGP-encrypted unseal keys. Targets `vault-0` in namespace `vault` (configurable).

- [setup/cleanup-vault-sandbox.sh](setup/cleanup-vault-sandbox.sh)
	- Cleans up sandbox state between runs: uninstalls the Vault Helm release, deletes the `vault` namespace, deletes the Minikube `vault` profile, and removes `setup/init.json`.

### Kubernetes / Platform Behavior

- [kubernetes/liveness-probe-kb.md](kubernetes/liveness-probe-kb.md)
	- Demonstrates automatic Vault pod recovery when TLS certificates expire, using Kubernetes liveness probes.

- [kubernetes/proxy-tls-behavior/vault-proxy-tls-behavior-repro.md](kubernetes/proxy-tls-behavior/vault-proxy-tls-behavior-repro.md)
	- Reproduces HTTP client traffic into a local proxy with TLS-only Vault upstream.
	- Validates that Vault can stay TLS-only while a front proxy handles plaintext listener and HTTPS re-encryption.

## How to use this repository

1. Find the scenario or plugin you're interested in.
2. Follow the instructions in the file.
3. Voilà.