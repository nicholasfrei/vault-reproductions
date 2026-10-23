# Oracle database labs

Start with [Oracle on EC2: reusable setup](oracle-ec2-setup-runbook.md) to provision Vault, Oracle XE, and 100 static plus 100 dynamic-role definitions. Set the Vault/plugin versions and population in Terraform before creating the lab.

`lab/` is the single shared golden-baseline implementation: one Vault node by default, or three Raft voters when `vault_node_count = 3` is set. Issue-specific Terraform roots supply their investigation's special conditions.

Legend: `runbook` = ordered procedure, `kb` = explanation and diagnosis, `repro` = focused issue or behavior, `guide` = teaching walkthrough, `script` = executable helper. Purpose tags distinguish reusable `setup` from an `issue` investigation or `reference`.

## Build a healthy integration

- [Oracle on EC2 setup runbook](oracle-ec2-setup-runbook.md)
  `runbook` `setup` `oracle` `ec2`
  <details>
  <summary>Details</summary>

  - Terraform provisions one or three persistent Vault Raft nodes with AWS KMS auto-unseal. Oracle runs on node 1; every Vault node receives Instant Client and the selected Enterprise Oracle plugin.
  - Defaults to 100 Oracle static users and matching Vault static roles, plus 100 dynamic-role definitions. Bootstrap checks real Oracle logins, a manual static rotation, and dynamic issuance/revocation.
  - [Terraform](lab/terraform/) and [guest scripts](lab/scripts/) own this baseline. Runtime validation is pending; see the runbook's verification record.
  </details>

## Investigate specific issues

- [Self-managed static-role rotation requiring REPLACE](alter-vs-replace/oracle-rotate-requires-replace-repro.md)
  `repro` `issue` `oracle`
  <details>
  <summary>Details</summary>

  - Investigates `ORA-28221` with a restricted account, a password-verification profile, and a `self_managed=true` connection.
  - Its current fixture includes dev-server candidate-plugin signing. The shared baseline's administrator-managed static roles do not establish this trigger; see the reuse boundary below.
  </details>

- [Automatic rotation resource-growth investigation](automated-rotation-leak/oracle-static-role-goroutine-fd-leak-runbook.md)
  `runbook` `issue` `oracle`
  <details>
  <summary>Details</summary>

  - Records healthy rotations before explicitly blocking Oracle traffic and observing resource growth.
  - The existing fixture owns its bridge-network fault, ten-second rotation settings, and monitoring services. These are investigation conditions, rather than baseline defaults.
  </details>

- [Oracle plugin callback resource-growth explanation](automated-rotation-leak/oracle-database-updateuser-initialize-goroutine-fd-leak-kb.md)
  `kb` `reference` `oracle`
  <details>
  <summary>Details</summary>

  - Explains callback cleanup, failed initialization, and retry amplification; records the evidence and limitations of the investigation.
  </details>

## Learn external-plugin installation

- [Install the external Oracle database plugin](plugin-installation/oracle-external-plugin-installation-guide.md)
  `guide` `learning` `oracle` `external-plugin`
  <details>
  <summary>Details</summary>

  - Explicit host-level Instant Client installation, complete Enterprise plugin archive layout, and Vault catalog registration commands.
  - Covers manual installation and Vault-managed downloads, multi-node prerequisites, a connection/credential check, and common installation errors.
  </details>

## Reuse boundary

The setup runbook's handoff is a reachable Oracle `XEPDB1`, an installed plugin, and a healthy administrator-managed connection at `oracle-db/config/oracle`. Use separate mounts, connection names, and Oracle usernames for a scenario's additional fixtures.

For a REPLACE investigation, select the required Vault/plugin pair before provisioning, then add the restricted accounts/profile and a separate self-managed connection. The existing REPLACE runbook assumes its own paths and dev-server signing configuration; jumping directly to its reproduction or custom-plugin steps on this persistent baseline is not a drop-in workflow.

Similarly, the resource-growth investigation's fixed Docker bridge address and fault-service names belong to its own fixture. Adapt and verify those prerequisites before applying its fault sequence to another deployment.

Versions are configurable setup inputs, not affected/fixed-version claims. Keep an investigation's evidence and trigger separate from healthy provisioning.
