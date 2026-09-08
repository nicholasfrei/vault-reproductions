# LDAP Secrets Engine `racf` Schema Regression Runbook (VAULT-49977)

## Objective

Reproduce the LDAP secrets engine regression in Vault Enterprise `1.19.16` through
`1.19.20`, where the engine rejects the valid `racf` schema during configuration.

This runbook uses only an initialized, unsealed Vault cluster. An LDAP server is
not required: the failure occurs while Vault validates the `schema` value, before
it needs to connect to the configured LDAP URL.

## Symptom

On an affected version, configuring the engine with `schema="racf"` fails with:

```text
unsupported schema type "racf": must be one of [openldap ad]
```

The same configuration is accepted on Vault `1.19.15` and on Vault `2.0.0`
through `2.0.4`.

## Version Matrix

| Vault version | Expected result |
| --- | --- |
| `1.19.15` and earlier | `racf` is accepted |
| `1.19.16` through `1.19.20` | Configuration fails with the unsupported-schema error |
| `2.0.0` through `2.0.4` | `racf` is accepted |

The regression was introduced in `1.19.16`. The practical workaround is to
upgrade to a fixed Vault release, such as Vault `2.x`.

## Prerequisites

- A non-production Vault Enterprise cluster that can be upgraded, downgraded,
  or replaced for version comparison.
- The cluster is initialized and unsealed.
- A Vault token with permission to enable and configure a secrets engine.
- The Vault CLI installed and authenticated, with `VAULT_ADDR` and
  `VAULT_TOKEN` set.
- Access to the Vault UI is optional for the UI confirmation.

Do not run the version comparison against a production cluster. If the existing
cluster cannot be changed between versions, reproduce the affected behavior on
its current version and use a separate lab cluster or Vault container for the
fixed-version comparison.

## Step 1: Verify the Vault Target

Confirm that the CLI points to the intended lab cluster and record its version:

```bash
vault status
vault version
```

Expected status includes:

```text
Initialized     true
Sealed          false
```

The version output must identify the Vault Enterprise version under test. The
Enterprise build is required because this bug report concerns Vault Enterprise.

## Step 2: Enable a Dedicated LDAP Secrets Engine

Use a unique mount path so the runbook does not interfere with an existing LDAP
secrets engine:

```bash
export RACF_MOUNT="ldap-racf-49977"
vault secrets enable -path="$RACF_MOUNT" ldap
```

Expected output:

```text
Success! Enabled the ldap secrets engine at: ldap-racf-49977/
```

If the mount already exists from an earlier attempt, either choose another path
or remove it during cleanup before continuing.

## Step 3: Reproduce on Vault 1.19.16 through 1.19.20

Configure the engine with the RACF bind DN shape and schema. The URL uses the
documentation-only loopback address `127.0.0.1:389`; no LDAP service is expected
to be listening there for this validation.

```bash
vault write "$RACF_MOUNT/config" \
  schema="racf" \
  binddn="racfid=<username>,profiletype=user,cn=RACF" \
  bindpass="<password>" \
  url="ldap://127.0.0.1:389"
```

On Vault `1.19.16` through `1.19.20`, the command must fail with HTTP `500` and
the following validation error:

```text
Error writing data to ldap-racf-49977/config: Error making API request.

Code: 500. Errors:

* 1 error occurred:

* unsupported schema type "racf": must be one of [openldap ad]
```

The error proves the regression. It is not an LDAP connectivity failure. In
particular, the error does not mean that the RACF bind DN is malformed or that
the bind password is invalid.

Confirm that the failed write did not create configuration data:

```bash
vault read "$RACF_MOUNT/config"
```

Depending on the Vault patch release, this may return an empty configuration or
an error indicating that the configuration has not been written.

## Step 4: Confirm the Same Request Is Accepted on a Fixed Version

Run the same commands against a separate Vault cluster running `1.19.15` or a
fixed `2.x` release. Do not change the command payload between versions.

```bash
vault version
vault secrets enable -path="$RACF_MOUNT" ldap
vault write "$RACF_MOUNT/config" \
  schema="racf" \
  binddn="racfid=<username>,profiletype=user,cn=RACF" \
  bindpass="<password>" \
  url="ldap://127.0.0.1:389"
```

Expected output on the fixed version:

```text
Success! Data written to: ldap-racf-49977/config
```

Read the resulting configuration and confirm that the schema was retained:

```bash
vault read "$RACF_MOUNT/config"
```

Expected field:

```text
schema    racf
```

The configuration write only demonstrates schema acceptance. A real RACF LDAP
environment, reachable URL, and valid credentials are required for credential
generation or password rotation, which are outside this reproduction.

## Step 5: Confirm UI Behavior

The UI uses the same backend configuration endpoint, so the regression is also
visible there.

1. Open the Vault UI for the affected cluster.
2. Navigate to `Secrets` and open the `ldap-racf-49977` mount.
3. Open the mount configuration screen.
4. Enter the RACF bind DN, bind password, URL, and `racf` schema if the UI
   exposes the schema field.
5. Save the configuration.
6. Open the browser developer tools Network panel and inspect the request to
   `<VAULT_ADDR>/v1/ldap-racf-49977/config`.

On an affected version, the save fails with HTTP `500` and the same message:

```text
unsupported schema type "racf": must be one of [openldap ad]
```

If the UI does not expose `racf` as a selectable schema, that is also consistent
with the bug: the UI cannot successfully configure a value rejected by the
backend. Use the CLI in Step 3 to capture the canonical error.

## Validation Checklist

- `vault version` identifies an affected Enterprise version.
- The dedicated LDAP mount is enabled.
- The `schema="racf"` write fails only on `1.19.16` through `1.19.20`.
- The exact error contains `unsupported schema type "racf": must be one of
  [openldap ad]`.
- The same payload is accepted on `1.19.15` or `2.0.0` through `2.0.4`.
- The fixed-version read shows `schema    racf`.
- The UI reproduces the same backend error on an affected version.

## Cleanup

Run cleanup against each lab cluster used for the reproduction:

```bash
vault secrets disable "$RACF_MOUNT"
unset RACF_MOUNT
```

If the write failed on an affected version, disabling the mount still removes
the empty engine mount.

## References

- [VAULT-49977](https://hashicorp.atlassian.net/browse/VAULT-49977)
- [VAULT-43114](https://hashicorp.atlassian.net/browse/VAULT-43114)
