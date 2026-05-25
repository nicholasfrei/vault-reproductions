# Terraform: AWS CloudHSM PKCS11 Seal Wrap KV Latency Lab

This Terraform scaffold creates the AWS infrastructure for the runbook one directory up:

- VPC, internet gateway, three public subnets, and route table
- Vault security group for SSH, Vault API, and Vault cluster traffic
- AWS CloudHSM cluster and one initial HSM
- IAM instance profile that allows Vault nodes to call `cloudhsm:DescribeClusters`
- Six Amazon Linux 2023 EC2 instances, with `vault-6` tagged as the non-voter
- Vault Enterprise `1.19.15+ent`, Vault system user, license file, systemd unit, and per-node `vault.hcl`
- Helper scripts for CloudHSM PKCS11 configuration, KV workload generation, and `tc netem` latency injection

It does not initialize the CloudHSM cluster or create HSM users. Continue with the runbook after `terraform apply` to initialize CloudHSM, configure the PKCS11 client with the customer CA, and start Vault.

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars
vi terraform.tfvars

# Recommended instead of writing secrets to terraform.tfvars:
export TF_VAR_vault_license="$(cat /path/to/vault.hclic)"
export TF_VAR_hsm_password='<hsm_crypto_user_password>'

terraform init
terraform plan
terraform apply
```

After apply, collect outputs:

```bash
terraform output
terraform output -json vault_nodes
terraform output -raw cloudhsm_cluster_id
```

Destroy the lab when finished:

```bash
terraform destroy
```

If CloudHSM deletion is blocked, delete any HSMs from the CloudHSM cluster first, wait for deletion to complete, and run `terraform destroy` again.
