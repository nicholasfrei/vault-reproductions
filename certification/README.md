# Certification

Vault Associate and Professional exam guides and hands-on labs.

Lab prerequisites are in the [root README](../README.md). Confirmed version-specific defects are in [KNOWN_BUGS.md](../KNOWN_BUGS.md).

Legend: `runbook` = procedural, `kb` = break-fix analysis, `repro` = focused behavior demo, `guide` = broader walkthrough, `script` = executable is the primary deliverable.

## Vault Associate Cert

- [Vault Associate Exam Guide](vault-associate-cert/vault-associate-exam-guide.md)
  `guide` `certification` `associate`
  <details>
  <summary>Details</summary>

  - Guide covering the Vault Associate Exam: format, rubric, and external resources.
  </details>

## Vault Professional Cert

- [Vault Professional Exam Guide](vault-professional-cert/vault-professional-exam-guide.md)
  `guide` `certification` `professional`
  <details>
  <summary>Details</summary>

  - Guide covering the Vault Professional Exam: format, rubric, and lab scenarios.
  </details>

- [Lab 1: Transit Auto-Unseal and Node Join](vault-professional-cert/lab-01-transit-auto-unseal-and-node-join.md)
  `runbook` `certification` `professional`
  <details>
  <summary>Details</summary>

  - Hands-on runbook for configuring a transit-backed auto-unseal flow and joining a node to a cluster.
  </details>

- [Lab 2: AppRole + response wrapping + database secrets engine](vault-professional-cert/lab-02-approle-wrapping-and-postgresql.md)
  `runbook` `certification` `professional`
  <details>
  <summary>Details</summary>

  - Hands-on runbook for AppRole login with wrapped `secret_id`, JSON output capture, and PostgreSQL dynamic credentials validation.
  </details>

- [Lab 3: Vault Agent + AppRole auto-auth + templating](vault-professional-cert/lab-03-vault-agent-approle-templating.md)
  `runbook` `certification` `professional`
  <details>
  <summary>Details</summary>

  - Hands-on runbook for configuring Vault Agent with AppRole auto-auth, validating `secret_id` retention, and rendering a template with dynamic KV v2 secrets.
  </details>

- [Lab 4: Performance replication with path filtering](vault-professional-cert/lab-04-pr-replication-path-filtering.md)
  `runbook` `certification` `professional`
  <details>
  <summary>Details</summary>

  - Practical PR setup and verification flow focused on primary/secondary behavior and path filter validation.
  </details>

- [Lab 5: Policies, namespaces, and KV v2 operations](vault-professional-cert/lab-05-policy-kvv2-namespaces.md)
  `runbook` `certification` `professional`
  <details>
  <summary>Details</summary>

  - Traditional runbook to practice namespace-aware login context, policy inheritance boundaries, and KV v2 path precision tests.
  </details>
