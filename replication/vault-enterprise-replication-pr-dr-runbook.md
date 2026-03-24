## Vault Enterprise Replication Troubleshooting Reference (PR + DR)

### Overview / Objective

This document is meant for troubleshooting Vault Enterprise replication (PR + DR). Use this when PR and/or DR are already configured and you need fast operational commands for:

- health and state checks
- replication lag / WAL backlog review
- `merkle-diff` and `merkle-sync` triage
- merkle corruption detection and recovery direction
- failover/failback command reference during incidents

This includes patterns from real internal support incidents.

---

### Lab Setup

- PR and/or DR replication is already configured between clusters.
- You have operator access (`root` or equivalent replication permissions) on all involved clusters.
- `vault` CLI is available.
- `jq`, `curl`, and `nc` are available for troubleshooting checks.

---

### Quick Command Index

Generic Vault Replication Status
```bash
vault read -format=json sys/replication/status
```

Performance Replication Status
```bash
vault read -format=json sys/replication/performance/status
```

Disaster Recovery Replication Status
```bash
vault read -format=json sys/replication/dr/status
```

Merkle Corruption Check
```bash
vault write -format=json sys/replication/merkle-check
```

Success signals:

```text
mode: primary/secondary as expected
state: running
connection_status: connected
merkle_corruption_report.corrupted_root: false
```

---

### Troubleshooting

#### 1) Symptom: Replication state is not `running` or `connection_status` is disconnected

Likely causes:

- stale/invalid secondary token
- wrong `api_addr` or `cluster_addr`
- TLS trust mismatch for cluster communication
- blocked network path on `8201`

Fix actions:

1. Validate endpoints and network path with `curl` + `nc`.
  - `curl -sk "https://<primary-api-addr>:8200/v1/sys/health"`
  - `curl -sk "https://<secondary-api-addr>:8200/v1/sys/health"`
  - `nc -vz "<primary-cluster-addr>" 8201`
  - `nc -vz "<secondary-cluster-addr>" 8201`
2. Re-issue a secondary token from current primary.
3. Repoint secondary using `secondary/update-primary` (preferred when already joined) or re-enable secondary when needed.
  - [Update Performance Secondary's Primary](https://developer.hashicorp.com/vault/api-docs/system/replication/replication-performance#update-performance-secondary-s-primary)
  - [Update Disaster Recovery Secondary's Primary](https://developer.hashicorp.com/vault/api-docs/system/replication/replication-dr#update-dr-secondary-s-primary)

---

#### 2) Symptom: WAL backlog/replication lag grows and does not drain

Likely causes:

- bandwidth/latency issue between cluster addresses
- write pressure spike on primary
- active node resource contention
- secondary repeatedly reconnecting

Useful checks:

```bash
# Run on the current PR primary
vault read -format=json sys/replication/performance/status | jq .

# Run on the PR secondary
vault read -format=json sys/replication/performance/status | jq .
```

Fix actions:

- reduce write-heavy tasks temporarily (mass login bursts, lease churn, high-frequency secret writes)
- keep active node stable while backlog drains
- resolve packet loss / routing / firewall issues on replication paths

If lag still does not drain, tune log shipper on the WAL-shipping cluster (typically the primary):

```bash
# Example server configuration on the WAL-shipping cluster
replication {
  logshipper_buffer_length = 130000
  logshipper_buffer_size   = "5gb"
}
```

Log shipper tuning guidance:

- `logshipper_buffer_length` controls how many WAL entries can be retained in-memory.
- Start by increasing `logshipper_buffer_length` to exceed the largest secondary debug value from:
  - `[DEBUG] replication: starting merkle sync: num_conflict_keys=<N>`
- `logshipper_buffer_size` caps memory usage for log shipper buffers. Increase only if needed after validating host memory headroom.
- Apply these values on each member of the cluster shipping WAL and restart Vault servers in that cluster for changes to take effect.
- Keep a controlled change window because restarts on the primary affect service.

Useful telemetry while tuning:

- `vault.logshipper.streamWALs.missing_guard` (increasing value indicates WAL entries are missing from buffer)
- `vault.logshipper.streamWALs.scanned_entries` (helps estimate how far behind secondaries are)
- `vault.logshipper.buffer.length`
- `vault.logshipper.buffer.max_length`

Retest by sampling status repeatedly and confirming lag trends downward.

Related references:
- Telemetry setup for replication trend visibility: [telemetry/vault-telemetry-grafana-repro.md](../telemetry/vault-telemetry-grafana-repro.md)
- DR troubleshooting pattern for `merkle-diff`/`merkle-sync` and log shipper tuning: [DR Replication Issues](https://support.hashicorp.com/hc/en-us/articles/27327663163027-DR-Replication-Issues)

---

#### 3) Symptom: Secondary stuck in `merkle-diff` or `merkle-sync`

Likely causes:

- unresolved merkle tree mismatch
- primary-side merkle corruption
- reindex run only on secondary while primary remains inconsistent

Useful checks:

```bash
# Run on primary
vault write -format=json sys/replication/merkle-check | jq .

# Run on secondary
vault write -format=json sys/replication/merkle-check | jq .
```

Primary-side log indicator commonly seen in this condition:

```text
state is still irreconcilable after reindex, try reindexing primary cluster
```

Fix actions:

1. Plan low-write change window.
2. Keep leader stable (avoid restart/step-down during reindex).
3. Run primary reindex:

```bash
vault write -f sys/replication/reindex skip_flush=true
```

4. Monitor:

```bash
vault read -format=json sys/replication/status | jq .
```

For detailed stage behavior and lock-window cautions, use:

- [Merkle Corruption Reindex KB](./vault-replication-merkle-corruption-reindex-kb.md)

Retest:

- secondaries leave `merkle-diff` / `merkle-sync`
- both PR and DR return to stable `running` state

---

#### 4) Symptom: `merkle-check` reports corruption

Diagnostic pattern:

```json
{
  "data": {
    "merkle_corruption_report": {
      "corrupted_root": true
    }
  }
}
```

Interpretation:

- corruption in `tree_type="replicated"` impacts PR
- corruption in `tree_type="local"` impacts DR

Fix actions:

- prioritize primary-side reindex workflow
- avoid secondary-only reindex as the sole recovery action when primary is corrupted
- keep baseline snapshots and rollback plan before execution

Retest:

```bash
vault write -format=json sys/replication/merkle-check | jq '.data.merkle_corruption_report'
```

Expected result: `corrupted_root=false`.

---

### Failover Commands

Use these only during incident-approved recovery events.

#### Avoid Split-Brain

Split-brain in replication means two clusters behave as primary at the same time. This is high risk because writes can diverge and recovery becomes more complex.

Key guardrails:

- Keep only one active primary at any time.
- If the current primary is still reachable and you must promote a secondary, demote the current primary first.
- Keep the gap between demote and promote operations as short as possible.
- After promotion, immediately repoint remaining secondaries to the new primary.
- If the old primary comes back after failover, either demote it to secondary and update primary assignment, or disable replication on it until topology is clean.

Quick checks after failover actions:

```bash
# Run on each cluster and confirm exactly one primary is reported
vault read sys/replication/performance/status
vault read sys/replication/dr/status
```

For the official DR guidance and split-brain workflow notes, see:
- [Enable disaster recovery replication - Avoid split-brain situation](https://developer.hashicorp.com/vault/tutorials/enterprise/disaster-recovery#avoid-split-brain-situation)

---

#### PR failover command reference

Destructive action warning: promotes a new PR primary; new secondary tokens are required for peers.

```bash
# Run on old PR primary (if reachable)
vault write -f sys/replication/performance/primary/demote

# Run on PR secondary to promote it
vault write sys/replication/performance/secondary/promote

# Run on new PR primary to generate a token for old primary
vault write sys/replication/performance/primary/secondary-token id="pr-secondary-old-primary"

# Run on old primary to rejoin as secondary
vault write sys/replication/performance/secondary/update-primary token="<token-from-command-above>"
```

#### DR promotion/failback command reference

Destructive action warning: DR promotion changes disaster-recovery authority and requires DR operation tokens.

```bash
# Run on old DR primary (if reachable)
vault write -f sys/replication/dr/primary/demote

# Run on DR secondary to generate a DR operation token (interactive)
vault operator generate-root -dr-token -init

# ...submit required key shares...
# ...decode token...

# Run on DR secondary to promote it
vault write sys/replication/dr/secondary/promote \
  dr_operation_token="<decoded-dr-operation-token>"

# Run on new DR primary to generate a failback token
vault write -field=token sys/replication/dr/primary/secondary-token id="dr-secondary-old-primary"

# Run on old primary:
# 1) Generate DR operation token there
# 2) Repoint old primary to new DR primary
vault write sys/replication/dr/secondary/update-primary \
  dr_operation_token="<decoded-dr-operation-token-generated-on-old-primary>" \
  token="<failback-token-from-command-above>"
```

Retest after each action:

```bash
# Run on both clusters
vault read sys/replication/performance/status
vault read sys/replication/dr/status
```

---

### References

- [Vault Enterprise Replication](https://developer.hashicorp.com/vault/docs/enterprise/replication)
- [replication stanza configuration](https://developer.hashicorp.com/vault/docs/configuration/replication)
- [Performance replication API docs](https://developer.hashicorp.com/vault/api-docs/system/replication/replication-performance)
- [Disaster recovery replication API docs](https://developer.hashicorp.com/vault/api-docs/system/replication/replication-dr)
- [Troubleshoot and tune enterprise replication](https://developer.hashicorp.com/vault/tutorials/enterprise/troubleshoot-tune-enterprise-replication)
- [Merkle Corruption Reindex KB](./vault-replication-merkle-corruption-reindex-kb.md)
- [PR Path Filtering Lab](../vault-professional-cert/lab-04-pr-replication-path-filtering.md)
- [Vault Raft Quorum Break and Restore Runbook](../kubernetes/vault-raft-quorum-break-and-restore-runbook.md)
- [Vault Telemetry Grafana Repro](../telemetry/vault-telemetry-grafana-repro.md)
