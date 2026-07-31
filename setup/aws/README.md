# AWS setup

Terraform for a quick Vault Enterprise dev server on EC2. See [terraform/](./terraform/README.md).

```bash
cd setup/aws/terraform
cp terraform.tfvars.example terraform.tfvars
export TF_VAR_vault_license="$VAULT_LICENSE"
terraform init && terraform apply
```

Teardown: `terraform destroy`.
