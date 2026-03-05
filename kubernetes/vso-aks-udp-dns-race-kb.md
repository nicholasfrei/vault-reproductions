# VSO KB: Intermittent DNS `i/o timeout` in AKS (UDP Conntrack Race)

## Overview

This KB documents an AKS-specific behavior where Vault Secrets Operator (VSO) intermittently fails DNS lookups during secret refresh, even though initial reconciliation succeeds. This was a ticket where the customer was facing issues with all of their application pods losing connectivity to Vault after a certain period of time, and the root cause was traced back to VSO DNS timeouts due to AKS UDP conntrack behavior.

Observed errors in VSO logs looked like this:

```text
dial tcp: lookup hvst.test.net on <IP_ADDR>:53:
read udp <pod-ip>:<src-port>-><IP_ADDR>:53: i/o timeout
```

In the case, this impacted Vault API calls made by VSO (secret reads, auth/login flows, and status-related calls) after VSO had been idle between refresh windows. Their intial configuration was set to refresh secrets every `300s`, and they observed that after about 5 minutes of idle time, the next refresh would trigger these DNS timeout errors. Restarting the VSO pod would temporarily clear the issue, but it would return after another idle period and subsequent refresh attempt.

## Problem Statement

- VSO initializes and syncs secrets successfully on first reconcile.
- Later refresh cycles intermittently fail with DNS UDP timeout errors to CoreDNS/KubeDNS service IP (`:53`).
- Restarting the VSO pod temporarily clears the issue.
- Failures reappear after idle time and subsequent refresh attempts.

## Environment Pattern

- VSO version: `0.10.0`
- Platform: AKS (Azure Kubernetes Service)
- Vault and VSO deployed in separate AKS clusters (same Azure network boundary)
- `VaultStaticSecret` refresh interval initially set to around `300s`
- High concurrent reconcile behavior observed (`worker count: 100` in logs)
  - this was not related to the root cause, but just wanted to call this out

## Key Indicators in Logs

1. VSO starts and reconciles resources successfully.
2. VSO caching client is reused across secrets (`Got client from cache` with same client ID).
3. Intermittent DNS failures appear on later refreshes:

```text
Failed to read Vault secret: Get "https://hvst.test.net:8200/v1/secret/data/...":
dial tcp: lookup hvst.test.net on <IP_ADDR>:53:
read udp 172.28.66.243:57308-><IP_ADDR>:53: i/o timeout
```

4. Restarting VSO removes errors temporarily, then errors return after idle/refresh cycles.

## Root Cause Hypothesis

This behavior is consistent with the AKS UDP conntrack race/aging pattern for DNS traffic:

- DNS uses UDP by default.
- After idle periods, UDP conntrack entries may expire.
- A subsequent lookup can be dropped or timed out in the networking path.
- VSO then surfaces lookup failures as Vault client errors.

This is primarily a Kubernetes/Azure networking behavior, not a Vault API/path correctness issue.

## Validation Steps

Use this sequence to confirm scope quickly:

1. Confirm VSO can reconcile immediately after pod restart:

```bash
kubectl rollout restart deploy/vault-secrets-operator-controller-manager -n vso-vault
kubectl logs -n vso-vault deploy/vault-secrets-operator-controller-manager -f
```

2. Confirm DNS timeout signature in events/logs:

```bash
kubectl logs -n vso-vault deploy/vault-secrets-operator-controller-manager \
  | grep -E "lookup .*:53|read udp|VaultClientError"
```

3. Confirm failing endpoint resolves to cluster DNS service IP (example):

```bash
kubectl get svc -n kube-system -l k8s-app=kube-dns -o wide
```

4. Verify errors are intermittent and correlated with refresh windows (not all requests fail continuously).

## Mitigations
Each of these options were provided to the customer. The first option is the most platform-aligned long-term mitigation, and the others are operational workarounds that can be applied immediately while coordinating with the AKS team for the LocalDNS rollout.

### Preferred Platform Mitigation (AKS)

Enable AKS LocalDNS per Microsoft guidance to reduce conntrack pressure/UDP race impact.

- This is the most platform-aligned long-term mitigation.
- Coordinate with the AKS platform/network team.

### Operational Workaround (Validated)

Reduce VSO `refreshAfter` to keep DNS traffic active (for example `30s`).

- In the reported case, reducing to `30s` and restarting VSO pods removed observed timeout errors during monitoring.
- Tradeoff: increased read frequency/load on Vault and Kubernetes.

### Additional Tuning

Reduce VSO reconcile concurrency (for example set `maxConcurrentReconciles` to a small value such as `<5`) to lower burst pressure during refresh windows.

## Expected vs Observed

- **Expected:** VSO refreshes all configured `VaultStaticSecret` objects at each interval without DNS-related errors.
- **Observed:** Initial sync succeeds, but subsequent refresh intervals intermittently fail with UDP DNS timeout errors to CoreDNS IP `:53`.

## Steps taken to diagnose the issue

1. Captured VSO logs around refresh windows to identify error patterns.
2. Confirmed DNS timeout signature in logs (`read udp ... :53: i/o timeout`).
3. Restarted VSO deployment to confirm temporary resolution of errors.
4. Validated that the failing endpoint was the cluster DNS service IP, consistent with AKS UDP conntrack behavior.
5. Reviewed AKS documentation and known issues around DNS and UDP timeouts, confirming alignment with the observed pattern.
6. Provided mitigations based on AKS best practices for DNS reliability.

## References

- [AKS DNS concepts](https://learn.microsoft.com/en-us/azure/aks/dns-concepts)
- [Troubleshoot DNS failures from pod but not from node](https://learn.microsoft.com/en-us/troubleshoot/azure/azure-kubernetes/connectivity/dns/troubleshoot-dns-failure-from-pod-but-not-from-worker-node)
- [Basic troubleshooting for DNS resolution in AKS](https://learn.microsoft.com/en-us/troubleshoot/azure/azure-kubernetes/connectivity/dns/basic-troubleshooting-dns-resolution-problems)
- [Kubernetes issue discussing UDP conntrack DNS behavior](https://github.com/kubernetes/kubernetes/issues/56903)