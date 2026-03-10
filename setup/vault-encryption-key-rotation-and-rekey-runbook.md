# Vault Encryption Key Rotation + Rekey Runbook (Shamir)

## Objective

Rotate Vault’s encryption key term and generate a new set of Shamir unseal keys.

This runbook covers two separate operations:

- **Unseal key rekey** via `vault operator rekey` (replaces Shamir unseal key shares/threshold)
- **Encryption key rotation** via `sys/rotate` (increments key term used to encrypt new data)

## Safety Notes

- Run first in a non-production environment and document timing/impact.
- Store unseal keys in a secure secret manager/HSM workflow. Do not leave keys in shell history or plaintext files.
- Do not lose the new unseal shares. If lost, recovery may require disruptive procedures.
- `sys/rotate` does **not** automatically re-encrypt all historical data at once; it rotates to a new active term for future writes.

## Prerequisites

- Vault is initialized, unsealed, and reachable.
- You have:
  - current unseal key share(s) meeting current threshold
  - a privileged token for `operator rekey`
  - a token with `update,sudo` on `sys/rotate` and `read` on `sys/key-status`
- Confirm seal type is Shamir:

```bash
vault status
```

Expected fields include:

- `Seal Type: shamir`
- `Initialized: true`
- `Sealed: false`

## Part 1: Rekey Vault Unseal Keys

Use this when you want to change total shares and threshold (for example, from `1/1` to `3/2`).

### 1) Start rekey operation

```bash
vault operator rekey -init \
  -key-shares=3 \
  -key-threshold=2
```

Expected output includes:

- `Started: true`
- `Rekey Progress: 0/<current-threshold>`
- `Nonce: <uuid>`

### 2) Provide existing unseal key share(s)

For a current threshold of `1`, submit one existing unseal key:

```bash
vault operator rekey -nonce="<NONCE>" "<CURRENT_UNSEAL_KEY_SHARE>"
```

Expected result:

- Vault prints `Key 1`, `Key 2`, `Key 3` (new unseal shares)
- Message confirms new shares and threshold

### 3) Securely store the new unseal keys

Immediately move new shares to your approved key custody location.

### 4) Verify new threshold/share settings

```bash
vault status
```

Expected fields now show:

- `Total Shares: 3`
- `Threshold: 2`

### Optional: Check/Cancel in-progress rekey

Check status:

```bash
vault operator rekey -status
```

Cancel (if needed):

```bash
vault operator rekey -cancel
```

## Part 2: Rotate Vault Encryption Key Term

Use this to rotate the active barrier encryption key term.

### 1) (Least privilege option) create a rotation policy

```hcl
path "sys/rotate" {
  capabilities = ["update", "sudo"]
}
path "sys/key-status" {
  capabilities = ["read"]
}
```

Apply policy and create a token:

```bash
vault policy write rotate_ops rotate_ops.hcl
vault token create -policy=rotate_ops
export VAULT_TOKEN="<ROTATE_OPS_TOKEN>"
```

### 2) Capture current key status

```bash
vault read sys/key-status
```

Record at minimum:

- `term`
- `encryptions`
- `install_time`

### 3) Rotate the key term

`sys/rotate` requires force mode (no payload body):

```bash
vault write -f sys/rotate
```

If you run `vault write sys/rotate` without `-f`, expected error is:

```text
Must supply data or use -force
```

### 4) Validate key term incremented

```bash
vault read sys/key-status
```

Expected result:

- `term` increases by 1 (for example `1 -> 2`)

## Post-Change Validation Checklist

- `vault status` shows unsealed and healthy HA state.
- Rekeyed unseal keys are distributed and old key custody records are retired per your process.
- `vault read sys/key-status` shows incremented term after rotation.
- At least one normal read/write path still works (for example `vault secrets list`).

## Troubleshooting

- **`rekey already in progress`**
  - A previous rekey was started. Use `vault operator rekey -status` or `vault operator rekey -cancel`.

- **`Must supply data or use -force` on rotate**
  - Run `vault write -f sys/rotate`.

## Cleanup / Operational Hygiene

- Remove sensitive env vars when done:

```bash
unset VAULT_TOKEN
```

- If command history contains sensitive key material, rotate shell history and follow your incident/security process.
