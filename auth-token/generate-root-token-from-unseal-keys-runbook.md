# Generate a New Vault Root Token Using Unseal Keys

## Objective

Generate a new root token when the original root token has been lost, using existing Shamir unseal key shares.

This runbook uses `vault operator generate-root` to produce a new root token without reinitializing or unsealing the cluster.

## Safety Notes

- This procedure requires at least a quorum of unseal key shares (meeting the configured threshold).
- Run in a controlled change window if possible.

## Prerequisites

- Vault is initialized, unsealed, and reachable.
- You have unseal key shares meeting the current threshold (for example, 3 of 5).
- `vault` CLI is installed and `VAULT_ADDR` is set to the target cluster.

Confirm Vault is unsealed and reachable:

```bash
vault status
```

Expected fields:

- `Initialized: true`
- `Sealed: false`

---

## Steps

### 1. Start the generate-root operation

Initialize the process. This returns a **nonce** and a one-time pad (**OTP**) needed to decode the final encoded token.

```bash
vault operator generate-root -init
```

Example output:

```
Nonce         <nonce-value>
Started       true
Progress      0/3
Complete      false
OTP           <otp-value>
OTP Length    26
```

Record both `Nonce` and `OTP`. The OTP is shown only once.

---

### 2. Submit unseal key shares

For each unseal key share, submit it using the nonce from step 1. Repeat until the threshold is met.

```bash
vault operator generate-root \
  -nonce="<nonce-from-step-1>" \
  "<unseal-key-share>"
```

After each submission, output shows the current progress:

```
Nonce         <nonce-value>
Started       true
Progress      1/3
Complete      false
```

When the final key share is submitted and the threshold is reached, the output includes the encoded token:

```
Nonce              <nonce-value>
Started            true
Progress           3/3
Complete           true
Encoded Token      <encoded-token-value>
```

---

### 3. Decode the encoded token

Use the OTP from step 1 and the encoded token from step 2 to produce the plaintext root token.

```bash
vault operator generate-root \
  -decode="<encoded-token-from-step-2>" \
  -otp="<otp-from-step-1>"
```

Output:

```
<new-root-token>
```

---

### 4. Login and verify

```bash
vault login <new-root-token>
vault token lookup
```

Confirm the output shows:

- `policies: [root]`
- `display_name: root`

---

## Cancelling an In-Progress Attempt

If you need to cancel an incomplete generate-root operation:

```bash
vault operator generate-root -cancel
```

---

## References

- [vault operator generate-root](https://developer.hashicorp.com/vault/docs/commands/operator/generate-root)
- [Generate Root API](https://developer.hashicorp.com/vault/api-docs/system/generate-root)
