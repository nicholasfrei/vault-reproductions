# Kubernetes

Vault on Kubernetes: CSI provider, Vault Secrets Operator, probes, and Raft quorum recovery.

Lab prerequisites are in the [root README](../README.md). Confirmed version-specific defects are in [KNOWN_BUGS.md](../KNOWN_BUGS.md).

Legend: `runbook` = procedural, `kb` = break-fix analysis, `repro` = focused behavior demo, `guide` = broader walkthrough, `script` = executable is the primary deliverable.

## Kubernetes

- [Liveness Probe KB](liveness-probe-kb.md)
  `kb` `kubernetes` `probes`
  <details>
  <summary>Details</summary>

  - Demonstrates automatic Vault pod recovery when TLS certificates expire, using Kubernetes liveness probes.
  </details>

- [Vault Raft Quorum Break and Restore Runbook](vault-raft-quorum-break-and-restore-runbook.md)
  `runbook` `kubernetes` `raft`
  <details>
  <summary>Details</summary>

  - Reproduces quorum-loss by scaling a Vault StatefulSet down to one pod, then restores service with single-node raft peer recovery and scale-out validation.
  </details>

## <img src="https://cdn.simpleicons.org/kubernetes" alt="Kubernetes" width="18" /> Vault CSI Provider

- [Vault CSI Provider TLS CA Bundle Runbook](vault-csi-provider/vault-csi-provider-tls-ca-bundle-runbook.md)
  `runbook` `kubernetes` `csi`
  <details>
  <summary>Details</summary>

  - Reproduces and fixes CSI login failures caused by an untrusted Vault TLS issuer.
  - Shows how to mount the CA bundle into both the CSI provider and the Vault Agent sidecar, then align `SecretProviderClass` with `vaultCACertPath`.
  </details>

## <img src="https://cdn.simpleicons.org/kubernetes" alt="Kubernetes" width="18" /> VSO K8s Auth Static Dynamic

- [VSO Kubernetes Auth Static and Dynamic Repro](vso-k8s-auth-static-dynamic/vso-k8s-auth-static-dynamic-repro.md)
  `repro` `kubernetes` `vso`
  <details>
  <summary>Details</summary>

  - Reproduces Vault Secrets Operator sync flows for static KV v2 secrets and dynamic database credentials using Vault Kubernetes authentication.
  - Includes policy and role setup, secret rotation verification, and failure injection by breaking/restoring Kubernetes auth role bindings.
  </details>

- [VSO Special Character Secret Keys KB](vso-special-character-secret-keys-kb.md)
  `kb` `kubernetes` `vso`
  <details>
  <summary>Details</summary>

  - Documents VSO sync failures when KV keys include Kubernetes-invalid characters such as `@`.
  - Includes a runnable repro, expected vs observed behavior, and workaround/architecture guidance.
  </details>

- [VSO AKS UDP DNS Race KB](vso-aks-udp-dns-race-kb.md)
  `kb` `kubernetes` `vso`
  <details>
  <summary>Details</summary>

  - Documents intermittent VSO DNS timeout failures in AKS (`read udp ... :53: i/o timeout`) after initial successful reconciles. This was a customer incident where all application pods lost connectivity to Vault after a certain period of time, and the root cause was traced back to VSO DNS timeouts due to AKS UDP conntrack behavior.
  - Covers UDP conntrack race hypothesis, validation commands, and mitigations (LocalDNS and/or shorter refresh intervals).
  </details>
