# Vault Associate Exam: What to Expect

This guide is for preparing for the HashiCorp Certified: Vault Associate (003) exam.

## Format

Official exam details:

- Assessment type: multiple choice
- Duration: 1 hour
- Price: $70.50 USD (plus local taxes/fees)
- Credential expiration: 2 years

Question style:

- True/false questions
- Multiple-choice questions (single answer)
- Multiple-answer questions

## Official Exam Objective Rubric

Official objective list: [Exam content list - Vault Associate (003)](https://developer.hashicorp.com/vault/tutorials/associate-cert-003/associate-review-003)

Domain breakdown:

- 1. Authentication methods (1a-1f)
  - Purpose of auth methods, selecting methods by use case, human vs system auth, identities/groups, and API/CLI/UI auth + config.
- 2. Vault policies (2a-2e)
  - Policy value, path/capability syntax, policy selection, and policy configuration in UI/CLI.
- 3. Vault tokens (3a-3f)
  - Service vs batch tokens, root token lifecycle, token accessors, TTL impact, orphan tokens, token creation.
- 4. Vault leases (4a-4c)
  - Lease IDs, renewal, and revocation.
- 5. Secrets engines (5a-5h)
  - Engine selection, dynamic vs static secrets, transit, response wrapping, and enabling/accessing secrets through CLI/API/UI.
- 6. Encryption as a service (6a-6b)
  - Encrypt/decrypt with transit and key rotation.
- 7. Vault architecture fundamentals (7a-7c)
  - Encryption model, seal/unseal process, and environment variable usage.
- 8. Vault deployment architecture (8a-8e)
  - Self-managed vs HashiCorp-managed strategy, storage backends, Shamir unsealing, DR vs performance replication.
- 9. Access management architecture (9a-9b)
  - Vault Agent and Vault Secrets Operator.

## Practical Study Workflow

Use this sequence so study time maps directly to exam objectives:

1. Access + auth + policy + tokens first (domains 1-3), including API/CLI/UI flow.
2. Secrets + leases + transit (domains 4-6), especially dynamic secrets and response wrapping.
3. Architecture and deployment concepts (domains 7-8), including integrated storage and replication concepts.
4. Access-management components (domain 9): Vault Agent and VSO purpose/use cases.
5. Run sample-question drills and review misses by objective ID.

## Readiness Checklist

Before scheduling, make sure you can do the following without prompts:

- Identify correct auth method for human vs machine use cases.
- Read and troubleshoot policy path/capability mismatches (including wildcard behavior).
- Explain token fields from lookup output (type, TTL, orphan, num_uses, accessor use).
- Choose correct secrets engine for a scenario (KV vs database vs transit).
- Explain lease renew/revoke behavior and when leases apply.
- Explain response wrapping value and short-lived secret handling.
- Compare DR replication vs performance replication at a concept level.
- Explain what Vault Agent and VSO solve, and where they fit.

## Material to Reference for Preparation

Official HashiCorp resources:

- Certification details + registration: [Security Automation Certifications](https://developer.hashicorp.com/certifications/security-automation#vault-associate-(003)-details)
- Learning path: [Vault Associate (003) study guide](https://developer.hashicorp.com/vault/tutorials/associate-cert-003/associate-study-003)
- Objective-by-objective rubric: [Vault Associate (003) exam content list](https://developer.hashicorp.com/vault/tutorials/associate-cert-003/associate-review-003)
- Question format practice: [Vault Associate (003) sample questions](https://developer.hashicorp.com/vault/tutorials/associate-cert-003/associate-questions-003)

External Resources:
- Bryan Krausen's Udemy Course: [HashiCorp Vault Associate Certification Course](https://www.udemy.com/course/hashicorp-vault/)

Internal repo practice material:
- [auth-userpass/userpass-entity-metadata-dynamic-policy-repro.md](../auth-userpass/userpass-entity-metadata-dynamic-policy-repro.md) — identities/groups + policy behavior (1d, 2a-2e)
- [auth-jwt/jwt-authentication-setup-and-login.sh](../auth-jwt/jwt-authentication-setup-and-login.sh) — auth method config/login workflow (1a-1f)
- [auth-jwt/jwt-bound-claims-glob-runbook.md](../auth-jwt/jwt-bound-claims-glob-runbook.md) — auth troubleshooting + policy matching mindset (1b, 2b-2d)
- [auth-token/token-role-allowed-policies-glob-kb.md](../auth-token/token-role-allowed-policies-glob-kb.md) — token/policy constraints and glob semantics (2d, 3a-3f)
- [secrets-kv/kv-v2-soft-delete-destroy-undelete-recovery-runbook.md](../secrets-kv/kv-v2-soft-delete-destroy-undelete-recovery-runbook.md) — KV v2 lifecycle + secrets engine behavior (5a-5h)
- [secrets-postgresql-db/postgresql-database-secrets-engine-repro.md](../secrets-postgresql-db/postgresql-database-secrets-engine-repro.md) — dynamic secrets, leases, revoke/renew patterns (4a-4c, 5b, 5f)
- [secrets-rabbitmq-db/rabbitmq-secrets-engine-repro.md](../secrets-rabbitmq-db/rabbitmq-secrets-engine-repro.md) — another dynamic secrets + lease flow (4, 5)
- [secrets-totp/totp-secrets-engine-repro.md](../secrets-totp/totp-secrets-engine-repro.md) — broader engine familiarity (5a, 5d)
- [setup/vault-encryption-key-rotation-and-rekey-runbook.md](../setup/vault-encryption-key-rotation-and-rekey-runbook.md) — seal/unseal fundamentals, key rotation/rekey concepts (7a-7c, 8c)
- [seal-awskms/awskms-auto-unseal-runbook.md](../seal-awskms/awskms-auto-unseal-runbook.md) and [seal-azure/azurekeyvault-auto-unseal-runbook.md](../seal-azure/azurekeyvault-auto-unseal-runbook.md) — auto-unseal concepts in practice (7b, 8b-8e)
- [replication/vault-enterprise-replication-pr-dr-runbook.md](../replication/vault-enterprise-replication-pr-dr-runbook.md) — DR vs performance replication concepts (8d)
- [kubernetes/vso-k8s-auth-static-dynamic/vso-k8s-auth-static-dynamic-repro.md](../kubernetes/vso-k8s-auth-static-dynamic/vso-k8s-auth-static-dynamic-repro.md) — VSO objective coverage (9b)
- [vault-professional-cert/lab-03-vault-agent-approle-templating.md](../vault-professional-cert/lab-03-vault-agent-approle-templating.md) — very useful for Vault Agent fundamentals (9a) even though it lives under professional prep