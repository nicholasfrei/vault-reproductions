# Vault Professional Exam: What to Expect

This guide is to be used for preparation for the Vault Professional Exam.

## Format

- 17 multiple-choice / knowledge questions
- 4 hands-on lab scenarios
- 1 hybrid scenario with a lab and multiple-choice questions
- 4 hours = total exam time

## Official Exam Objective Rubric

HashiCorp Vault Operations Professional exam content list: [Exam content list - Vault Operations Professional](https://developer.hashicorp.com/vault/tutorials/ops-pro-cert/ops-pro-review)

- 1. Server configuration: secret engines, hardening, auto-unseal, raft storage, auth methods, init/generate-root/rekey/rotate
- 2. Monitoring: telemetry, audit logs, operational/server logs
- 3. Security model: secure client introduction, Kubernetes security implications
- 4. Fault tolerance: HA clustering, DR replication, DR secondary promotion (Enterprise)
- 5. HSM integration: auto-unseal with HSM, seal wrap use cases (Enterprise)
- 6. Performance scale: batch tokens, performance standbys, PR replication, path filters (Enterprise)
- 7. Access control: identity entities/groups, ACL policy troubleshooting, Sentinel, control groups, namespaces (Enterprise where applicable)
- 8. Vault Agent: auto-auth + sink security, templating

## Mock Lab Scenarios
## Lab 1: Transit auto-unseal and node bootstrap

Expected capabilities:

- Configure transit auto-unseal on an initial node
   - create the vault configuration with the correct seal stanza
- After transit auto-unseal is configured, initialize the cluster with PGP recovery keys. See [Vault operator init HSM and KMS options](https://developer.hashicorp.com/vault/docs/commands/operator/init#hsm-and-kms-options).
- Unseal and validate cluster health
- Configure a second node with transit auto-unseal
   - create the vault configuration with the correct seal stanza
- Join second node to the first node

Practice checklist:

- Validate `seal "transit"` stanza and token permissions
- Confirm `vault operator init` with correct recovery key type and count
- Verify unseal/health status before joining peers
- Use correct join commands and validate raft peers after join

## Lab 2: AppRole + response wrapping + database secrets engine

Expected capabilities:

- Enable and configure AppRole auth
- Generate a wrapped `secret_id` (response wrapping)
- Persist wrapped output to JSON (for grading)
- Configure database secrets engine to connect to PostgreSQL
- Rotate root credentials and create a role for dynamic credential generation
- Validate role issuance and credential retrieval

Practice checklist:

- Use `-wrap-ttl` for response wrapping and confirm wrapped token behavior. See [Response wrapping token creation](https://developer.hashicorp.com/vault/docs/concepts/response-wrapping#response-wrapping-token-creation).
- Save output with `-format=json`
- Test DB connection config and dynamic credential generation

## Lab 3: Vault Agent with AppRole auto-auth and templating

Expected capabilities:

- Configure Vault Agent
   - create agent configuration from scratch with correct auto-auth
- Configure AppRole auto-auth
- Render templates via Vault Agent templating
- Validate token/lease behavior and rendered output
- Save template output to a file for grading

Practice checklist:

- Verify `auto_auth` and sink behavior
- Do not delete the secret-id upon authentication. See [AppRole auto-auth: remove_secret_id_file_after_reading](https://developer.hashicorp.com/vault/docs/agent-and-proxy/autoauth/methods/approle#remove_secret_id_file_after_reading).
- Validate template destination permissions
- Confirm template updates after secret rotation/change

## Lab 4: Performance replication with path filtering

Expected capabilities:

- Configure performance replication (PR)
- Enable PR primary
- Enable PR secondary
- Join secondary to primary
- Apply and verify path filtering. See [Performance replication: create paths filter](https://developer.hashicorp.com/vault/api-docs/system/replication/replication-performance#create-paths-filter).

Practice checklist:

- Verify primary/secondary status endpoints
   - `vault read -format=json sys/replication/performance/status`

## Lab 5: Policies, namespaces, and KV v2 operations

Expected capabilities:

- Write/debug ACL policies
- Work with namespace-aware commands and tokens
- Configure and use KV v2 correctly (paths, versions, metadata)
- Answer conceptual questions on policy evaluation and namespace scoping
- Understand the difference between internal vs external groups

Practice checklist:

- Practice exact path matching (`data/`, `metadata/`, etc.)
- Validate capabilities with token self-lookup and real reads/writes
- Test namespace context with policies and authentication

## Material to Reference for Preparation

For those of you who will take the exam in the future, feel free to reference the following materials for preparation. The exam focuses heavily on creating configuration files from scratch, so (TODO) I will add some specific labs that are designed to be as close to the exam experience as possible. In the meantime, the following materials are good references for the topics covered in the exam:

External Resources:

- Udemy Course: [HashiCorp Certified Vault Operations Professional](https://ibm-learning.udemy.com/course/hashicorp-certified-vault-operations-professional/)

Generic Resources:

- Transit auto-unseal baseline: [seal-transit/transit-auto-unseal-runbook.md](../seal-transit/transit-auto-unseal-runbook.md)
- PGP recovery key setup helper: [setup/setup-pgp-keys-for-vault.sh](../setup/setup-pgp-keys-for-vault.sh)
- PostgreSQL secrets engine baseline: [secrets-postgresql-db/postgresql-database-secrets-engine-repro.md](../secrets-postgresql-db/postgresql-database-secrets-engine-repro.md)
- Replication concepts and recovery context: [replication/vault-replication-merkle-corruption-reindex-kb.md](../replication/vault-replication-merkle-corruption-reindex-kb.md)
- Namespace and policy-heavy examples: [auth-userpass/userpass-entity-metadata-dynamic-policy-repro.md](../auth-userpass/userpass-entity-metadata-dynamic-policy-repro.md)
- Sentinel EGP/RGP governance examples: [sys-policies/sentinel-egp-rgp-governing-policies-kb.md](../sys-policies/sentinel-egp-rgp-governing-policies-kb.md)

Mock lab Resources:

- Lab 2: AppRole + wrapping + PostgreSQL walkthrough: [vault-professional-cert/lab-02-approle-wrapping-and-postgresql.md](./lab-02-approle-wrapping-and-postgresql.md)
- Lab 4: Performance replication with path filtering: [vault-professional-cert/lab-04-pr-replication-path-filtering.md](./lab-04-pr-replication-path-filtering.md)
- Lab 5: Policies + KV v2 + namespaces walkthrough: [vault-professional-cert/lab-05-policy-kvv2-namespaces.md](./lab-05-policy-kvv2-namespaces.md)

Future additions:

1. vault-professional-cert/lab-01-transit-auto-unseal-and-node-join.md
   - Transit seal config, init/unseal, node join validation
2. vault-professional-cert/lab-03-vault-agent-approle-templating.md
   - Agent auto-auth and template rendering walkthrough