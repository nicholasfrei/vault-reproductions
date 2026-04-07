# KB: Circular Transit Auto-Unseal Dependency (Double Transit)

## Overview

This KB documents an anonymized support case where two Vault clusters were configured to transit auto-unseal each other. During recovery-site testing, the design created a circular dependency where neither cluster could unseal first.

Impact risk: full site recovery can stall because both clusters remain sealed and unavailable until an independent unseal root is introduced.

## Problem Statement

The anti-pattern is:

- Cluster A uses `seal "transit"` and points to Cluster B.
- Cluster B uses `seal "transit"` and points to Cluster A.

In a simultaneous restart or disaster recovery event, both clusters need the other cluster to be unsealed first, which is impossible.

## Case Context

- A customer opened a support case while testing recovery-site restore workflows.
- They provided configs showing Cluster A transit-sealed by Cluster B, and Cluster B transit-sealed by Cluster A.
- The issue was discovered during DR validation (not day-to-day steady state).
- The customer was unable to unseal the clusters using the transit auto-unseal configuration.
- The agreed remediation was to deploy a new standalone Vault cluster with independent unseal (Shamir), then use that cluster as the transit unseal root for the existing clusters.

## Why This Design Is Risky

1. Circular startup deadlock: no first cluster can unseal.
2. Recovery procedures become non-deterministic during full restart scenarios.
3. Outage blast radius increases because both clusters can become unavailable at the same time.
4. DR tests may pass in partial-failure situations but fail in full-site recovery events.

## Configuration Pattern That Causes the Issue

Example of circular dependency:

```hcl
# Cluster A
seal "transit" {
  address = "http://<cluster-b-host>:8200"
  token = "<token>"
  key_name = "key-a"
  mount_path = "transit/"
}
```

```hcl
# Cluster B
seal "transit" {
  address = "http://<cluster-a-host>:8200"
  token = "<token>"
  key_name = "key-b"
  mount_path = "transit/"
}
```

## Key Indicators (Symptoms and Logs)

Symptoms:

- Both clusters report `Sealed: true` after restart/recovery.
- Neither cluster can serve API requests that require unsealed state.
- Manual sequencing attempts fail because each side depends on the other side first.

Common operational evidence:

- Repeated transit seal retries to the peer cluster endpoint.
- Transport errors against the peer transit address (for example connection refused or timeout).
- Persistent sealed state in `vault status`.

Check status on each cluster:

```bash
export VAULT_ADDR=http://<cluster-a-host>:8200
vault status

export VAULT_ADDR=http://<cluster-b-host>:8200
vault status
```

Collect recent Vault logs for seal-related errors:

```bash
journalctl -u vault --since "30 min ago" | rg -i "seal|transit|unseal|retry|error"
```

## Root Cause Hypothesis

Transit auto-unseal requires an available upstream transit service at startup. In this topology, each cluster is both dependent and depended-on. During a full recovery event, both dependencies are unavailable at the same time, so unseal cannot proceed on either side.

## Remediation

Break the loop by introducing an independent unseal root.

Recommended implementation pattern:

1. Deploy a standalone Vault cluster with independent unseal (for example Shamir).
2. Enable transit on the standalone cluster and create dedicated transit keys.
3. Update Cluster A and Cluster B to use the standalone cluster in their `seal "transit"` stanza.
4. Restart one cluster at a time and verify each unseals via the standalone transit service.
5. Re-run DR simulation with simultaneous restart to validate no circular dependency remains.

Minimal transit seal target example after remediation:

```hcl
seal "transit" {
  address = "http://<independent-transit-cluster>:8200"
  token = "<token>"
  key_name = "<unseal-key>"
  mount_path = "transit/"
}
```

## Post-Change Validation

Run these checks after updating both clusters:

```bash
export VAULT_ADDR=http://<cluster-a-host>:8200
vault status

export VAULT_ADDR=http://<cluster-b-host>:8200
vault status
```

Expected outcome:

- Cluster A and Cluster B report `Sealed: false` after restart.
- No dependency on each other for unseal.
- DR test with full simultaneous restart succeeds.

## References

- [Transit Seal Configuration](https://developer.hashicorp.com/vault/docs/configuration/seal/transit)
- [Transit Seal Best Practices](https://developer.hashicorp.com/vault/docs/configuration/seal/transit-best-practices)
