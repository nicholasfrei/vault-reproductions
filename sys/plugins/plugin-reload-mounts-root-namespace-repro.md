# `vault plugin reload -mounts` Fails in the Root Namespace — Repro

## Overview

`vault plugin reload -mounts=<path>` fails when run against the root
namespace, even though `-mounts` is documented and intended to work in 
any namespace. The CLI silently ignores `-mounts` and sends the request 
to the wrong API, producing a `404 unsupported path` error:

```text
$ vault plugin reload -mounts=transit
Error reloading plugin/mounts: Error making API request.

URL: PUT http://127.0.0.1:8200/v1/sys/plugins/reload/unknown
Code: 404. Errors:

* 1 error occurred:
        * unsupported path
```

### Impacted versions

- Introduced in Vault CE `v1.16.0` / Vault Enterprise `v1.16.0+ent` by 
- Confirmed present on every branch checked:
  - CE: `main`
  - Enterprise: `main`, `release/1.19.x+ent`, `release/1.20.x+ent`,
    `release/1.21.x+ent`, `release/2.0.x+ent`, `release/2.1.x+ent`

## Objective

1. Reproduce the `404 unsupported path` failure of `vault plugin reload
   -mounts=<mount>` in the root namespace.
2. Confirm two working workarounds that bypass the buggy CLI branch.
3. Confirm each reload actually took effect (not just that the CLI/API
   returned success).

## Prerequisites

- A running Vault cluster, CE or Enterprise (single node is sufficient),
  any version from `1.16.0` / `1.16.0+ent` and later.
- `vault` CLI installed locally, matching the cluster version.
- A root token, or a token with `sudo` on `sys/mounts/*` and
  `update`/`create` on `sys/plugins/reload/backend`.
- `curl` installed locally for the API workaround.

## Steps

### 1. Set environment variables

```bash
export VAULT_ADDR="https://<vault-addr>:8200"
export VAULT_TOKEN="<root-token>"
```

### 2. Enable a scratch mount to reload against

```bash
vault secrets enable -path=transit transit
```

Expected output:

```text
Success! Enabled the transit secrets engine at: transit/
```

### 3. Reproduce the bug

```bash
vault plugin reload -mounts=transit
```

Expected (buggy) output:

```text
Error reloading plugin/mounts: Error making API request.

URL: PUT http://127.0.0.1:8200/v1/sys/plugins/reload/unknown
Code: 404. Errors:

* 1 error occurred:
        * unsupported path
```

Note the URL does not contain `transit` at all, and does not hit
`/v1/sys/plugins/reload/backend` — confirming the CLI took the wrong code
path and never sent the mount list to the server.

### 4. Workaround A — call the HTTP API directly

Bypasses the buggy CLI branch entirely by calling the correct endpoint,
`sys/plugins/reload/backend`, directly:

```bash
curl --header "X-Vault-Token: $VAULT_TOKEN" \
     --request POST \
     --data '{"mounts": ["transit/"]}' \
     "$VAULT_ADDR/v1/sys/plugins/reload/backend"
```

Expected output:

```json
{"request_id":"<uuid>","lease_id":"","renewable":false,"lease_duration":0,"data":{"reload_id":"<reload_uuid>"},"wrap_info":null,"warnings":null,"auth":null,"mount_type":"system"}
```

A `reload_id` in the response with no `errors` field confirms the request
reached the correct endpoint and was accepted.

### 5. Workaround B - Reload with global scope and check status

```bash
vault plugin reload -mounts=transit -scope=global
```

Expected output includes a `reload_id`:

```text
Success! Reloading mounts: [transit], reload_id: <reload_id>
```

Check status using the reload ID:

```bash
vault plugin reload-status <reload_id>
```

Expected output — one row per node/participant that processed the reload,
with a timestamp and success flag:

```text
Time     | Participant                          | Success | Message
15:04:05 | 3f1e2b4a-...                          | true    |
```

Note: `reload-status` (`sys/plugins/reload/backend/status`) is only
populated for reloads run with `-scope=global`. A plain local reload
(no `-scope`) never writes status entries.

### 6. Confirm via server logs (works for any scope — with a caveat)

Vault logs an info-level line for every mount it actually reloads, and the
logging call (`vault/plugin_reload.go:66`) is unconditional regardless of
`-scope`:

```bash
# journalctl example; adjust to your log collection method
journalctl -u vault --since "-2m" | grep "successfully reloaded plugin"
```

Expected output:

```text
... [INFO]  secrets.transit.transit_...: successfully reloaded plugin: plugin=transit path=transit/ version=
```

This confirms the specific mount, path, and (for external/versioned
plugins) running version that was actually swapped — independent of scope
and independent of the CLI/API response. In practice the plugin field will
include the mount's accessor suffix (e.g. `transit_1cdacd12`), which is
normal — it is the plugin type plus mount accessor, not an error.

### 7. Confirm functionally

Exercise the mount immediately after reload to confirm it is serving
requests normally:

```bash
vault write -f transit/keys/repro-key
vault read transit/keys/repro-key
```

Expected output:

```text
Success! Data written to: transit/keys/repro-key
```

## Validation

| Check | Command | Confirms |
|-------|---------|----------|
| Bug reproduces | `vault plugin reload -mounts=transit` (no namespace set) | `404 unsupported path`, URL missing the mount |
| Workaround A works | `curl ... /v1/sys/plugins/reload/backend` | `reload_id` returned, no error |
| Workaround B works | `VAULT_NAMESPACE=root vault plugin reload -mounts=transit` | `Success! Reloading mounts: [transit], reload_id: <reload_id>` |
| Server-side evidence (currently most reliable via direct `curl` / `-scope=global`; plain CLI `-mounts` was inconsistent in testing — see note in step 7) | `journalctl ... \| grep "successfully reloaded plugin"` | Log line naming the specific mount/path |
| Functional check | `vault write -f transit/keys/repro-key` | Mount responds normally post-reload |

## Cleanup

```bash
vault secrets disable transit
```

## Root cause

`command/plugin_reload.go:136` decides which API to call with:

```go
if client.Namespace() == "" {
    // calls RootReloadPlugin -> PUT /v1/sys/plugins/reload/:type/:name
} else {
    // calls ReloadPlugin -> PUT /v1/sys/plugins/reload/backend
}
```

This condition only checks whether a namespace was set on the client. It
does not also check whether `-mounts` was provided. Since the vast majority
of operators run `vault plugin reload` without setting `VAULT_NAMESPACE`
(i.e. against the root namespace, where `client.Namespace() == ""`), any
`-mounts=...` invocation there is routed to `RootReloadPlugin` instead —
which builds a request with an empty plugin name and `type=unknown`
(`RootReloadPluginInput{Plugin: "", Type: PluginTypeUnknown}`), producing a
URL of `/v1/sys/plugins/reload/unknown/` (server-normalized to
`/v1/sys/plugins/reload/unknown`). The server correctly rejects this as an
unsupported path. The `-mounts` value the operator supplied is never used.

See "Impacted versions" above for where this was introduced and where it
has been confirmed to still be present.

## References

- `command/plugin_reload.go:136` — buggy condition, `if client.Namespace()
  == "" {`, missing a `len(c.mounts) == 0` check before routing to
  `RootReloadPlugin`.
- `api/sys_plugins.go:352` — `RootReloadPlugin` builds
  `/v1/sys/plugins/reload/%s/%s` (type/name); called with an empty plugin
  name when this bug triggers.
- `api/sys_plugins.go:370` — `ReloadPlugin` (the correct path for
  `-mounts`), posts to `/v1/sys/plugins/reload/backend`.
- `command/plugin_reload_status.go` — `vault plugin reload-status` CLI,
  wraps `ReloadPluginStatus` (`GET /v1/sys/plugins/reload/backend/status`).
- `vault/plugin_reload_ent.go` — `entHandleGlobalPluginReload`,
  `writeReloadStatus`: status entries are only written for
  `-scope=global` reloads.
- `vault/logical_system_helpers_ent.go:728` — `handlePluginReloadStatus`,
  reads status entries written above; empty `results` for any reload_id
  from a non-global reload.
- Introduced by PR #24878, "New root namespace plugin reload API
  `sys/plugins/reload/:type/:name`" — see "Impacted versions" above for the
  full list of confirmed-affected branches/releases.