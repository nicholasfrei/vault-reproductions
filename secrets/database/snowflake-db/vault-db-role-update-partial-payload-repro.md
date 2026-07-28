# Vault Provider `vault_database_secret_backend_role` Partial Update Payload Bug in `2.0.2+ent`

## Overview

A customer is experiencing an issue in the Terraform Vault Provider (versions 5.8.0 through 5.10.1) where only changed attributes are included in the API request payload during an update. When Vault receives this partial payload, the database config is reset back to defaults for the values that did not change.  

- Vault 1.20.x: The endpoint preserves unchanged fields.
- Vault 2.0.2: The endpoint loses data for unchanged fields.

This only impacts `update` operations. `create` is not impacted. 

See [hashicorp/terraform-provider-vault#2966](https://github.com/hashicorp/terraform-provider-vault/issues/2966) for the upstream issue.

## Objective

Deploy a single-node Vault cluster on AWS, configure the database secrets engine with a mock Snowflake role, trigger an in-place update, and confirm the partial payload behavior. On `2.0.2`, this causes silent data loss.

## Prerequisites

- Terraform >= 1.12.2 (the `versions.tf` in `terraform/` enforces this)
- provider registry.terraform.io/hashicorp/vault v5.10.0
- AWS credentials with permissions to create VPC, EC2, KMS, and IAM resources
- An existing EC2 key pair in the target region
- A Vault Enterprise license
- Your local/admin IP CIDR (used to scope SSH and Vault API access)

The Terraform files for this repro live at:

```text
secrets/database/snowflake-db/terraform/
├── main.tf
├── outputs.tf
├── terraform.tfvars.example
├── user-data.sh.tftpl
├── variables.tf
└── versions.tf
```

## Infrastructure Setup

### 1. Configure tfvars

```bash
cd secrets/database/snowflake-db/terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` and fill in:

| Variable | Description |
|---|---|
| `key_name` | Your EC2 key pair name |
| `admin_ssh_cidr` | Your IP in CIDR form, e.g. `203.0.113.5/32` |
| `vault_version` | `2.0.2` to reproduce silent data loss; `1.20.5` for the alternate behavior |
| `vault_license` | Your Vault Enterprise license string (or set `TF_VAR_vault_license`) |

```bash
export TF_VAR_vault_license="$VAULT_LICENSE"
```

### 2. Deploy the cluster

```bash
terraform init
terraform apply
```

Once complete, note the outputs:

```bash
terraform output ssh_command
terraform output vault_addr
```

### 3. Initialize and unseal Vault

SSH into the node:

```bash
ssh ec2-user@<public_ip>
```

Wait for user data to finish, then initialize:

```bash
export VAULT_ADDR=http://127.0.0.1:8200

vault operator init -format=json | tee /tmp/vault-init.json

export VAULT_TOKEN=$(jq -r '.root_token' /tmp/vault-init.json)
```

Verify the node is active:

```bash
vault status
```

```text
Key                      Value
---                      -----
Seal Type                awskms
Recovery Seal Type       shamir
Initialized              true
Sealed                   false
Total Recovery Shares    5
Threshold                3
Version                  2.0.2+ent
Build Date               2026-06-04T13:15:06Z
Storage Type             raft
Cluster Name             vault-db-role-repro-cluster
HA Enabled               true
HA Cluster               https://10.0.10.10:8201
HA Mode                  active
```

### 4. Enable the database secrets engine

```bash
vault secrets enable database
```

### 5. Configure a Snowflake connection

Reference: [How to Configure Snowflake](../../../secrets/database/snowflake-db/approle-snowflake-db-runbook.md) for steps on how to configure Snowflake from scratch 

Use the information from the guide above to create the snowflake configuration.

```bash
export private_key=$(cat vault_demo_key.pem)

vault write database/config/snowflake \
  plugin_name=snowflake-database-plugin \
  allowed_roles="my-role" \
  connection_url="<account_uid>.snowflakecomputing.com" \
  username="repro_svc" \
  private_key="$private_key"
```

## Reproduction Steps w/Terraform Vault Provider

### Step 1 — Write the initial Terraform configuration

Create a working directory outside this repo (to avoid nested state files) and write the initial provider configuration:

```bash
mkdir -p /tmp/db-role-repro && cd /tmp/db-role-repro
```

Create `main.tf` and replace <public_ip> and <root_token>:

```hcl
terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "5.10.0"
    }
  }
  required_version = ">= 1.12.2"
}

provider "vault" {
  address = "http://<public_ip>:8200"
  token   = "<root_token>"
}

resource "vault_database_secret_backend_role" "example" {
  backend         = "database"
  name            = "my-role"
  db_name         = "snowflake"
  credential_type = "rsa_private_key"
  credential_config = {
    key_bits = 2048
    format   = "pkcs8"
  }
  default_ttl = 600
  max_ttl     = 7200

  creation_statements = [
    "CREATE USER {{name}} RSA_PUBLIC_KEY='{{public_key}}' DAYS_TO_EXPIRY={{expiration}} DEFAULT_ROLE=SOME_ROLE",
    "GRANT ROLE SOME_ROLE TO USER {{name}}"
  ]

  renew_statements    = ["ALTER USER {{name}} SET DAYS_TO_EXPIRY={{expiration}}"]
  rollback_statements = ["DROP USER {{name}}"]
}
```

### Step 2 — Apply the initial configuration

```bash
terraform init
terraform apply
```

Verify all fields were stored correctly on Vault:

```bash
vault read database/roles/my-role
```

```text
Key                      Value
---                      -----
creation_statements      [CREATE USER {{name}} RSA_PUBLIC_KEY='{{public_key}}' DAYS_TO_EXPIRY={{expiration}} DEFAULT_ROLE=SOME_ROLE GRANT ROLE SOME_ROLE TO USER {{name}}]
credential_config        map[format:pkcs8 key_bits:2048]
credential_type          rsa_private_key
db_name                  snowflake
default_ttl              10m
max_ttl                  2h
renew_statements         [ALTER USER {{name}} SET DAYS_TO_EXPIRY={{expiration}}]
rollback_statements      [DROP USER {{name}}]
```

### Step 3 — Trigger an in-place update by modifying only `creation_statements`

Edit `main.tf` and append `TYPE=SERVICE` to the first creation statement:

```hcl
  creation_statements = [
    "CREATE USER {{name}} RSA_PUBLIC_KEY='{{public_key}}' DAYS_TO_EXPIRY={{expiration}} DEFAULT_ROLE=SOME_ROLE TYPE=SERVICE",
    "GRANT ROLE SOME_ROLE TO USER {{name}}"
  ]
```

Apply the change:

```bash
terraform apply
```

>This is where the data loss is supposed to occur. I'm having an issue reproducing this at this point.
>When you read the config in step 4, the TTL values are supposed to be reset. I'm not seeing this behavior.

The provider detects only `creation_statements` changed and sends a partial payload to `PUT database/roles/my-role` containing only `creation_statements`, `db_name`, and `credential_config` (omitting `credential_type`, `default_ttl`, `max_ttl`, `renew_statements`, and `rollback_statements`).

### Step 4 — Read back the role and observe the result

```bash
vault read database/roles/my-role
```

Expected output:

```text
Key                      Value
---                      -----
creation_statements      [CREATE USER {{name}} RSA_PUBLIC_KEY='{{public_key}}' DAYS_TO_EXPIRY={{expiration}} DEFAULT_ROLE=SOME_ROLE  TYPE=SERVICE GRANT ROLE SOME_ROLE TO USER {{name}}]
credential_config        map[key_bits:2048]
credential_type          password
db_name                  snowflake
default_ttl              0s
max_ttl                  0s
renew_statements         []
rollback_statements      []
```

## Cleanup

From the Terraform working directory for the Vault infrastructure:

```bash
cd secrets/database/snowflake-db/terraform
terraform destroy
```

Remove the repro working directory:

```bash
cd /tmp/db-role-repro
terraform destroy
rm -rf /tmp/db-role-repro
```

## References

- [hashicorp/terraform-provider-vault#2966](https://github.com/hashicorp/terraform-provider-vault/issues/2966) — upstream issue tracking this bug
- [Vault Database Secrets Engine — Snowflake](https://developer.hashicorp.com/vault/docs/secrets/databases/snowflake)
- [vault_database_secret_backend_role resource docs](https://registry.terraform.io/providers/hashicorp/vault/latest/docs/resources/database_secret_backend_role)