# Vault TOTP Secrets Engine Reproduction

This runbook demonstrates Vault as a TOTP provider and verifier:
- Vault can issue TOTP keys for users.
- Vault can validate TOTP codes generated from those keys.
- A third-party service can enroll against the shared secret (for example, by scanning the provisioning URI or importing the secret) and then submit codes to Vault for verification.

## Preconditions

- Vault CLI is installed and authenticated.
- You have permissions to enable and write to the `totp` secrets engine.
- The TOTP secrets engine is not already enabled at path `totp` (or use a different mount path).

## Step 1: Enable TOTP Secrets Engine

```bash
vault secrets enable totp
```

Expected result:
- Vault enables the TOTP secrets engine at mount path `totp/`.

## Step 2: Generate a TOTP Key

```bash
vault write totp/keys/my-user \
    generate=true \
    issuer=Vault \
    account_name=user@test.com
```

Expected result:
- Vault creates key `my-user` with issuer `Vault` and account name `user@test.com`.
- Vault returns key metadata and provisioning details (output shape can vary by Vault version and CLI formatting).

## Step 3: Read Key Metadata

```bash
vault read totp/keys/my-user
```

Observed output:

```text
Key             Value
---             -----
account_name    user@test.com
algorithm       SHA1
digits          6
issuer          Vault
period          30s
```

Interpretation:
- Vault created a 6-digit SHA1 TOTP key with a 30-second period.

## Step 4: Read Current TOTP Code from Vault

```bash
vault read totp/code/my-user
```

Observed output:

```text
Key     Value
---     -----
code    376077
```

Interpretation:
- Vault returns the current valid code for the key at this time window.

## Step 5: Validate a Correct Code

```bash
vault write totp/code/my-user code=376077
```

Observed output:

```text
Key      Value
---      -----
valid    true
```

Interpretation:
- The submitted code is valid for the current TOTP time step.

## Step 6: Validate an Incorrect Code

```bash
vault write totp/code/my-user code=123456
```

Observed output:

```text
Key      Value
---      -----
valid    false
```

Interpretation:
- The submitted code is not valid.

## Expected vs Observed Behavior

- Expected: valid current code returns `valid=true`; incorrect code returns `valid=false`.
- Observed: `376077` validates as `true`; `123456` validates as `false`.
- Result: behavior matches expected TOTP verification semantics.

## Notes

- This scenario treats Vault as the TOTP provider (issuing keys and code verification).
- It can also be used with third-party services that support standard TOTP enrollment and code generation.
- TOTP codes rotate every `period` (30 seconds in this example), so a previously valid code will quickly expire.

## Cleanup

Destructive action: disabling the mount deletes all keys under it.

```bash
vault secrets disable totp
```
