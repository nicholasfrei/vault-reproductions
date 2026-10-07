terraform {
  required_providers {
    vault = { source = "hashicorp/vault" }
  }
}
provider "vault" {}

resource "vault_managed_keys" "repro" {
  gcp {
    name = "tf-repro"
    credentials = jsonencode({})
    project = "<project_id>"
    region = "us-central1"
    key_ring = "vault-repro"
    crypto_key = "vault-repro"
    crypto_key_version = "1"
    algorithm = "RSA_SIGN_PKCS1_4096_SHA256"
  }
}

