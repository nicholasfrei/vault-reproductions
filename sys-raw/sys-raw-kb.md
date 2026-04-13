# Vault sys/raw Endpoint KB

This KB contains information about the `/sys/raw` endpoint in Vault. This endpoint is intended for very specific use cases when no other options are available. It is not meant for general use and should be used with caution. This article will be updated over time as I add more information about the `/sys/raw` endpoint. Please refer to the official Vault documentation for the most up-to-date information.

Writing to or deleting from `/sys/raw` bypasses Vault's internal validation, logic, and safety checks. As noted above, this endpoint should only be used as a last resort. It can still be useful when there are phantom entries in the storage backend or corrupted leases or data that cannot be fixed through any other method.

## Overview of `/sys/raw` Endpoint

The `/sys/raw` endpoint is used to access the raw underlying store in Vault. It is off by default.

To enable the `/sys/raw` endpoint, set the `raw_storage_endpoint` configuration option to `true` in your Vault configuration file [docs](https://developer.hashicorp.com/vault/docs/configuration#raw_storage_endpoint). Once enabled, you can access the raw store by sending requests to the `/sys/raw` endpoint.

Here is a sample request to the `/sys/raw` endpoint:

```bash
/ $ vault read -format=json sys/raw/sys/policy/default
{
  "request_id": "<request_id>",
  "lease_id": "",
  "lease_duration": 0,
  "renewable": false,
  "data": {
    "value": "{\"EnforcementLevel\":\"\",\"EGPPaths\":null,\"ParsedEGPPaths\":null,\"Version\":2,\"Raw\":\"\
# Allow tokens to look up their own properties\
path "auth/token/lookup-self" {\
    capabilities = ["read"]\
}\
\
# Allow tokens to renew themselves\
path "auth/token/renew-self" {\
    capabilities = ["update"]\
}\
\
# Allow tokens to revoke themselves\
path "auth/token/revoke-self" {\
    capabilities = ["update"]\
}\
\
# Allow a token to look up its own capabilities on a path\
path "sys/capabilities-self" {\
    capabilities = ["update"]\
}\
\
# Allow a token to look up its own entity by id or name\
path "identity/entity/id/{{identity.entity.id}}" {\
  capabilities = ["read"]\
}\
path "identity/entity/name/{{identity.entity.name}}" {\
  capabilities = ["read"]\
}\
\
\
# Allow a token to look up its resultant ACL from all policies. This is useful\
# for UIs. It is an internal path because the format may change at any time\
# based on how the internal ACL features and capabilities change.\
path "sys/internal/ui/resultant-acl" {\
    capabilities = ["read"]\
}\
\
# Allow a token to renew a lease via lease_id in the request body; old path for\
# old clients, new path for newer\
path "sys/renew" {\
    capabilities = ["update"]\
}\
path "sys/leases/renew" {\
    capabilities = ["update"]\
}\
\
# Allow looking up lease properties. This requires knowing the lease ID ahead\
# of time and does not divulge any sensitive information.\
path "sys/leases/lookup" {\
    capabilities = ["update"]\
}\
\
# Allow a token to manage its own cubbyhole\
path "cubbyhole/*" {\
    capabilities = ["create", "read", "update", "delete", "list"]\
}\
\
# Allow a token to wrap arbitrary values in a response-wrapping token\
path "sys/wrapping/wrap" {\
    capabilities = ["update"]\
}\
\
# Allow a token to look up the creation time and TTL of a given\
# response-wrapping token\
path "sys/wrapping/lookup" {\
    capabilities = ["update"]\
}\
\
# Allow a token to unwrap a response-wrapping token. This is a convenience to\
# avoid client token swapping since this is also part of the response wrapping\
# policy.\
path "sys/wrapping/unwrap" {\
    capabilities = ["update"]\
}\
\
# Allow general purpose tools\
path "sys/tools/hash" {\
    capabilities = ["update"]\
}\
path "sys/tools/hash/*" {\
    capabilities = ["update"]\
}\
\
# Allow checking the status of a Control Group request if the user has the\
# accessor\
path "sys/control-group/request" {\
    capabilities = ["update"]\
}\
\
# Allow a token to make requests to the Authorization Endpoint for OIDC providers.\
path "identity/oidc/provider/+/authorize" {\
    capabilities = ["read", "update"]\
}\
\",\"Templated\":true,\"Type\":0}
"
  },
  "warnings": null,
  "mount_type": "system"
}
```

## sys/raw Utility Script

There is a utility script at `sys-raw/sys-raw-inspector.sh` for two common support tasks:

1. Printing an ASCII tree of mounted logical and auth storage by resolving mount UUIDs from `core/mounts` and `core/auth`.
2. Recursively searching raw storage responses for a UUID or other string under a chosen starting path.

Example usage:

```bash
export VAULT_ADDR="https://127.0.0.1:8200"
export VAULT_TOKEN="..."

# Walk logical/auth storage and write output to sys-raw/vault_storage_tree.txt
./sys-raw/sys-raw-inspector.sh tree

# Search under sys/raw/core for a UUID or other substring
./sys-raw/sys-raw-inspector.sh search --needle "<uuid>" --start-path "sys/raw/core"
```

Dependencies:

- `vault`
- `jq`

If you are testing against a lab instance with self-signed TLS, use the normal Vault CLI environment variables such as `VAULT_SKIP_VERIFY=true`, `VAULT_CACERT`, or `VAULT_CAPATH` before running the script.

## References

1. [Vault API Documentation for `/sys/raw` Endpoint](https://developer.hashicorp.com/vault/api-docs/system/raw)
2. [Vault Configuration Required for `/sys/raw` Endpoint](https://developer.hashicorp.com/vault/docs/configuration#raw_storage_endpoint)