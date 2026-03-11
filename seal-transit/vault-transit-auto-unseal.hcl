storage "file" {
  path = "vault-data-auto-unseal"
}

listener "tcp" {
  # Auto-unseal Vault listener (second Vault)
  address     = "127.0.0.1:8300"
  tls_disable = 1
}

api_addr     = "http://127.0.0.1:8300"
cluster_addr = "http://127.0.0.1:8301"

seal "transit" {
  # Transit Vault address (first Vault, running in dev mode)
  address     = "http://127.0.0.1:8200"
  # Token must have encrypt/decrypt/read capabilities on the transit key.
  # In dev, you can safely use a short-lived token created from the dev root token.
  token       = "TRANSIT_UNSEAL_TOKEN_PLACEHOLDER"

  # Transit configuration
  mount_path  = "transit/"
  key_name    = "autounseal-key"

  # Optional settings (left as defaults for dev):
  # disable_renewal = "false"
  # tls_server_name = ""
  # namespace       = ""
}

