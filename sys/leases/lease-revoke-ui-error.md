# Vault `2.2.0` - `2.2.2` UI Error on Lease Revoke Reproduction

## Objective

Reproduce the UI error encountered when revoking a lease in Vault versions `2.2.0` through `2.2.2`. This runbook is a simple guide to demonstrate the behavior and provide steps for replication.

## Pre-requisites

- Vault cluster running `2.2.0` through `2.2.2`
- Access to the Vault UI for the cluster
- A Vault token with access to create tokens and revoke leases (preferably with admin privileges)

## Step 1: Create a Token in Vault

Login to the Vault CLI using your Vault token:

```bash
vault login <your-vault-token>
```

Create a new token using the Vault CLI:

```bash
vault token create -format=json -ttl=1h \
  -display-name=ui-revoke-repro -policy=default
```

## Step 2: Navigate in the UI

Open the Vault UI (typically at `http://<vault-address>:8200`) and log in with your Vault token.

Navigate to the "Access" section and select "Leases".  

Locate the token you created earlier (`ui-revoke-repro`). It will be under `auth/token/create` if you followed the steps above. 

## Step 3: Revoke the Lease in the UI

Click on the lease corresponding to the token you created (`ui-revoke-repro`) and attempt to revoke it.

Observe the UI behavior and any errors that occur during the revocation process.

![UI Error on Lease Revoke in Vault UI for Token `ui-revoke-repro`](20261112-transitionaborted.png)

## Step 4: Confirm Revocation in CLI

Check the status of the lease in the CLI to confirm it has been revoked:

```bash
vault list sys/leases/lookup/auth/token/create
```

If the lease has been successfully revoked, it should no longer appear in the list. You are looking for the same lease ID that you revoked in the UI.

## Conclusion

This runbook is very simple and reproduces a known UI error in `2.2.x` with lease revocations. The error that appears is not an indication that the lease was not revoked. 