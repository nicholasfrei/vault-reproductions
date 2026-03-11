## Transit Auto-Unseal Dev Runbook

This runbook starts **two local Vault dev servers**:

- **Transit Vault**: runs the `transit` secrets engine and holds the unseal key.
- **Auto-unseal Vault**: uses a **transit seal** with a simple **HCL config file**.

Use this to quickly reproduce transit auto-unseal behavior on your laptop. This is **not** a production pattern.

---

### 1. Start the Transit Vault (dev mode)

In **terminal tab 1**, start a dev Vault that will act as the **transit KMS**:

```bash
export VAULT_ADDR=http://127.0.0.1:8200

vault server -dev \
  -dev-root-token-id=root \
  -dev-listen-address="127.0.0.1:8200"
```

Leave this process running.

In a **second shell** (same tab via `tmux` split or a new tab), export the same environment:

```bash
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=root
```

Validate connectivity:

```bash
vault status
```

You should see `sealed: false` (dev mode) and `HA Enabled: false`.

---

### 2. Configure the Transit Secrets Engine and Auto-Unseal Key

Still pointing at the **transit Vault** (`VAULT_ADDR=http://127.0.0.1:8200`, `VAULT_TOKEN=root`):

1. **Enable transit** (if not already):

   ```bash
   vault secrets enable transit
   ```

2. **Create a dedicated transit key** for unsealing:

   ```bash
   vault write -f transit/keys/autounseal-key
   ```

3. **Create a minimal policy** that can encrypt/decrypt with this key:

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

4. **Create a token** bound to the policy and capture it:

   ```bash
   TRANSIT_UNSEAL_TOKEN="$(
     vault token create \
       -policy=transit-auto-unseal \
       -period=24h \
       -format=json | jq -r .auth.client_token
   )"

   echo "TRANSIT_UNSEAL_TOKEN=${TRANSIT_UNSEAL_TOKEN}"
   ```

Keep this value handy; you will plug it into the HCL config in the next step.

---

### 3. Review the Mock HCL Config File

This repository includes a **mock HCL config template** for the auto-unseal Vault:

- `seal-transit-auto-unseal/vault-transit-auto-unseal.hcl`

Key elements of the config:

- `storage "file"`: local file storage in `./vault-data-auto-unseal`.
- `listener "tcp"`: HTTP listener on `127.0.0.1:8300` (no TLS, dev only).
- `seal "transit"`: points back to the **transit Vault** on `127.0.0.1:8200`.

The `seal "transit"` block expects you to replace the placeholder:

- `TRANSIT_UNSEAL_TOKEN_PLACEHOLDER`

with the actual `TRANSIT_UNSEAL_TOKEN` from step 2.

#### 3.1. Populate the HCL file with your token

In the `vault-transit-auto-unseal.hcl` file, replace the `TRANSIT_UNSEAL_TOKEN_PLACEHOLDER` with the actual `TRANSIT_UNSEAL_TOKEN` from step 2.

---

### 4. Start the Auto-Unseal Vault with the HCL Config

In **terminal tab 2**, start a **second Vault** that will use the transit seal:

```bash
export VAULT_ADDR=http://127.0.0.1:8300

vault server -config=/tmp/vault-transit-auto-unseal.hcl
```

Leave this process running as well.

In another shell for this instance:

```bash
export VAULT_ADDR=http://127.0.0.1:8300
```

At this point, this Vault is **sealed** and **not yet initialized**.

---

### 5. Initialize the Auto-Unseal Vault (once)

Run the init flow **against the auto-unseal Vault** from a new shell:

```bash
export VAULT_ADDR=http://127.0.0.1:8300

vault status
vault operator init
```

> **Important (transit seal behavior)**  
> Do **not** pass `-key-shares` or `-key-threshold` flags when the `seal "transit"` stanza is configured.  

Expected behavior:

- Vault contacts the **transit Vault** at `127.0.0.1:8200`.
- The **unseal key** is encrypted using the `autounseal-key` transit key.
- The server should report `Sealed: false` immediately after `init` completes (because transit auto-unseal is configured).

Capture and store the init output somewhere safe (even in dev).

Verify status:

```bash
vault status
```

You should see `sealed: false`.

---

### 6. Validate Auto-Unseal Behavior on Restart

To prove auto-unseal is active:

1. **Stop** the auto-unseal Vault process (Ctrl+C in its terminal tab).
2. **Restart** it with the same HCL config:

   ```bash
   export VAULT_ADDR=http://127.0.0.1:8300

   vault server -config=/tmp/vault-transit-auto-unseal.hcl
   ```

3. Wait a few seconds, then in a separate shell run:

   ```bash
   export VAULT_ADDR=http://127.0.0.1:8300

   vault status
   ```

Expected:

- `sealed: false`
- `type: file`
- No manual `vault operator unseal` calls are required.

If you **stop** the transit Vault (dev server on `8200`) and then restart the auto-unseal Vault, you should see **seal failures** because the seal cannot talk to its KMS; this is a useful failure mode to test.

---

### 7. Basic Read/Write Sanity Check

Log into the auto-unseal Vault using the root token returned by `vault operator init` in step 5:

```bash
export VAULT_ADDR=http://127.0.0.1:8300
export VAULT_TOKEN=<ROOT_TOKEN_FROM_INIT>

vault secrets enable -path=kv kv
vault kv put kv/demo foo=bar
vault kv get kv/demo
```

If this works end-to-end (before and after restart), the transit auto-unseal path is operating correctly.

---

### 8. Cleanup

Stop both Vault dev servers (Ctrl+C in each terminal tab).

---

### 9. Common Tweaks / Variations

- **Change storage path**: edit the `storage "file"` stanza in the HCL template.
- **Change ports**: update `listener "tcp"` and `api_addr`/`cluster_addr` in the HCL to avoid conflicts.
- **TLS testing**: swap `tls_disable = 1` for a real TLS listener and run the same flow with HTTPS endpoints.

For production, replace:

- Dev mode (`vault server -dev`) with a proper multi-node deployment.
- File storage with your real storage backend.
- Inlined token in HCL with a more secure secret delivery mechanism (env var, secret manager, or Vault Agent template).

