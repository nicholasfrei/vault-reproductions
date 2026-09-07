# Setup

Local lab bootstrap and teardown for the scenarios in this repository.

Lab prerequisites are in the [root README](../README.md). Confirmed version-specific defects are in [KNOWN_BUGS.md](../KNOWN_BUGS.md).

Legend: `runbook` = procedural, `kb` = break-fix analysis, `repro` = focused behavior demo, `guide` = broader walkthrough, `script` = executable is the primary deliverable.

- [Vault Cluster Init Script](k8s/init.sh)
  `script` `setup` `cluster`
  <details>
  <summary>Details</summary>

  - Installs Vault via Helm (HA + Raft, 3 pods), initializes with 5 total key shares and threshold 3, saves init output to `setup/k8s/init.json`, unseals all nodes, and logs into `vault-0` with the root token.
  </details>

- [Vault PGP Key Setup Script](k8s/setup-pgp-keys-for-vault.sh)
  `script` `setup` `pgp`
  <details>
  <summary>Details</summary>

  - Generates PGP key pairs, copies public keys into the Vault pod, and runs `vault operator init` with PGP-encrypted unseal keys. Targets `vault-0` in namespace `vault` (configurable).
  </details>

- [Vault Sandbox Cleanup Script](k8s/cleanup.sh)
  `script` `setup` `cleanup`
  <details>
  <summary>Details</summary>

  - Cleans up sandbox state between runs: uninstalls the Vault Helm release, deletes the `vault` namespace, deletes the Minikube `vault` profile, and removes `setup/k8s/init.json`.
  </details>

## AWS

Terraform for a single Vault Enterprise node on EC2 lives in [setup/aws](aws/README.md).
