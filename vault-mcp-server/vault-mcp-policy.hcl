# Vault MCP Server Policy

# sys
path "sys/mounts" {
  capabilities = ["read", "list"]
}

path "sys/mounts/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# secret (KV v2)
path "secret/metadata/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/data/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

# PKI
path "pki/issuers/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "pki/roles/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "pki/issue/*" {
  capabilities = ["create", "update"]
}

# kv
path "kv/" {
  capabilities = ["read", "list"]
}

path "kv/*" {
  capabilities = ["read", "list"]
}

# kv-v2
path "kv-v2/" {
  capabilities = ["read", "list"]
}

path "kv-v2/*" {
  capabilities = ["read", "list"]
}

# kvv2
path "kvv2/metadata/" {
  capabilities = ["read", "list"]
}

path "kvv2/metadata/*" {
  capabilities = ["read", "list"]
}

path "kvv2/data/*" {
  capabilities = ["read"]
}
