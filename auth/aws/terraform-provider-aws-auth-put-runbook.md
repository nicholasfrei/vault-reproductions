# Vault Terraform Provider AWS Auth `PUT` Method Regression Runbook

## Summary

Customer is facing an issue in Vault version `1.10.11` when upgrading the Terraform Vault Provider from `5.6.0` to `5.7.0`. This upgrade results in the following error:

```
Error: Error making API request.
│
│ URL: PUT http://127.0.0.1:8200/v1/auth/aws/login
│ Code: 400. Errors:
│
│ * invalid iam_http_request_method; currently only 'POST' is supported
```

## Root cause

terraform-provider-vault v5.7.0 (PR [#2679](https://github.com/hashicorp/terraform-provider-vault/pull/2679)) migrated AWS auth credential handling from AWS SDK Go v1 to v2. The AWS SDK Go v2 presigner converts `GetCallerIdentity` requests to `GET` rather than `POST`. Vault versions prior to `1.15.0` only accept `POST` for `iam_http_request_method` and reject `GET` with the error above.

The Vault-side fix was introduced in PR [#10961](https://github.com/hashicorp/vault/pull/10961) and first released in Vault `1.15.0`. It was not backported to any `1.10.x`–`1.14.x` release.

| | Version |
|---|---|
| Vault: affected | `< 1.15.0` |
| Vault: fixed | `>= 1.15.0` |
| terraform-provider-vault: last working | `5.6.0` |
| terraform-provider-vault: regression introduced | `5.7.0` |

## Objective

Reproduce and confirm the regression introduced in terraform-provider-vault v5.7.0 that causes AWS auth logins to fail against Vault versions older than `1.15.0`.

## Prerequisites

- Vault version `1.10.11` in a working cluster
- Terraform CLI installed locally.
- AWS CLI configured on your workstation with permissions to create IAM users and attach policies.

## Step 1: Enable the AWS Auth Method in Vault

Use this step to mount the AWS auth method at the default path.

```bash
vault auth enable aws
```

Verify the mount is present:

```bash
vault auth list
```

```text
Path      Type    Accessor                Description
----      ----    --------                -----------
aws/      aws     auth_aws_<accessor>     n/a
token/    token   auth_token_<accessor>   token based credentials
```

Success looks like: `aws/` appears in the auth method list.

## Step 2: Create an IAM User for Vault AWS Auth

Use this step to create a dedicated IAM user whose credentials Vault will use to call the AWS STS API to verify login requests.

```bash
aws iam create-user --user-name vault-aws-auth
```

Attach the policy required for IAM-based auth. Vault needs `sts:GetCallerIdentity` to verify login requests, and `iam:GetUser` / `iam:GetRole` to resolve bound ARNs to internal IAM IDs when a role is created with `bound_iam_principal_arn`:

```bash
aws iam put-user-policy \
  --user-name vault-aws-auth \
  --policy-name vault-aws-auth-sts \
  --policy-document '{
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "sts:GetCallerIdentity",
          "iam:GetUser",
          "iam:GetRole"
        ],
        "Resource": "*"
      }
    ]
  }'
```

Create an access key for the user and save the output — you will need it in the next step:

```bash
aws iam create-access-key --user-name vault-aws-auth
```

```text
{
    "AccessKey": {
        "UserName": "vault-aws-auth",
        "AccessKeyId": "<access_key_id>",
        "Status": "Active",
        "SecretAccessKey": "<secret_access_key>",
        "CreateDate": "<timestamp>"
    }
}
```

Success looks like: an `AccessKeyId` and `SecretAccessKey` are returned. Store these securely — the secret is shown only once.

## Step 3: Configure Vault AWS Auth with the IAM Credentials

Use this step to give Vault the IAM credentials it needs to call STS on behalf of authenticating clients.

```bash
vault write auth/aws/config/client \
  access_key=<access_key_id> \
  secret_key=<secret_access_key> \
  sts_region=<aws_region>
```

Verify the configuration (the secret key is not returned):

```bash
vault read auth/aws/config/client
```

```text
Key                      Value
---                      -----
access_key               <access_key_id>
allowed_sts_header_values    []
endpoint                 n/a
iam_endpoint             n/a
iam_server_id_header_value    n/a
max_retries              -1
sts_endpoint             n/a
sts_region               <aws_region>
use_sts_region_from_client    false
```

Success looks like: the `access_key` and `sts_region` values reflect what you configured.

## Step 4: Create a Vault Policy for the Terraform Caller

Use this step to create a minimal policy that the AWS auth role will attach to tokens issued by this runbook.

```bash
vault policy write terraform-aws-auth - <<'EOF'
path "secret/data/*" {
  capabilities = ["read"]
}
path "auth/token/create" {
  capabilities = ["create", "update", "sudo"]
}

EOF
```

Success looks like: `Success! Uploaded policy: terraform-aws-auth`

## Step 5: Retrieve the IAM ARN for the Caller Identity

Use this step to find the IAM ARN of the identity (user or role) that Terraform will authenticate as. This is the principal the Vault AWS auth role will be bound to.

```bash
aws sts get-caller-identity
```

```text
{
    "UserId": "<user_id>",
    "Account": "<account_id>",
    "Arn": "arn:aws:iam::<account_id>:user/<iam_username>"
}
```

Note the `Arn` value. You will use it in the next step.

## Step 6: Create the Vault AWS Auth Role

Use this step to create the AWS auth role that binds the IAM ARN to the Vault policy. The `auth_type` is `iam`, which is the method the Terraform provider uses via `method = "aws"`.

```bash
vault write auth/aws/role/<iam_role_name> \
  auth_type=iam \
  bound_iam_principal_arn=arn:aws:iam::<account_id>:user/<iam_username> \
  token_policies=terraform-aws-auth \
  token_ttl=1h \
  token_max_ttl=4h
```

Verify the role:

```bash
vault read auth/aws/role/<iam_role_name>
```

```text
Key                         Value
---                         -----
auth_type                   iam
bound_iam_principal_arn     [arn:aws:iam::<account_id>:user/<iam_username>]
token_max_ttl               4h
token_policies              [terraform-aws-auth]
token_ttl                   1h
```

Success looks like: `auth_type` is `iam` and `bound_iam_principal_arn` matches the ARN from Step 5.

## Step 7: Confirm the Failing Provider Version

Use this step to initialize with the affected provider version and observe the error.

A provider block alone will not trigger authentication — the provider only authenticates when it needs to make a Vault API call. A data source forces a login attempt at plan time.

Create a working directory with the following `main.tf`:

```hcl
terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "5.7.0"
    }
  }
}

provider "vault" {
  address = "http://127.0.0.1:8200"

  auth_login {
    path   = "auth/aws/login"
    method = "aws"
    parameters = {
      role         = "<iam_role_name>"
      header_value = "127.0.0.1:8200"
      sts_region   = "<aws_region>"
    }
  }
}

data "vault_generic_secret" "test" {
  path = "secret/data/test"
}
```

Initialize and plan:

```bash
terraform init -upgrade
terraform plan
```

Expected Error: 

```
Error: Error making API request.
│
│ URL: PUT http://127.0.0.1:8200/v1/auth/aws/login
│ Code: 400. Errors:
│
│ * invalid iam_http_request_method; currently only 'POST' is supported
```

## Step 8: Confirm the Workaround — Pin to v5.6.0

Use this step to restore a working login by pinning the provider to the last known-good version.

Update the version constraint in `main.tf`:

```hcl
terraform {
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "5.6.0"
    }
  }
}
```

Re-initialize and plan:

```bash
terraform init -upgrade
terraform plan
```

The plan completes without error, confirming v5.6.0 login succeeds.

## Step 9: Confirm `iam_http_request_method` Does Not Resolve the Issue

Use this step to document that adding `iam_http_request_method = "POST"` to the `auth_login` block does not fix the regression.

Add the parameter with the v5.7.0 constraint still set:

```hcl
provider "vault" {
  address = "http://127.0.0.1:8200"

  auth_login {
    path   = "auth/aws/login"
    method = "aws"
    parameters = {
      role                    = "<iam_role_name>"
      header_value            = "127.0.0.1:8200"
      sts_region              = "<aws_region>"
      iam_http_request_method = "POST"
    }
  }
}
```

```bash
terraform init -upgrade
terraform plan
```

This does not fix the issue. 

## References

- [Vault Terraform Provider Changelog](https://github.com/hashicorp/terraform-provider-vault/blob/main/CHANGELOG.md)
- [Vault AWS Auth Method — Login endpoint](https://developer.hashicorp.com/vault/api-docs/auth/aws#login)
- [Terraform Provider `auth_login` documentation](https://registry.terraform.io/providers/hashicorp/vault/latest/docs#auth_login)