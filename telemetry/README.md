# Telemetry

Vault metrics, Prometheus, and Grafana.

Lab prerequisites are in the [root README](../README.md). Confirmed version-specific defects are in [KNOWN_BUGS.md](../KNOWN_BUGS.md).

Legend: `runbook` = procedural, `kb` = break-fix analysis, `repro` = focused behavior demo, `guide` = broader walkthrough, `script` = executable is the primary deliverable.

- [Vault Telemetry Grafana Repro](vault-telemetry-grafana-repro.md)
  `repro` `telemetry` `grafana`
  <details>
  <summary>Details</summary>

  - Configures Vault telemetry with Prometheus scraping and a local Grafana dashboard using `kube-prometheus-stack`.
  - Includes end-to-end setup and validation steps for metrics targets, Prometheus queries, and Grafana access.
  </details>

- [Prometheus Negative Counter Panic (VAULT-46830)](prometheus-negative-counter-panic-kb.md)
  `kb` `telemetry` `prometheus` `panic` `enterprise`
  <details>
  <summary>Details</summary>

  - Explains the `panic: counter cannot decrease in value` startup crash when Prometheus telemetry is enabled from Vault through armon/go-metrics to prometheus/client_golang.
  - Surveys every non-literal `IncrCounter` call site in vault-enterprise with a negative-value assessment for each.
  - Includes a self-contained Go program that reproduces the panic using the exact library versions Vault 1.19.8-ent ships, with no cluster required.
  </details>
