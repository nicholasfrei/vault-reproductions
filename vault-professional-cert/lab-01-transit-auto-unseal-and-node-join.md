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

1. **Create a Codespace** from this repo (click the button below).  
2. Once the Codespace is running, open the integrated terminal.
3. Follow the instructions in each **lab** to complete the exercises.

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

Start node 1:

```bash
vault server -config=/tmp/vault-node-1.hcl
```

Open a second terminal for status/init commands.

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

Start node 2:

```bash
vault server -config=/tmp/vault-node-2.hcl
```

Expected:
- Node 2 starts and joins raft leader at `http://vault-node-1:8200`.

---

### 6. Validate Cluster Join and Health

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

### 7. Troubleshooting Hints

- `permission denied` in seal operations:
  - Re-check policy paths and token used in `seal "transit"`.
- Node stays sealed after restart:
  - Confirm transit node is up and reachable at `http://transit-vault:8200`.
  - Confirm `key_name`, `mount_path`, and token are correct.
- Node 2 does not join:
  - Verify `retry_join` leader address.
  - Confirm node 1 is initialized and healthy before starting node 2.

---

### 8. Cleanup

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
