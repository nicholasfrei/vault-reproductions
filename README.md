# Vault Reproductions

This repository is a vault (wink) of various scenarios I've worked with during my time as a Senior Support Engineer. The goal is to share various scripts, guides, and reproductions for different Vault plugins. Some of these are based on real support cases or incidents, while others are smaller scripts to assist with learning Vault. 

## What this project is for

- Build repeatable scenarios for learning and troubleshooting
- Quickly spin up environments to test specific Vault behaviors

## Available scenarios

### Authentication Mounts
- [auth-userpass/Userpass Entity Metadata Dynamic Policy Repro.md](auth-userpass/Userpass%20Entity%20Metadata%20Dynamic%20Policy%20Repro.md)
	- Local reproduction for dynamic policy templating using entity metadata.
	- Demonstrates immediate access changes on active tokens when entity metadata changes.

- [auth-userpass/Userpass Authentication Setup.sh](auth-userpass/Userpass%20Authentication%20Setup.sh)
	- Enables userpass auth, creates test users, and validates login/token behavior.
	- Useful for observing identity handling when many local auth users are created and used.
	- Includes behavior validation related to entities and aliases.

- [auth-kubernetes/Create Kubernetes Users and Login.sh](auth-kubernetes/Create%20Kubernetes%20Users%20and%20Login.sh)
	- Creates Kubernetes service accounts, configures Vault Kubernetes auth, and tests login flow.
	- Useful for evaluating how Vault creates and maps identities during Kubernetes auth.
	- Includes behavior validation related to entities and aliases.

### Secrets Engines
- [secrets-artifactory/Artifactory Plugin Registration.sh](secrets-artifactory/Artifactory%20Plugin%20Registration.sh)
	- Amazon Linux setup script for Vault Enterprise + JFrog Artifactory secrets plugin registration.
	- Includes plugin checksum validation and flattened plugin directory layout to avoid execution path errors.

- [secrets-ldap/setup ldap secrets engine repro.md](secrets-ldap/setup%20ldap%20secrets%20engine%20repro.md)
	- OpenLDAP + Vault LDAP secrets engine setup focused on bind account and static-role password rotation timing.
	- Uses [secrets-ldap/openldap-deployment.yaml](secrets-ldap/openldap-deployment.yaml) as the backing Kubernetes manifest.

- [secrets-oracle-db/Oracle Database Plugin Setup.md](secrets-oracle-db/Oracle%20Database%20Plugin%20Setup.md)
	- Rapid Oracle environment setup for testing Vault database plugin behavior with dynamic and static credentials.

- PostgreSQL database plugin scenarios
	- [secrets-postgresql-db/PostgreSQL Database Secrets Engine Repro.md](secrets-postgresql-db/PostgreSQL%20Database%20Secrets%20Engine%20Repro.md)
		- PostgreSQL + Vault database secrets engine setup covering dynamic credentials, static role rotation, and custom password policies.
		- Useful for validating credential lifecycle, lease revocation, and rotation timing behavior.
	- [secrets-postgresql-db/PostgreSQL Static Role Denial-of-Service Repro.md](secrets-postgresql-db/PostgreSQL%20Static%20Role%20Denial-of-Service%20Repro.md)
		- Reproduces static role rotation pressure when the backing PostgreSQL target is unavailable or decommissioned.
		- Useful for incident response drills and understanding cleanup/recovery patterns for stale static roles.

### Vault MCP Server

- [vault-mcp-server/Vault MCP Server Setup.md](vault-mcp-server/Vault%20MCP%20Server%20Setup.md)
	- Connects `vault-mcp-server` to an existing Kubernetes Vault cluster via port-forward.
	- Covers binary install, policy and token creation, and VS Code / Claude Desktop MCP client configuration.
	- Includes a policy file scoped to KV v2, mount management, and PKI operations.

### Vault Setup

- [setup/Initialize and Unseal Vault Cluster.sh](setup/Initialize%20and%20Unseal%20Vault%20Cluster.sh)
	- Installs Vault via Helm (HA + Raft, 3 pods), initializes with 5 total key shares and threshold 3, saves init output to `init.json`, unseals all nodes, and logs into `vault-0` with the root token.

- [setup/Setup PGP Keys for Vault.sh](setup/Setup%20PGP%20Keys%20for%20Vault.sh)
	- Generates PGP key pairs, copies public keys into the Vault pod, and runs `vault operator init` with PGP-encrypted unseal keys. Targets `vault-0` in namespace `vault` (configurable).

- [setup/Cleanup Vault Sandbox.sh](setup/Cleanup%20Vault%20Sandbox.sh)
	- Cleans up sandbox state between runs: uninstalls the Vault Helm release, deletes the `vault` namespace, deletes the Minikube `vault` profile, and removes `setup/init.json`.

### Kubernetes / Platform Behavior

- [kubernetes/LivenessProbe KB.md](kubernetes/LivenessProbe%20KB.md)
	- Demonstrates automatic Vault pod recovery when TLS certificates expire, using Kubernetes liveness probes.

## How to use this repository

1. Find the scenario or plugin you're interested in.
2. Follow the instructions in the file.
3. Voilà.