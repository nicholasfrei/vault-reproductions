## Lab 1: Transit Auto-Unseal and Node Join

Objective:
- Configure a transit-backed auto-unseal flow.
- Build node 1 config with a correct `seal "transit"` stanza.
- Initialize node 1 with recovery keys.
- Build node 2 config with transit seal and join it to node 1.
- Validate cluster health and raft peers.

This lab is intentionally exam-style: you are expected to populate the `seal "transit"` stanza yourself.

---

### 0. Preconditions

#### How to Use This Hands-On Lab

1. **Create a Codespace** from this repo using the Lab 01 devcontainer link below (required so host aliases and terminal profiles load).
2. Open **three** terminals: use the **˅** next to **+** in the Terminal panel → **Select Profile** — pick each profile once (repeat three times):
   - **Lab 01: transit-vault** — prompt shows `[transit-vault]`; use for transit KMS CLI (pre-started dev Vault).
   - **Lab 01: vault-node-1** — prompt shows `[vault-node-1]`; run `vault server` for node 1 here.
   - **Lab 01: vault-node-2** — prompt shows `[vault-node-2]`; run `vault server` for node 2 here.
3. Follow the steps in this runbook in the matching terminal.

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://github.com/codespaces/new?hide_repo_select=true&ref=main&repo=1161798724&skip_quickstart=true&devcontainer_path=.devcontainer%2Flab-01%2Fdevcontainer.json)

Quick checks:

```bash
export VAULT_ADDR=http://transit-vault:8200
export VAULT_TOKEN=root

vault status
vault token lookup
```

Expected:
- Transit node is unsealed and reachable.
- Root token works.

Lab topology in this profile:
- Transit node: pre-started dev Vault at `transit-vault:8200`.
- Node 1: you start/configure at `vault-node-1:8200`.
- Node 2: you start/configure at `vault-node-2:8200`.

Raft storage directories `/tmp/vault-node-1/data` and `/tmp/vault-node-2/data` are created on container start.

---

### 1. Configure Transit KMS Resources

Point CLI at the transit node:

```bash
export VAULT_ADDR=http://transit-vault:8200
export VAULT_TOKEN=root
```

Enable transit and create key:

```bash
vault secrets enable transit
vault write -f transit/keys/autounseal-key
```

Create minimal policy:

```bash
vault policy write transit-auto-unseal - <<EOF
path "transit/encrypt/autounseal-key" {
  capabilities = ["update"]
}

path "transit/decrypt/autounseal-key" {
  capabilities = ["update"]
}

path "transit/keys/autounseal-key" {
  capabilities = ["read"]
}
EOF
```

Create token for seal operations:

```bash
TRANSIT_UNSEAL_TOKEN="$(
  vault token create \
    -policy=transit-auto-unseal \
    -period=24h \
    -format=json | jq -r .auth.client_token
)"

export TRANSIT_UNSEAL_TOKEN
echo "$TRANSIT_UNSEAL_TOKEN"
```

---

### 2. Prepare Node 1 Config (You Fill Seal Stanza)

Copy template:

```bash
cp .devcontainer/lab-01/vault-node-1.hcl.example /tmp/vault-node-1.hcl
```

Edit `/tmp/vault-node-1.hcl` and add your `seal "transit"` stanza.

Tips:
- Transit address should be `http://transit-vault:8200`.
- Use `mount_path = "transit/"`.
- Use `key_name = "autounseal-key"`.
- Use the token from step 1.

In the **`[vault-node-1]`** terminal, start node 1 (leave it running):

```bash
vault server -config=/tmp/vault-node-1.hcl
```

Use **`[transit-vault]`** for transit KMS commands and another tab (or **`[vault-node-1]`** with `VAULT_ADDR` changed) only if you need an extra shell for `vault status` before init.

---

### 3. Initialize Node 1 with Recovery Keys

In a new shell:

```bash
export VAULT_ADDR=http://vault-node-1:8200
vault status
```

Initialize with recovery key options:

```bash
vault operator init \
  -recovery-shares=5 \
  -recovery-threshold=3 \
  -format=json > /tmp/lab1-node1-init.json
```

Read and export root token:

```bash
jq -r .root_token /tmp/lab1-node1-init.json
export VAULT_TOKEN="$(jq -r .root_token /tmp/lab1-node1-init.json)"
```

Validation:

```bash
vault status
```

Expected:
- `Sealed` is `false` (auto-unseal active).
- `Recovery Seal Type` shows transit-backed behavior.

---

### 4. Restart Node 1 to Prove Auto-Unseal

In node 1 server terminal, stop process (`Ctrl+C`) and restart:

```bash
vault server -config=/tmp/vault-node-1.hcl
```

In another shell:

```bash
export VAULT_ADDR=http://vault-node-1:8200
export VAULT_TOKEN="$(jq -r .root_token /tmp/lab1-node1-init.json)"
vault status
```

Expected:
- Node 1 returns as unsealed without manual `vault operator unseal`.

---

### 5. Prepare Node 2 Config (You Fill Seal Stanza)

Copy template:

```bash
cp .devcontainer/lab-01/vault-node-2.hcl.example /tmp/vault-node-2.hcl
```

Edit `/tmp/vault-node-2.hcl` and add a valid `seal "transit"` stanza (same transit node/key model as node 1).

In the **`[vault-node-2]`** terminal, start node 2:

```bash
vault server -config=/tmp/vault-node-2.hcl
```

Expected:
- Node 2 starts with transit seal configuration.
- Node 2 is **not joined yet** until you run `vault operator raft join`.

---

### 6. Manually Join Node 2 to Node 1

Run the join command against node 2 using the node 1 root token from init:

```bash
export VAULT_ADDR=http://vault-node-2:8200
vault operator raft join http://vault-node-1:8200
export VAULT_TOKEN="$(jq -r .root_token /tmp/lab1-node1-init.json)"
vault status
```

Expected:
- `vault operator raft join` returns success.
- Node 2 reports healthy status after join.

---

### 7. Validate Cluster Join and Health

From a separate shell:

```bash
export VAULT_ADDR=http://vault-node-1:8200
export VAULT_TOKEN="$(jq -r .root_token /tmp/lab1-node1-init.json)"

vault operator raft list-peers
vault status
```

Optional check from node 2 endpoint:

```bash
export VAULT_ADDR=http://vault-node-2:8200
vault status
```

Expected:
- Two raft peers are visible.
- Node 1 leader / node 2 follower (or equivalent cluster state).

---
### 8. Troubleshooting Hints

- `permission denied` in seal operations:
  - Confirm each HCL file has the actual transit token (not the placeholder).
  - Verify the transit policy includes encrypt/decrypt/read for `autounseal-key`.
- Node 2 join fails:
  - Ensure node 1 is initialized, unsealed, and active first.
  - Re-run `vault operator raft join http://vault-node-1:8200` from node 2 context.

---

### 9. Cleanup

Stop node 1 and node 2 server processes (`Ctrl+C`).

Optional cleanup files:

```bash
rm -rf /tmp/vault-node-1 /tmp/vault-node-2 /tmp/lab1-node1-init.json
```

---

### References

- [Transit Seal Configuration](https://developer.hashicorp.com/vault/docs/configuration/seal/transit)
- [Transit Seal Best Practices](https://developer.hashicorp.com/vault/docs/configuration/seal/transit-best-practices)
- [Vault operator init: HSM and KMS options](https://developer.hashicorp.com/vault/docs/commands/operator/init#hsm-and-kms-options)
