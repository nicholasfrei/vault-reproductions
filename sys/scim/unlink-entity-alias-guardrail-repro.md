# SCIM `unlink-entity` Alias Guardrail Bypass Repro

## Overview

`identity/scim/client/<name>/unlink-entity` exposes two consent flags with an identical documented safety contract:

- `unlink_aliases=true` — required to strip the entity's SCIM-managed alias from the client.
- `remove_memberships=true` — required to remove the entity from SCIM-managed groups.

Both flags are documented as opt-in consent gates. The group-membership flag enforces correctly: omitting it blocks the operation, supplying it executes and reports `unlinked_group_ids`. The alias flag does not enforce: calling with `remove_memberships=true` and no `unlink_aliases` silently strips the SCIM-managed alias and returns `unlinked_alias_ids: null`, giving no audit trail that the alias was touched.

### Affected versions

Reproduced on `vault_2.2.0-beta1+ent`.

### Symptoms

- `unlinked_alias_ids: null` in the audit log response even though the alias was removed.
- Entity's `aliases[0].scim_client_id` becomes `null` (unmanaged) without the caller supplying `unlink_aliases=true`.
- No error or warning is returned.

### Expected behavior

Calling `unlink-entity` with `remove_memberships=true` but without `unlink_aliases=true` should leave the SCIM alias intact and still owned by the client, matching the behavior of the `remove_memberships` flag.

## Prerequisites

- Vault Enterprise binary `2.2.0-beta1+ent` or later. SCIM endpoints are not present in `2.0.x+ent` or `2.1.x+ent` even with `enable-scim` activated — `vault list identity/scim/` returns nothing on those builds. Use the `2.2.0-beta1+ent` pre-release binary or a local enterprise build at a commit that includes the SCIM implementation. A 404 on `identity/scim/client` on an older GA binary confirms the feature is not yet shipped.
- A valid Enterprise license loaded in the server (`VAULT_LICENSE` env var or `license_path` in the config).
- `jq` and `curl` installed.

## Step 1: Start Vault and activate the SCIM feature flag

Set your license, then start a dev server:

```bash
export VAULT_LICENSE=<your_enterprise_license>
vault server -dev -dev-root-token-id=root &
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN=root
export S="$VAULT_ADDR/v1/identity/scim/v2"
```

SCIM is gated behind a one-time activation flag. Check whether it is already active:

```bash
vault read sys/activation-flags
```

If `enable-scim` appears in the `unactivated` list, activate it. This is a one-way, irreversible action:

```bash
vault write -f sys/activation-flags/enable-scim/activate
```

Expected output confirms `enable-scim` moves to the `activated` list:

```text
Key           Value
---           -----
activated     [enable-scim]
unactivated   []
```

## Step 2: Enable userpass and capture its mount accessor

The SCIM client needs an auth method to associate entity aliases with. Userpass is the simplest choice. The mount accessor is the unique identifier Vault assigns to each enabled auth method; aliases are tied to a specific accessor so Vault knows which auth backend owns the identity.

```bash
vault auth enable userpass
```

Capture the accessor:

```bash
ACC_IDP=$(vault auth list -format=json | jq -r '.["userpass/"].accessor')
echo $ACC_IDP
```

Expected output: a string like `auth_userpass_xxxxxxxx`.

## Step 3: Create a SCIM client and obtain a bearer token

A SCIM client is a named configuration object in Vault (`identity/scim/client/<name>`) that represents an external identity provider connecting over SCIM. Two parameters are required:

- `access_grant_principal` — the entity ID of an existing Vault entity. Vault authorizes SCIM protocol requests only from tokens whose entity ID matches this value.
- `alias_mount_accessor` — the auth mount accessor from Step 2. Vault creates an entity alias on this mount for each SCIM user provisioned through this client.

Create a dedicated entity for the SCIM client principal:

```bash
vault write identity/entity name=scim-idp-a-principal
PRINCIPAL_EID=$(vault read -format=json identity/entity/name/scim-idp-a-principal | jq -r '.data.id')
echo $PRINCIPAL_EID
```

Create the SCIM client:

```bash
vault write identity/scim/client/idp-a \
  access_grant_principal=$PRINCIPAL_EID \
  alias_mount_accessor=$ACC_IDP
```

The SCIM endpoints require a standard Vault token whose backing entity matches `access_grant_principal`. Create a userpass credential for the principal entity, attach it as an alias, and log in to obtain the token:

```bash
vault write auth/userpass/users/scim-idp-a password=password

vault write identity/entity-alias \
  name=scim-idp-a \
  canonical_id=$PRINCIPAL_EID \
  mount_accessor=$ACC_IDP

TOK_A=$(vault login -format=json -method=userpass username=scim-idp-a password=password | jq -r '.auth.client_token')
echo $TOK_A
```

Expected output: a token string starting with `hvs.`.

## Step 4: Create entity, alias, and SCIM user

```bash
EMAIL="scim-repro-$(date +%s)@example.com"
EID=$(vault write -f -format=json identity/entity | jq -r '.data.id')

vault write identity/entity-alias \
  name="$EMAIL" \
  canonical_id=$EID \
  mount_accessor=$ACC_IDP

curl -sS -X POST "$S/Users" \
  -H "Authorization: Bearer $TOK_A" \
  -H "Content-Type: application/scim+json" \
  -d "{\"schemas\":[\"urn:ietf:params:scim:schemas:core:2.0:User\"],\"userName\":\"$EMAIL\",\"active\":true}"
```

## Step 5: Create group and add entity as member

```bash
GNAME="scim-repro-group-$(date +%s)"
vault write -format=json identity/group name="$GNAME" type=internal > /tmp/group.json
GROUP_ID="$(jq -r '.data.id' /tmp/group.json)"
echo $GROUP_ID

jq -n --arg dn "$GNAME" --arg eid "$EID" \
  '{schemas:["urn:ietf:params:scim:schemas:core:2.0:Group"],displayName:$dn,members:[{value:$eid}]}' \
  > /tmp/gbody.json

curl -sS -X PUT "$S/Groups/$GROUP_ID" \
  -H "Authorization: Bearer $TOK_A" \
  -H "Content-Type: application/scim+json" \
  --data @/tmp/gbody.json
```

## Step 6: Confirm ownership before unlinking

```bash
vault read -format=json identity/entity/id/$EID \
  | jq -c '{entity_owner:.data.scim_client_id, alias_owner:.data.aliases[0].scim_client_id, groups:.data.group_ids}'

vault read -format=json identity/group/id/$GROUP_ID \
  | jq -c '{group_owner:.data.scim_client_id, members:.data.member_entity_ids}'
```

Expected output: both `entity_owner` and `alias_owner` are non-empty SCIM client IDs; group membership contains `$EID`.

```text
{"entity_owner":"<scim-client-uuid>","alias_owner":"<scim-client-uuid>","groups":["<group-uuid>"]}
{"group_owner":"<scim-client-uuid>","members":["<entity-uuid>"]}
```

## Step 7: Call `unlink-entity` without any consent flags (baseline)

```bash
vault write identity/scim/client/idp-a/unlink-entity entity_id=$EID
```

Expected: Vault blocks the operation with a 400 error because the entity is a member of a SCIM-managed group and no consent flags were supplied:

```text
Error writing data to identity/scim/client/idp-a/unlink-entity: Error making API request.

URL: PUT http://127.0.0.1:8200/v1/identity/scim/client/idp-a/unlink-entity
Code: 400. Errors:

* entity is a member of 1 SCIM-managed group(s); pass remove_memberships=true to proceed with removing group memberships
```

Nothing is changed. This is correct behavior.

## Step 8: Reproduce the bug — supply `remove_memberships` but not `unlink_aliases`

```bash
vault write identity/scim/client/idp-a/unlink-entity \
  entity_id=$EID \
  remove_memberships=true
```

Observed response:

```text
Key                   Value
---                   -----
unlinked_alias_ids    <nil>
unlinked_group_ids    [<group-uuid>]
```

`unlinked_group_ids` correctly reports the removed group. `unlinked_alias_ids: <nil>` implies the alias was not touched — but it was. Verify:

```bash
vault read -format=json identity/entity/id/$EID \
  | jq -c '{entity_owner:(.data.scim_client_id | if . == "" or . == null then "UNMANAGED — stripped WITHOUT consent" else . end), alias_owner:(.data.aliases[0].scim_client_id | if . == "" or . == null then "UNMANAGED — stripped WITHOUT consent" else . end), groups:.data.group_ids}'

vault read -format=json identity/group/id/$GROUP_ID \
  | jq -c '{members:.data.member_entity_ids}'
```

Observed (buggy) output:

```text
{"entity_owner":"UNMANAGED — stripped WITHOUT consent","alias_owner":"UNMANAGED — stripped WITHOUT consent","groups":[]}
{"members":[]}
```

The alias `scim_client_id` is empty (unmanaged) even though `unlink_aliases=true` was never passed. The group removal and alias removal both executed, but only the group removal was reported.

## Step 9: Contrast — correct behavior of `remove_memberships` flag

Reset the entity and group (repeat Steps 4–6), then call with only `remove_memberships=true` and no `unlink_aliases`:

```bash
vault write identity/scim/client/idp-a/unlink-entity \
  entity_id=$EID \
  remove_memberships=true
```

The group membership is removed and reported in `unlinked_group_ids`. Then call again with `unlink_aliases=true`:

```bash
vault write identity/scim/client/idp-a/unlink-entity \
  entity_id=$EID \
  unlink_aliases=true
```

Expected: alias ownership is removed and reported in `unlinked_alias_ids`.

The group flag enforces its contract; the alias flag does not.

## Audit log confirmation

The audit log response for the buggy call shows `unlinked_alias_ids: null` despite the alias ownership being cleared, giving no indication the alias was modified:

```json
{
  "response": {
    "data": {
      "unlinked_alias_ids": null,
      "unlinked_group_ids": ["<group-uuid>"]
    }
  }
}
```

A correct implementation would either return the stripped alias IDs in `unlinked_alias_ids` (if the operation is intentionally allowed) or reject the request with an error (if `unlink_aliases=true` is required to proceed).

## Cleanup

```bash
vault delete identity/entity/id/$EID
vault delete identity/group/id/$GROUP_ID
rm -f /tmp/gbody.json
```

## References

- [Vault SCIM client documentation](https://developer.hashicorp.com/vault/docs/concepts/scim)
- [identity/scim/client API](https://developer.hashicorp.com/vault/api-docs/secret/identity/scim)
