# Oracle Database Plugin Terraform Lab

This Terraform example creates three Vault Enterprise nodes on Amazon Linux 2023 for the Oracle database secrets engine reproduction. It does not configure Vault replication.

The EC2 startup script installs:

- Vault Enterprise from `releases.hashicorp.com`
- Oracle Instant Client Basic and SDK from Oracle's Linux Instant Client download URLs
- Oracle database plugin release artifact under `/etc/vault.d/plugins`
- Required OS packages including `libaio` and `libnsl`

## Usage

Copy the example variables file and set your local values:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Set the Vault Enterprise license outside of the file when possible:

```bash
export TF_VAR_vault_license="$VAULT_LICENSE"
```

Create the AWS infrastructure:

```bash
terraform init
terraform apply
```

After the nodes finish bootstrapping, SSH to one node and initialize Vault:

```bash
vault operator init
```

Use the generated unseal keys and initial root token according to your lab process. Auto-unseal is configured with AWS KMS, so restarts after initialization should not require manual unseal.

Then point the Vault provider at the initialized cluster and apply the plugin registration:

```bash
export TF_VAR_vault_addr="http://<vault_node_public_ip>:8200"
export TF_VAR_vault_token="<token>"
export TF_VAR_register_oracle_plugin=true
terraform apply
```

Do not also set `vault_addr`, `vault_token`, or `register_oracle_plugin` in `terraform.tfvars` when using the `TF_VAR_*` exports above. Values in `terraform.tfvars` take precedence over environment variables.

The plugin registration is declared as:

```hcl
resource "vault_plugin" "oracle" {
  count = var.register_oracle_plugin ? 1 : 0

  type    = "database"
  name    = "vault-plugin-database-oracle"
  version = "v0.14.1+ent"
}
```

## Validation

Check user data completion on each node:

```bash
sudo test -f /var/log/vault-user-data-complete
sudo journalctl -u vault --no-pager
```

Verify the Oracle client libraries are registered with the dynamic linker:

```bash
ldconfig -p | grep libclntsh
```

Verify the Oracle database plugin artifact exists before enabling Terraform plugin registration:

```bash
sudo test -x /etc/vault.d/plugins/vault-plugin-database-oracle_0.14.1+ent_linux_amd64/vault-plugin-database-oracle
```

Verify the plugin catalog entry after the second apply:

```bash
vault plugin info -version="0.14.1+ent" database vault-plugin-database-oracle
```
