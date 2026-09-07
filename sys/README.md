# System Backend

System backend (`sys/`): health, policies, plugins, raft, replication, seal, migrate, billing, sync, SCIM, and UI.

Lab prerequisites are in the [root README](../README.md). Confirmed version-specific defects are in [KNOWN_BUGS.md](../KNOWN_BUGS.md).

Legend: `runbook` = procedural, `kb` = break-fix analysis, `repro` = focused behavior demo, `guide` = broader walkthrough, `script` = executable is the primary deliverable.

## Health

- [sys/health Best Practices KB](health/sys-health-best-practices-kb.md)
  `kb` `sys` `health`
  <details>
  <summary>Details</summary>

  - Covers how `sys/health` status codes and query parameters work, including `standbycode`, `performancestandbycode`, `drsecondarycode`, and the boolean `standbyok`/`perfstandbyok` flags.
  </details>

- [Consul Health Check Misconfiguration with `sys/health`](health/consul-health-check-misconfiguration-kb.md)
  `kb` `sys` `health` `consul` `replication`
  <details>
  <summary>Details</summary>

  - Documents a production incident where `standbycode=503` in a static Consul health check removed all performance standbys from the load balancer pool during an election, concentrating ~7× baseline traffic onto the new active node.
  - Covers the lease restoration gate that blocked standbys from re-promoting to performance standby, the resulting audit sink timeout cascade (`event not processed by enough sink nodes`), and how the two factors extended the outage beyond a normal election window.
  </details>

- [AWS Auto Scaling Runbook for Vault `sys/health`](health/aws-asg-sys-health-runbook.md)
  `runbook` `sys` `health`
  <details>
  <summary>Details</summary>

  - Step-by-step AWS CLI runbook to create an ALB target group and Auto Scaling Group using Vault `sys/health` endpoint checks for automated unhealthy-instance replacement.
  </details>

## Policies

- [Sentinel EGP and RGP Governing Policies KB](policies/sentinel-egp-rgp-governing-policies-kb.md)
  `kb` `sys` `policies`
  <details>
  <summary>Details</summary>

  - Break-fix KB for understanding and validating Sentinel Endpoint Governing Policies (EGP) and Role Governing Policies (RGP).
  - Includes practical policy examples, denial signatures, and validation/cleanup commands.
  </details>

- [Priority Matching in ACL Policies KB](policies/priority-matching-policies-kb.md)
  `kb` `sys` `policies`
  <details>
  <summary>Details</summary>

  - Actionable KB explaining how Vault determines the winning path when multiple policies match a request.
  - Covers capability union vs. exact-match priority rules, namespace expansion, and common wild-card pitfalls.
  </details>

- [Control Group Missing Audit Response Repro](policies/control-group-missing-audit-response-repro.md)
  `repro` `sys` `policies` `control-group` `audit` `enterprise`
  <details>
  <summary>Details</summary>

  - Reproduces the bug where a control-group-blocked request writes an audit `request` entry but never writes the corresponding `response` entry.
  - The missing response means the wrapped token accessor, caller HMAC'd token, TTL, and creation path are never logged, making it impossible to link an authorisation to the request that triggered it.
  - Uses userpass auth, KV v2, and a two-user (bob/alice) setup to trigger and verify the missing log entry.
  </details>

## Plugins

- [`vault plugin reload -mounts` Fails in the Root Namespace Repro](plugins/plugin-reload-mounts-root-namespace-repro.md)
  `repro` `sys` `plugins`
  <details>
  <summary>Details</summary>

  - Reproduces a confirmed bug where `vault plugin reload -mounts=<mount>` fails with a `404 unsupported path` error when run in the root namespace, because the CLI routes the request to the wrong API (`sys/plugins/reload/:type/:name` instead of `sys/plugins/reload/backend`) whenever no client namespace is set.
  - Affects both Vault CE and Vault Enterprise from `v1.16.0`/`v1.16.0+ent` through `2.1.0`/`2.1.0+ent`.
  - Covers two confirmed workarounds (direct API call to `sys/plugins/reload/backend`, and setting `VAULT_NAMESPACE` to any non-empty value), plus how to positively confirm a reload took effect via `-scope=global` + `vault plugin reload-status`
  </details>

## Raw

- [Vault sys/raw Endpoint KB](raw/sys-raw-kb.md)
  `kb` `sys` `raw`
  <details>
  <summary>Details</summary>

  - KB for working with Vault's raw storage endpoint safely and understanding when it is appropriate to use it.
  - Includes background on `raw_storage_endpoint`, example raw reads, and cautions about bypassing normal validation.
  </details>

- [Vault sys/raw Inspector Script](raw/sys-raw-inspector.sh)
  `script` `sys` `raw`
  <details>
  <summary>Details</summary>

  - Bash utility for walking logical/auth storage under `/sys/raw` and exporting an ASCII tree.
  - Includes recursive search mode for locating UUIDs or other strings inside raw storage responses without using Python.
  </details>

## Replication

- [Vault Enterprise Replication Runbook (PR + DR)](replication/vault-enterprise-replication-pr-dr-runbook.md)
  `runbook` `sys` `replication`
  <details>
  <summary>Details</summary>

  - Troubleshooting guide for already-configured Performance Replication and Disaster Recovery replication clusters.
  - Covers merkle sync/diff issues, failover/failback commands, and merkle corruption remediations.
  </details>

- [Vault Enterprise PR and DR Replication Lab Runbook](replication/performance/vault-pr-dr-replication-lab-runbook.md)
  `runbook` `sys` `replication`
  <details>
  <summary>Details</summary>

  - Deploys a nine-node Vault Enterprise lab across three Raft clusters (primary, PR secondary, DR secondary) with AWS KMS auto-unseal.
  - Enables performance and DR replication and validates replication state on all three clusters.
  </details>

- [Merkle Corruption Reindex KB](replication/vault-replication-merkle-corruption-reindex-kb.md)
  `kb` `sys` `replication`
  <details>
  <summary>Details</summary>

  - KB for resolving PR/DR replication stuck in `merkle-diff`/`merkle-sync` due to corrupted primary merkle trees.
  - Covers primary-first reindex strategy, write-lock expectations, validation checkpoints, and rollback cautions.
  </details>

- [Logshipper Buffer vs. `trailing_logs` — Replication vs. HA Lag KB](replication/logshipper-vs-trailing-logs-kb.md)
  `kb` `sys` `replication` `raft` `enterprise`
  <details>
  <summary>Details</summary>

  - Explains the architectural distinction between `trailing_logs` (intracluster Raft HA) and `logshipper_buffer_length` (intercluster Enterprise replication WAL shipping).
  - Covers failure modes, lag diagnosis via `sys/replication/status`, and tuning recommendations for both parameters.
  </details>

## Migrate

- [`vault operator migrate -start` Incompatibility with Raft Destination KB](migrate/operator-migrate-raft-start-kb.md)
  `kb` `sys` `migrate` `raft` `storage`
  <details>
  <summary>Details</summary>

  - Documents the confirmed bug where `vault operator migrate -start` always fails when the destination is integrated storage (Raft), with error `error bootstrapping cluster: cluster already has state`.
  - Provides a two-phase workaround: PostgreSQL → `file` (resumable with `-start`) → `raft` (single complete pass).
  - References GitHub issues #11026 and #10769.
  </details>

## Raft

- [Performance Secondary Raft Snapshot Loop — High Lease Volume KB](raft/raft-snapshot-loop-high-lease-volume-kb.md)
  `kb` `sys` `raft` `enterprise`
  <details>
  <summary>Details</summary>

  - Documents a real incident where a follower node on a performance secondary cluster entered a permanent Raft snapshot loop due to extreme memory pressure and 6M+ active leases.
  - Covers triage path (ruling out intercluster replication, confirming intracluster Raft lag), why a clean node rejoin did not break the loop, and the role of `trailing_logs` tuning as a preventive measure.
  - Includes observed metrics: 40 GB `vault.db`, 1.5-hour snapshot cycles, 175k index lag, and sustained 90%+ RAM utilization with 10+ GB swap.
  </details>

- [`vault recover` Panic on Missing Path Argument Repro](raft/recover-no-path-panic-repro.md)
  `repro` `sys` `raft` `enterprise` `recover` `snapshot`
  <details>
  <summary>Details</summary>

  - Reproduces a panic (`index out of range [0] with length 0`) in `vault recover` when `-snapshot-id` is supplied but no path argument is provided on Vault Enterprise `2.0.3+ent`.
  - Demonstrates that the same command with an invalid path returns a clean `400` error, confirming the missing input-validation guard on the no-path code path.
  - Covers snapshot load, the panicking invocation, the structured-error comparison, and cleanup.
  </details>

## Rotate

- [Vault Encryption Key Rotation + Rekey Runbook](rotate/vault-encryption-key-rotation-and-rekey-runbook.md)
  `runbook` `sys` `rotate`
  <details>
  <summary>Details</summary>

  - Step-by-step runbook for rotating the Vault encryption key term (`sys/rotate`) and rekeying Shamir unseal shares (`vault operator rekey`).
  - Includes least-privilege policy example, command syntax gotchas, and post-change validation checks.
  </details>

## Seal

### AWSKMS

- [AWS KMS Auto-Unseal Runbook (EC2 + Vault Enterprise)](seal/awskms/awskms-auto-unseal-runbook.md)
  `runbook` `sys` `seal`
  <details>
  <summary>Details</summary>

  - Single-node EC2 (Amazon Linux 2023) setup for Vault Enterprise with `awskms` seal and `raft` storage.
  - Includes license setup, systemd service configuration, restart validation, and cleanup guidance.
  </details>

### PKCS11

- [AWS CloudHSM PKCS11 Seal Wrap KV Latency Reproduction Runbook](seal/pkcs11/aws-cloudhsm-pkcs11-sealwrap-kv-latency-runbook.md)
  `runbook` `sys` `seal` `pkcs11` `cloudhsm`
  <details>
  <summary>Details</summary>

  - End-to-end six-node Vault Enterprise lab on Amazon Linux 2023 with AWS CloudHSM PKCS#11 auto-unseal, five Raft voters, and one non-voter.
  - Enables a seal-wrapped KV v2 engine, loads configurable high-volume secrets, and injects CloudHSM network latency with `tc netem` to investigate `POTENTIAL DEADLOCK` logs.
  </details>

### Azure

- [Azure Key Vault Auto-Unseal Runbook (Linux VM + Vault Enterprise)](seal/azure/azurekeyvault-auto-unseal-runbook.md)
  `runbook` `sys` `seal`
  <details>
  <summary>Details</summary>

  - Single-node Azure Ubuntu 22.04 VM setup for Vault Enterprise with `azurekeyvault` seal and `raft` storage.
  - Covers App Registration creation, client secret generation, Key Vault Crypto User role assignment, and seal stanza configuration.
  </details>

- [Azure Key Vault Auto-Unseal: US Gov Cloud Bug (`go-kms-wrapping` ≤ v2.0.14)](seal/azure/azurekeyvault-auto-unseal-gov-cloud.md)
  `kb` `sys` `seal`
  <details>
  <summary>Details</summary>

  - Bug in `go-kms-wrapping` where the Azure AD authentication endpoint is hard-coded to public cloud, causing Vault startup failures for US Government Cloud tenants. Filed as [VAULT-44389](https://hashicorp.atlassian.net/browse/VAULT-44389).
  - Covers two independent issues: an invalid `environment` config value and a hard-coded auth endpoint; both affect US Government Cloud tenants.
  - Affected: all Vault versions using `go-kms-wrapping/wrappers/azurekeyvault/v2` <= v2.0.14; workarounds available.
  </details>

### Transit

- [Transit Auto-Unseal Runbook](seal/transit/transit-auto-unseal-runbook.md)
  `runbook` `sys` `seal`
  <details>
  <summary>Details</summary>

  - Local reproduction for Vault transit-based auto-unseal using two dev servers (transit + auto-unseal).
  - Includes a mock HCL config file (`vault-transit-auto-unseal.hcl`) and step-by-step startup, init, restart, and validation flow.
  </details>

- [KB: Circular Transit Auto-Unseal Dependency (Double Transit)](seal/transit/double-transit-autounseal-dependency-kb.md)
  `kb` `sys` `seal`
  <details>
  <summary>Details</summary>

  - Documents a support case where two Vault clusters were configured to transit-unseal each other.
  </details>

## Billing

- [Consumption Billing KV Walk OOM Repro](billing/consumption-billing-kv-walk-oom-repro.md)
  `repro` `sys` `billing` `kv` `oom`
  <details>
  <summary>Details</summary>

  - Reproduces active-node OOM caused by the unconditional `consumptionBillingMetricsWorker` introduced in Vault 2.0.x, which walks every key in every KV v2 mount every 10 minutes to count secrets for billing metrics.
  - Demonstrates memory growth pattern (flat for 10 minutes, then rapid climb) using a single Vault 2.0.3 node with MySQL/MariaDB storage and `ha_enabled = "true"`.
  - Includes a side-by-side comparison with Vault 1.21.3 where the worker is absent and memory stays flat.
  - Covers the root cause (physical storage cache flooding), the `cache_size` workaround, and the relevant source locations in `consumption_billing.go` and `core_metrics.go`.
  </details>

## Sync

- [Azure KV Secrets Sync `panic: not struct` Repro](sync/azure-kv-secrets-sync-panic-repro.md)
  `repro` `sys` `sync` `azure` `enterprise`
  <details>
  <summary>Details</summary>

  - Reproduces a fatal `panic: not struct` in Vault `1.21.5+ent` triggered by writing a `sys/sync/destinations/azure-kv` destination with `disable_strict_networking=true`.
  - Includes Azure App Registration, Key Vault, and RBAC role setup using the Azure CLI.
  - Covers Secrets Sync activation, KV v2 test data, sync destination creation, association, and validation that the secret appears in Azure Key Vault.
  - Confirms the panic is resolved in `2.0.0+ent`.
  </details>

## UI Login

- [VAULT-40617: UI Default Auth `namespace_path` Canonicalization Repro](ui/login/ui-default-auth-namespace-path-repro.md)
  `repro` `sys` `ui` `enterprise`
  <details>
  <summary>Details</summary>

  - Reproduces `sys/internal/ui/default-auth-methods` returning `data: null` after upgrading from 1.21.1+ent to 2.0.x+ent when a default auth rule was written with `namespace_path=""`.
  - Root cause: `upsertRuleInTxn` normalizes empty `namespace_path` to `"root"` (no trailing slash) on pre-fix releases; fixed lookup paths use `"root/"`, causing a memdb key mismatch on the upgraded binary.
  - Demonstrates that `vault read sys/config/ui/login/default-auth/<name>` (name-based lookup) continues to return data while the unauthenticated UI endpoint returns `data: null`.
  - Uses Terraform to deploy a 3-node Vault 1.21.1+ent Raft cluster with AWS KMS auto-unseal on EC2.
  - Affected: 1.20.0–1.20.7+ent, 1.21.0–1.21.2+ent. Fixed: 1.20.8+ent, 1.21.3+ent, 2.0.0+ent.
  </details>

## SCIM

- [SCIM `unlink-entity` Alias Guardrail Bypass Repro](scim/unlink-entity-alias-guardrail-repro.md)
  `repro` `sys` `scim` `enterprise`
  <details>
  <summary>Details</summary>

  - Reproduces `identity/scim/client/<name>/unlink-entity` stripping the SCIM-managed alias when `remove_memberships=true` is set without `unlink_aliases=true`.
  - The alias flag is documented as an opt-in consent gate but is not enforced; group-membership consent is. Reproduced on `2.2.0-beta1+ent`.
  </details>
