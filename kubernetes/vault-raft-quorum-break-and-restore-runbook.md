# Vault Raft Quorum Break and Restore Runbook (Kubernetes)

## Objective

Reproduce a Vault Raft quorum-loss condition in Kubernetes, then restore service. This is a common scenario when a cluster has stability issues and customers need to recover their k8s Vault cluster without losing data.

- `local node not active but active cluster node not found`
- `HA Mode: standby` with no active node

## Safety Notes

- Run this only in a lab/sandbox cluster.
- Never run `vault operator init` on an already initialized cluster.

## Prerequisites

- `kubectl` access to the cluster
- Ability to `exec` into Vault pods
- Unseal key(s) and a privileged Vault token
- A 3-node Vault Raft cluster already initialized

## Part 1: Break Quorum Intentionally

### 1) Verify StatefulSet name before scaling

```bash
kubectl get sts -n vault
```

### 2) Scale down to one replica

```bash
kubectl scale sts --replicas=1 vault -n vault
kubectl get pods -n vault -w
```

Wait until only `vault-0` remains.

### 3) Confirm broken quorum symptoms

```bash
kubectl exec -ti vault-0 -n vault -- sh
vault status
```

Expected symptom pattern:

- `HA Enabled: true`
- `HA Mode: standby`
- `Active Node Address: <none>`

Try a write operation:

```bash
vault secrets enable ldap
```

Expected error:

```text
Code: 500
* local node not active but active cluster node not found
```

## Part 2: Restore Quorum (Single-Node Recovery)

Use this section when there is no active node and the singleton cannot elect a leader.

### 1) Stay at one replica and open shell in the remaining pod

```bash
kubectl exec -ti vault-0 -n vault -- sh
```

### 2) Identify Vault config and raft path

Cat the vault config to find the node_id and raft storage path:

```bash
cat /tmp/storageconfig.hcl
```

Find raft storage path from the `storage "raft"` stanza. Commonly:

- Vault data root: `/vault/data`
- Raft directory: `/vault/data/raft`

### 3) Capture cluster address and node ID

`env | grep VAULT_CLUSTER_ADDR`

Save both values:

- `NODE_ID` (from config)
- `VAULT_CLUSTER_ADDR` (from env; do not add `https://`)

### 4) Create `peers.json` in raft directory

```bash
cd /vault/data/raft
cat <<'EOF' > peers.json
[
  {
    "id": "vault-0",
    "address": "vault-0.vault-internal.vault.svc.cluster.local:8201",
    "non_voter": false
  }
]
EOF
```

Important:

- `id` must match `/vault/data/node-id` exactly.
- `address` should match `VAULT_CLUSTER_ADDR` plus raft port `:8201`.

If your real values differ, replace both fields accordingly.

### 5) Reschedule pod and unseal

```bash
kubectl delete pod -n vault vault-0
kubectl wait -n vault --for=condition=Ready pod/vault-0 --timeout=180s
kubectl exec -ti vault-0 -n vault -- vault operator unseal <UNSEAL_KEY>
kubectl exec -ti vault-0 -n vault -- vault status
```

Expected result: node becomes `active` (or at least `HA Mode` no longer stuck standby with no active).

### 6) Scale Back Out to 3 Nodes

```bash
kubectl scale sts --replicas=3 vault -n vault
kubectl get pods -n vault -w
```

wait for `vault-1` and `vault-2` to come up.

### 7) Unseal and join standbys (if auto-join is not configured)

```bash
kubectl exec -ti vault-1 -n vault -- vault operator unseal <UNSEAL_KEY>
kubectl exec -ti vault-2 -n vault -- vault operator unseal <UNSEAL_KEY>

kubectl exec -ti vault-1 -n vault -- vault operator raft join http://vault-0.vault-internal.vault.svc.cluster.local:8200
kubectl exec -ti vault-2 -n vault -- vault operator raft join http://vault-0.vault-internal.vault.svc.cluster.local:8200
```

If your Helm config already has `retry_join`, join may happen automatically after unseal.

### 8) Validate cluster health

```bash
kubectl exec -ti vault-0 -n vault -- vault operator raft list-peers
kubectl exec -ti vault-0 -n vault -- vault status
```

Expected:

- 3 peers listed
- one `leader`, others `follower`/standby
- write operations succeed again

## Quick Validation Command Set

```bash
kubectl get sts -n vault
kubectl get pods -n vault
kubectl exec -ti vault-0 -n vault -- vault status
kubectl exec -ti vault-0 -n vault -- vault operator raft list-peers
kubectl exec -ti vault-0 -n vault -- vault secrets list
```

## Troubleshooting

- If `vault status` still shows `standby` with no active node, re-check `peers.json` ID/address values.
- If join fails on standbys, verify DNS/service name and that raft data was cleared on those standbys.
- If you see TLS errors on join, use `https://` endpoint and matching CA/cert settings.