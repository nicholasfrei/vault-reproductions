# Control Group Missing Audit Response Repro

## Overview

When a request triggers a control group (CG) factor, Vault returns a wrapped token to the caller but the corresponding audit `response` log entry is never written. This means the CG token, its accessor, TTL, and creation path are never recorded. Downstream audit analysis cannot link an authorisation to the request that created it or to the unwrap that consumed it.

## Objective

Reproduce the missing audit response entry on a control-group-protected path and confirm:

- the audit `request` entry is written for the CG-blocked request
- the audit `response` entry is absent
- the wrapped token accessor is therefore never logged

## Prerequisites

- Vault Enterprise (control groups require Enterprise)
- `1.21.3+ent` Vault Version
- A running Vault cluster with audit logging enabled, or a local dev server started with audit enabled
- `vault` CLI configured and authenticated as root (or with `sudo` capability on all paths below)
- `jq` installed

## Step 1: Enable file audit device

```bash
vault audit enable file file_path=/tmp/vault-audit.log
```

Confirm it is active:

```bash
vault audit list
```

Expected output:

```text
Path     Type    Description
----     ----    -----------
file/    file    n/a
```

## Step 2: Enable KV v2 and write a protected secret

```bash
vault secrets enable -path=EU_GDPR_data kv-v2

vault kv put EU_GDPR_data/orders/acct1 \
  customer="Acme Corp" \
  order_id="ORD-9001"
```

## Step 3: Create the authorizer (alice) and requester (bob) users

```bash
vault auth enable userpass

vault write auth/userpass/users/alice password='password'
vault write auth/userpass/users/bob   password='password'
```

## Step 4: Create identity entities and group

```bash
vault write -format=json identity/entity name=alice-entity | \
  jq -r '.data.id' > /tmp/alice-entity-id.txt

vault write -format=json identity/entity name=bob-entity | \
  jq -r '.data.id' > /tmp/bob-entity-id.txt

USERPASS_ACCESSOR=$(vault auth list -format=json | jq -r '."userpass/".accessor')

vault write identity/entity-alias \
  name=alice \
  canonical_id="$(cat /tmp/alice-entity-id.txt)" \
  mount_accessor="$USERPASS_ACCESSOR"

vault write identity/entity-alias \
  name=bob \
  canonical_id="$(cat /tmp/bob-entity-id.txt)" \
  mount_accessor="$USERPASS_ACCESSOR"

vault write -format=json identity/group \
  name=cg-authorizers \
  member_entity_ids="$(cat /tmp/alice-entity-id.txt)" | \
  jq -r '.data.id' > /tmp/cg-group-id.txt
```

## Step 5: Create policies

Policy for alice (authorizer):

```bash
vault policy write authorize-gdpr - <<'EOF'
path "sys/control-group/approve" {
  capabilities = ["create", "update"]
}
EOF
```

Policy for bob (requester — accesses the protected path):

```bash
vault policy write read-gdpr-order - <<'EOF'
path "EU_GDPR_data/data/orders/acct1" {
  capabilities = ["read"]

  control_group = {
    factor "authorizer" {
      identity {
        group_names = ["cg-authorizers"]
        approvals   = 1
      }
    }
    ttl = "24h"
  }
}
EOF
```

Attach policies to users:

```bash
vault write auth/userpass/users/alice policies='authorize-gdpr'
vault write auth/userpass/users/bob   policies='read-gdpr-order'
```

## Step 6: Trigger the control group as bob

```bash
BOB_TOKEN=$(vault login -method=userpass username=bob password=password -format=json | \
  jq -r '.auth.client_token')

VAULT_TOKEN="$BOB_TOKEN" vault kv get EU_GDPR_data/orders/acct1
```

Expected CLI output (the request is blocked; a wrapped token is returned):

```text
Error reading EU_GDPR_data/data/orders/acct1: Error making API request.

URL: GET http://127.0.0.1:8200/v1/EU_GDPR_data/data/orders/acct1
Code: 400. Errors:

* request cannot be fulfilled until control group approval is obtained,
  initiating approval process by creating token to be approved
```

The CLI surfaces the error string but the caller actually receives a `200` with `wrap_info` populated. The accessor embedded in that response is what should appear in the audit log.

## Step 7: Inspect the audit log

```bash
grep '"type":"request"' /tmp/vault-audit.log | \
  jq 'select(.request.path == "EU_GDPR_data/data/orders/acct1")' | \
  jq '{type, request_id: .request.id, path: .request.path, error: .error}'
```

Expected (request entry is present):

```json
{
  "type": "request",
  "request_id": "<uuid>",
  "path": "EU_GDPR_data/data/orders/acct1",
  "error": "1 error occurred:\n\t* request cannot be fulfilled until control group approval is obtained, initiating approval process by creating token to be approved\n\n"
}
```

```bash
grep '"type":"response"' /tmp/vault-audit.log | \
  jq 'select(.request.path == "EU_GDPR_data/data/orders/acct1")'
```

Expected (response entry is absent):

```text
(no output)
```

This confirms the bug: the `response` entry — which would contain `response.wrap_info.token`, `response.wrap_info.accessor`, `response.wrap_info.ttl`, `response.wrap_info.creation_path`, and the caller's HMAC'd token and accessor in `auth` — is never written to the audit log.

## What a complete audit log should look like

When the bug is fixed, the audit log should contain a `response` entry immediately after the `request` entry. Example of expected structure:

```json
{
  "type": "response",
  "time": "2026-08-28T04:57:56.861399Z",
  "auth": {
    "display_name": "userpass-bob",
    "policies": ["default", "read-gdpr-order"],
    "client_token": "hmac-sha256:<redacted>",
    "accessor": "hmac-sha256:<redacted>"
  },
  "request": {
    "id": "<uuid>",
    "operation": "read",
    "path": "EU_GDPR_data/data/orders/acct1"
  },
  "response": {
    "wrap_info": {
      "token":         "hmac-sha256:<redacted>",
      "accessor":      "hmac-sha256:<redacted>",
      "ttl":           86400,
      "creation_time": "2026-08-28T04:57:56Z",
      "creation_path": "EU_GDPR_data/data/orders/acct1"
    }
  }
}
```

## Validation summary

| Audit entry | Expected | Observed (buggy) |
|---|---|---|
| `type: request` for CG-blocked path | present | present |
| `type: response` for CG-blocked path | present | absent |
| `response.wrap_info.accessor` | logged (HMAC'd) | never written |
| caller `auth.client_token` in response | logged (HMAC'd) | never written |

## References

- [Vault Docs - Control Groups](https://developer.hashicorp.com/vault/docs/enterprise/control-groups)
- [Vault Docs - Audit Devices](https://developer.hashicorp.com/vault/docs/audit)
- [Vault Docs - KV v2 Secrets Engine](https://developer.hashicorp.com/vault/docs/secrets/kv/kv-v2)
