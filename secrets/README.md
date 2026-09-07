# Secrets

Vault secrets engines: database, KV, LDAP, PKI, transit, TOTP, AWS, and Artifactory.

Lab prerequisites are in the [root README](../README.md). Confirmed version-specific defects are in [KNOWN_BUGS.md](../KNOWN_BUGS.md).

Legend: `runbook` = procedural, `kb` = break-fix analysis, `repro` = focused behavior demo, `guide` = broader walkthrough, `script` = executable is the primary deliverable.

## <img src="https://cdn.simpleicons.org/jfrog" alt="JFrog" width="18" /> Artifactory

- [Artifactory Plugin Registration Script](artifactory/artifactory-plugin-registration.sh)
  `script` `secrets` `artifactory`
  <details>
  <summary>Details</summary>

  - Amazon Linux setup script for Vault Enterprise + JFrog Artifactory secrets plugin registration.
  - Includes plugin checksum validation and flattened plugin directory layout to avoid execution path errors.
  </details>

## <img src="https://icons.veryicon.com/png/o/application/awesome-common-free-open-source-icon/aws-12.png" alt="AWS" width="18" /> AWS

- [AWS Secrets Engine Upgrade Findings KB](aws/aws-secrets-engine-upgrade-findings-kb.md)
  `kb` `secrets` `aws`
  <details>
  <summary>Details</summary>

  - Discusses real-life errors faced by enterprise customers found in v1.19.x for `sts_endpoint`, `iam_endpoint`, and rotation schedule/window(s).
  </details>

## Database

- [Oracle Database Secrets Engine Repro](database/oracle-db/oracle-database-secrets-engine-repro.md)
  `repro` `secrets` `database`
  <details>
  <summary>Details</summary>

  - Rapid Oracle environment setup for testing Vault database plugin behavior with dynamic and static credentials.
  </details>

- [PostgreSQL Database Secrets Engine Repro](database/postgresql-db/postgresql-database-secrets-engine-repro.md)
  `repro` `secrets` `database`
  <details>
  <summary>Details</summary>

  - PostgreSQL + Vault database secrets engine setup covering dynamic credentials, static role rotation, and custom password policies.
  - Useful for validating credential lifecycle, lease revocation, and rotation timing behavior.
  </details>

- [PostgreSQL Static Role Denial of Service Repro](database/postgresql-db/postgresql-static-role-denial-of-service-repro.md)
  `repro` `secrets` `database`
  <details>
  <summary>Details</summary>

  - Reproduces static role rotation pressure when the backing PostgreSQL target is unavailable or decommissioned.
  - Useful for incident response drills and understanding cleanup/recovery patterns for stale static roles.
  </details>

- [RabbitMQ Secrets Engine Repro](database/rabbitmq-db/rabbitmq-secrets-engine-repro.md)
  `repro` `secrets` `database`
  <details>
  <summary>Details</summary>

  - Simple RabbitMQ + Vault secrets engine runbook for dynamic credential issuance and lease revocation validation.
  - Assumes an already-operational Vault cluster in Kubernetes and uses a local RabbitMQ container for testing.
  </details>

- [AppRole + Snowflake Database Secrets Engine Runbook](database/snowflake-db/approle-snowflake-db-runbook.md)
  `runbook` `secrets` `database`
  <details>
  <summary>Details</summary>

  - End-to-end setup for Vault database secrets engine with Snowflake using RSA key-pair authentication and static role rotation.
  - Covers Snowflake service account creation, AppRole auth configuration, credential rotation verification, and optional SnowSQL connection validation.
  </details>

- [vault_database_secret_backend_role Partial Update Payload Repro](database/snowflake-db/vault-db-role-update-partial-payload-repro.md)
  `repro` `secrets` `database` `terraform`
  <details>
  <summary>Details</summary>

  - Reproduces the Terraform Vault provider bug (5.8.0–5.10.1) where `vault_database_secret_backend_role` Update only sends changed fields in the API payload.
  - On Vault 2.0.x (full-replace endpoint), omitted fields are silently reset to zero values: `credential_type` reverts from `rsa_private_key` to `password`, TTLs reset to `0s`, and statement fields are cleared.
  - See [hashicorp/terraform-provider-vault#2966](https://github.com/hashicorp/terraform-provider-vault/issues/2966) for the upstream issue.
  </details>

## <img src="https://cdn.simpleicons.org/vault" alt="Vault" width="18" /> KV

- [KV v1 Secret Recovery Runbook](kv/kv-v1-secret-recovery-runbook.md)
  `runbook` `secrets` `kv`
  <details>
  <summary>Details</summary>

  - Step-by-step reproduction for Vault Enterprise secret recovery using a loaded Raft snapshot.
  - Covers secret deletion/overwrite simulation, snapshot load status checks, `vault recover`, and cleanup.
  </details>

- [KV v2 Soft-Delete, Destroy, Undelete, and Recovery Runbook](kv/kv-v2-soft-delete-destroy-undelete-recovery-runbook.md)
  `runbook` `secrets` `kv`
  <details>
  <summary>Details</summary>

  - Step-by-step lifecycle validation for KV v2 versioned secrets.
  - Covers soft-delete, undelete, permanent destroy behavior, optional metadata delete, and cleanup.
  </details>

- [KV Path Migration Runbook (Same Mount)](kv/kv-path-migration-runbook.md)
  `runbook` `secrets` `kv`
  <details>
  <summary>Details</summary>

  - Instructions on how to copy a folder subtree and all secrets to a new path within the same KV mount.
  - Includes a recursive script, dry-run mode, validation checks, and cleanup guidance.
  - Clarifies when to use replication/snapshots versus manual copy and notes metadata/version-history limitations.
  </details>

## <img src="https://icons.veryicon.com/png/o/business/cloud-desktop/personal-ldap.png" alt="OpenLDAP" width="18" /> LDAP

- [LDAP Secrets Engine Setup Repro](ldap/setup-ldap-secrets-engine-repro.md)
  `repro` `secrets` `ldap`
  <details>
  <summary>Details</summary>

  - OpenLDAP + Vault LDAP secrets engine setup focused on bind account and static-role password rotation timing.
  - Uses [ldap/openldap-deployment.yaml](ldap/openldap-deployment.yaml) as the backing Kubernetes manifest.
  </details>

- [LDAP UI Capabilities Self Bug Repro](ldap/ldap-ui-capabilities-self-bug.md)
  `repro` `secrets` `ldap`
  <details>
  <summary>Details</summary>

  - Reproduces a Vault UI regression where the LDAP library set `check-out` action is visible in `1.20.4`, missing in `1.20.7` through `1.20.10` and `1.21.5`, and restored in `2.0.0`.
  - Includes OpenLDAP container setup, scoped policy creation, UI navigation steps, and version-specific screenshots.
  </details>

- [RHDS + Vault LDAP Secrets Engine Reproduction](ldap/red-hat-directory-server/rhds-ldap-integration-repro.md)
  `repro` `secrets` `ldap`
  <details>
  <summary>Details</summary>

  - End-to-end reproduction using 389 Directory Server (open source RHDS equivalent) with the Vault LDAP secrets engine on Vault 1.16.7.
  - Covers static-role creation for 10 pre-existing LDAP users, automatic and manual `rotate-role` validation, and `rotate-root` bind-account rotation.
  </details>

- [LDAP Dynamic Role Uppercase Name Bug Repro](ldap/ldap-dynamic-role-uppercase-bug-repro.md)
  `repro` `secrets` `ldap`
  <details>
  <summary>Details</summary>

  - Reproduces a bug where LDAP dynamic roles created with uppercase names appear in `vault list` but fail on `vault read`, `vault delete`, and credential generation.
  - Demonstrates orphaned metadata accumulation that cannot be removed via normal CLI operations.
  - Static roles are not affected; only dynamic roles at `ldap/role/` exhibit this behavior.
  </details>

## <img src="https://cdn.simpleicons.org/letsencrypt" alt="PKI" width="18" /> PKI

- [CMPv2 PKI Integration Guide](pki/cmpv2/cmpv2-pki-integration-guide.md)
  `guide` `secrets` `pki`
  <details>
  <summary>Details</summary>

  - Markdown-only runbook for Vault PKI CMPv2 integration and proxy behavior validation.
  - Includes concrete expected output blocks from a successful direct + proxied CMP IR repro.
  </details>

- [Vault Proxy TLS Behavior Repro](pki/cmpv2/vault-proxy-tls-behavior-repro.md)
  `repro` `secrets` `pki`
  <details>
  <summary>Details</summary>

  - Reproduces HTTP client traffic into a local proxy with TLS-only Vault upstream.
  - Validates that Vault can stay TLS-only while a front proxy handles plaintext listener and HTTPS re-encryption.
  </details>

- [CMPv2 Sentinel Nil Map Panic Repro](pki/cmpv2/cmpv2-sentinel-nil-map-panic-repro.md)
  `repro` `secrets` `pki` `cmpv2` `enterprise`
  <details>
  <summary>Details</summary>

  - Reproduces a server panic (`assignment to entry in nil map`) triggered by submitting a CMP CR with an empty `SEQUENCE OF CertReqMessages` body when `enable_sentinel_parsing=true`.
  - Includes a Go payload generator, full setup of mock origin PKI and cert auth, and the exact stack trace confirming the `path_cmpv2_ent.go` code path.
  </details>

## TOTP

- [TOTP Secrets Engine Repro](totp/totp-secrets-engine-repro.md)
  `repro` `secrets` `totp`
  <details>
  <summary>Details</summary>

  - Reproduction runbook for the Vault TOTP secrets engine, including setup and validation flow.
  </details>

## Transit

- [Transit CSR Re-Signing Drops Extension Critical Flag](transit/transit-csr-extension-drop-repro.md)
  `repro` `secrets` `transit` `pki`
  <details>
  <summary>Details</summary>

  - Reproduces the bug where `POST /transit/keys/:name/csr` silently strips the `Critical` flag from custom X.509 extensions in the re-signed output CSR.
  - When SANs and additional extensions are both present, the re-signed CSR is structurally invalid (malformed ASN.1) and rejected by downstream tools.
  - Covers root cause (stale `Attributes` field and duplicate SAN extension), affected versions (through `2.0.4`), and fix validation.
  </details>
