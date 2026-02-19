# Vault Reproductions

This repository is a practical lab for Vault admins who need quick, serviceable environments to test behavior, validate assumptions, and reproduce edge cases.

The goal is to help you stand up scenarios quickly, learn how Vault behaves in real integrations, and troubleshoot nuanced issues before they affect production.

## What this project is for

- Spin up focused Vault test environments quickly
- Reproduce auth and secrets engine behavior with minimal setup overhead
- Validate expected vs actual behavior for support cases and internal testing
- Build repeatable scenarios for learning and troubleshooting

## Available scenarios

### Authentication scenarios

- [auth-userpass/Userpass Entity Metadata Dynamic Policy Repro.md](auth-userpass/Userpass%20Entity%20Metadata%20Dynamic%20Policy%20Repro.md)
	- Local reproduction for dynamic policy templating using entity metadata.
	- Demonstrates immediate access changes on active tokens when entity metadata changes.

- [auth-kubernetes/Create Kubernetes Users and Login.sh](auth-kubernetes/Create%20Kubernetes%20Users%20and%20Login.sh)
	- Creates Kubernetes service accounts, configures Vault Kubernetes auth, and tests login flow.
	- Useful for evaluating how Vault creates and maps identities during Kubernetes auth.
	- Includes behavior validation related to entities and aliases.

- [auth-userpass/Userpass Authentication Setup.sh](auth-userpass/Userpass%20Authentication%20Setup.sh)
	- Enables userpass auth, creates test users, and validates login/token behavior.
	- Useful for observing identity handling when many local auth users are created and used.
	- Includes behavior validation related to entities and aliases.

### Secrets engine scenarios

- [secrets-artifactory/Artifactory Plugin Registration.sh](secrets-artifactory/Artifactory%20Plugin%20Registration.sh)
	- Amazon Linux setup script for Vault Enterprise + JFrog Artifactory secrets plugin registration.
	- Includes plugin checksum validation and flattened plugin directory layout to avoid execution path errors.

- [secrets-ldap/setup ldap secrets engine repro.md](secrets-ldap/setup%20ldap%20secrets%20engine%20repro.md)
	- OpenLDAP + Vault LDAP secrets engine setup focused on bind account and static-role password rotation timing.

- [secrets-ldap/openldap-deployment.yaml](secrets-ldap/openldap-deployment.yaml)
	- Kubernetes manifest used by the LDAP reproduction.

- [secrets-oracle-db/Oracle Database Plugin Setup.md](secrets-oracle-db/Oracle%20Database%20Plugin%20Setup.md)
	- Rapid Oracle environment setup for testing Vault database plugin behavior with dynamic and static credentials.

### Kubernetes/platform behavior

- [kubernetes/LivenessProbe KB.md](kubernetes/LivenessProbe%20KB.md)
	- Demonstrates automatic Vault pod recovery when TLS certificates expire, using Kubernetes liveness probes.

## How to use this repository

1. Choose a scenario based on the behavior you want to test.
2. Open the scenario script/guide and review prerequisites.
3. Run the setup exactly as written.
4. Validate behavior with the included verification steps.
5. Re-run with small changes to isolate nuanced behavior.

## Intended audience

Vault administrators, support engineers, and platform engineers who need fast, reproducible Vault integration environments.
