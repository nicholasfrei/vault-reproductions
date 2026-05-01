# AWS KMS Auto-Unseal Runbook (EC2 + Vault Enterprise)

This runbook sets up `awskms` auto-unseal using an EC2 instance. Please follow each step carefully, and refer to the official Vault documentation for more details on the AWS KMS seal configuration if you run into any issues. For more advanced users, please feel free to use the Terraform files in the following [Github Repo](https://github.com/hashicorp/vault-guides/tree/master/operations/aws-kms-unseal/terraform-aws) to automate the configuration and setup.

## Overview

Goal:
- Create the AWS resources needed for AWS KMS auto-unseal manually.
- Attach the resulting instance profile to an existing EC2 instance.
- Configure Vault to use an EC2 instance profile for AWS KMS access.
- Validate that Vault auto-unseals after restart.

What this runbook uses:
- Amazon Linux 2023
- Single-node `raft` storage
- A manually created KMS key, IAM role, inline policy, and instance profile

This runbook uses AWS CLI examples. If you prefer the AWS Console, create the same resources in KMS and IAM and attach the instance profile to the EC2 instance using the same values.

## Preconditions

Before starting, ensure you have:
- AWS permissions to create and manage KMS keys, IAM roles/policies/instance profiles, EC2 instances, security groups, and key pairs.
- AWS CLI configured on your workstation.
- A running Amazon Linux EC2 instance that you can reach over SSH.
- The EC2 instance ID and public IP or DNS name.
- Vault Enterprise license text (`.hclic` content).
- A chosen Vault version (`+ent` build), for example `1.21.0`.

## Step 1: Set Environment Variables

Use this step on your workstation to define the names used throughout the runbook.

```bash
export AWS_REGION=us-east-1
export VAULT_VERSION=1.21.0

export VAULT_KMS_ALIAS=vault-auto-unseal
export VAULT_ROLE_NAME=vault-kms-unseal-role
export VAULT_POLICY_NAME=vault-kms-unseal-policy
export VAULT_INSTANCE_PROFILE_NAME=vault-kms-unseal-profile

export INSTANCE_ID=<EXISTING_INSTANCE_ID>
export EC2_PUBLIC_IP=<EXISTING_INSTANCE_PUBLIC_IP_OR_DNS>
```

## Step 2: Create the AWS KMS Key

Use this step to create the KMS key and alias that Vault will use in the seal stanza.

```bash
read KMS_KEY_ID KMS_KEY_ARN <<<"$(aws kms create-key \
  --region "$AWS_REGION" \
  --description 'Vault unseal key' \
  --tags TagKey=Name,TagValue=vault-kms-unseal \
  --query 'KeyMetadata.[KeyId,Arn]' \
  --output text)"

aws kms create-alias \
  --region "$AWS_REGION" \
  --alias-name "alias/$VAULT_KMS_ALIAS" \
  --target-key-id "$KMS_KEY_ID"

printf 'KMS_KEY_ID=%s\nKMS_KEY_ARN=%s\n' "$KMS_KEY_ID" "$KMS_KEY_ARN"
```

Success looks like:
```text
You have a KMS key ID and ARN for the Vault seal stanza.
```

## Step 3: Create the IAM Role, Inline Policy, and Instance Profile

Use this step to create the role that grants the EC2 instance access to the KMS key.

```bash
cat > trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

cat > kms-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "VaultKMSUnseal",
      "Effect": "Allow",
      "Action": [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:DescribeKey"
      ],
      "Resource": "$KMS_KEY_ARN"
    }
  ]
}
EOF

aws iam create-role \
  --role-name "$VAULT_ROLE_NAME" \
  --assume-role-policy-document file://trust-policy.json

aws iam put-role-policy \
  --role-name "$VAULT_ROLE_NAME" \
  --policy-name "$VAULT_POLICY_NAME" \
  --policy-document file://kms-policy.json

aws iam create-instance-profile \
  --instance-profile-name "$VAULT_INSTANCE_PROFILE_NAME"

aws iam add-role-to-instance-profile \
  --instance-profile-name "$VAULT_INSTANCE_PROFILE_NAME" \
  --role-name "$VAULT_ROLE_NAME"
```

Success looks like:
```text
The instance profile contains the EC2 role with KMS permissions scoped to the new key.
```

## Step 4: Attach the Instance Profile to the Existing EC2 Instance

Use this step to attach the instance profile to the existing Vault host.

```bash
aws ec2 associate-iam-instance-profile \
  --region "$AWS_REGION" \
  --instance-id "$INSTANCE_ID" \
  --iam-instance-profile Name="$VAULT_INSTANCE_PROFILE_NAME"

aws ec2 describe-iam-instance-profile-associations \
  --region "$AWS_REGION" \
  --filters Name=instance-id,Values="$INSTANCE_ID" \
  --query 'IamInstanceProfileAssociations[0].[State,IamInstanceProfile.Arn]' \
  --output table
```

Success looks like:
```text
The instance profile association state is `associated`.
```

## Step 5: Connect to EC2 and Confirm the Instance Profile

Use this step to confirm the host is getting AWS credentials from instance metadata.

```bash
ssh -i <PATH_TO_EXISTING_PEM> ec2-user@"$EC2_PUBLIC_IP"

TOKEN=$(curl -s -X PUT \
  http://169.254.169.254/latest/api/token \
  -H 'X-aws-ec2-metadata-token-ttl-seconds: 21600')

curl -s \
  -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/iam/info
```

Success looks like:
```text
The metadata response shows the attached instance profile ARN.
```

## Step 6: Install Host Dependencies

Use this step to prepare the host with required tooling.

```bash
sudo dnf -y update
sudo dnf -y install unzip jq wget
```

Success looks like:
```text
All dependency packages install without dnf errors.
```

## Step 7: Download and Install Vault Enterprise Binary

Use this step to install Vault Enterprise to `/usr/local/bin`.

```bash
cd /tmp

wget "https://releases.hashicorp.com/vault/${VAULT_VERSION}+ent/vault_${VAULT_VERSION}+ent_linux_amd64.zip"
unzip "vault_${VAULT_VERSION}+ent_linux_amd64.zip"

sudo mv vault /usr/local/bin/vault
sudo chmod 0755 /usr/local/bin/vault
vault version
```

Success looks like:
```text
Vault v1.21.0+ent
```

## Step 8: Create Vault User, Directories, and Permissions

Use this step to create runtime paths used by `raft`, config, and logs.

```bash
sudo useradd --system --home /etc/vault.d --shell /bin/false vault || true

sudo mkdir -p /etc/vault.d
sudo mkdir -p /opt/vault/data
sudo mkdir -p /var/log/vault

sudo chown -R vault:vault /etc/vault.d /opt/vault /var/log/vault
sudo chmod 0750 /etc/vault.d
sudo chmod 0750 /opt/vault/data
```

Success looks like:
```text
Directories exist and are owned by user/group `vault`.
```

## Step 9: Install Vault Enterprise License on the Host

Use this step to place the license where only privileged users can read it.

```bash
sudo vi /etc/vault.d/vault.hclic
sudo chown root:vault /etc/vault.d/vault.hclic
sudo chmod 0640 /etc/vault.d/vault.hclic
```

## Step 10: Create the Vault Environment File

Use this step to expose only the values Vault needs when it is using the EC2 instance profile.

```bash
sudo tee /etc/vault.d/vault.env > /dev/null <<'EOF'
VAULT_LICENSE_PATH=/etc/vault.d/vault.hclic
AWS_REGION=<AWS_REGION>
EOF

sudo chown root:vault /etc/vault.d/vault.env
sudo chmod 0640 /etc/vault.d/vault.env
```

Use the same region value you used when creating the KMS key.

## Step 11: Create the Vault Server Configuration

Use this step to configure listener, storage, and the `awskms` seal.

Use the `KMS_KEY_ID` or `KMS_KEY_ARN` from Step 2. Do not add static AWS credentials to the seal stanza.

```bash
sudo tee /etc/vault.d/vault.hcl > /dev/null <<'EOF'
ui = true
disable_mlock = true

api_addr = "http://127.0.0.1:8200"
cluster_addr = "http://127.0.0.1:8201"

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}

storage "raft" {
  path    = "/opt/vault/data"
  node_id = "vault-ec2-1"
}

seal "awskms" {
  region     = "<AWS_REGION>"
  kms_key_id = "<KMS_KEY_ID_OR_ARN>"
}
EOF

sudo chown root:vault /etc/vault.d/vault.hcl
sudo chmod 0640 /etc/vault.d/vault.hcl
```

Success looks like:
```text
Vault is configured to use the attached EC2 instance profile for AWS KMS access.
```

## Step 12: Create and Start the Vault systemd Service

Use this step to run Vault as a managed service.

```bash
sudo tee /etc/systemd/system/vault.service > /dev/null <<'EOF'
[Unit]
Description=HashiCorp Vault
Documentation=https://developer.hashicorp.com/vault/docs
After=network-online.target
Wants=network-online.target

[Service]
User=vault
Group=vault
ExecStart=/usr/local/bin/vault server -config=/etc/vault.d/vault.hcl
ExecReload=/bin/kill --signal HUP $MAINPID
KillMode=process
KillSignal=SIGINT
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
EnvironmentFile=/etc/vault.d/vault.env

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable vault
sudo systemctl start vault
sudo systemctl status vault --no-pager
```

If startup fails, check logs:

```bash
sudo journalctl -u vault -n 100 --no-pager
```

Success looks like:
```text
The Vault service starts successfully without static AWS credentials on disk.
```

## Step 13: Initialize Vault Once and Validate Health

Use this step to initialize the new cluster and confirm it is serving requests.

```bash
export VAULT_ADDR=http://127.0.0.1:8200
vault status

vault operator init > /tmp/vault-init.txt
cat /tmp/vault-init.txt
```

Success looks like:
```text
`vault status` shows `Initialized: false` before init and `Initialized: true` after init.
`vault status` shows `Sealed: false` after init completes.
```

## Step 14: Restart Vault and Confirm Auto-Unseal

Use this step to verify KMS-based unseal after process restart.

```bash
sudo systemctl restart vault
sleep 2
vault status
```

Success looks like:
```text
`Sealed: false` without running `vault operator unseal`.
```

## Cleanup

Warning: The following commands are destructive and remove AWS resources and local Vault data.

On the EC2 instance (stop vault service and delete instance in AWS):

```bash
sudo systemctl stop vault
```

On your workstation:

```bash
ASSOCIATION_ID=$(aws ec2 describe-iam-instance-profile-associations \
  --region "$AWS_REGION" \
  --filters Name=instance-id,Values="$INSTANCE_ID" \
  --query 'IamInstanceProfileAssociations[0].AssociationId' \
  --output text)

aws ec2 disassociate-iam-instance-profile \
  --region "$AWS_REGION" \
  --association-id "$ASSOCIATION_ID"

aws iam remove-role-from-instance-profile \
  --instance-profile-name "$VAULT_INSTANCE_PROFILE_NAME" \
  --role-name "$VAULT_ROLE_NAME"

aws iam delete-instance-profile \
  --instance-profile-name "$VAULT_INSTANCE_PROFILE_NAME"

aws iam delete-role-policy \
  --role-name "$VAULT_ROLE_NAME" \
  --policy-name "$VAULT_POLICY_NAME"

aws iam delete-role --role-name "$VAULT_ROLE_NAME"

aws kms delete-alias \
  --region "$AWS_REGION" \
  --alias-name "alias/$VAULT_KMS_ALIAS"

aws kms schedule-key-deletion \
  --region "$AWS_REGION" \
  --key-id "$KMS_KEY_ID" \
  --pending-window-in-days 7
```

Remove the temporary policy files from your workstation:

```bash
rm -f trust-policy.json kms-policy.json
```

## Conclusion

This runbook creates the AWS KMS key, IAM role, inline policy, and instance profile manually, attaches that profile to an existing EC2 instance, then installs Vault Enterprise on Amazon Linux 2023 and validates KMS-based auto-unseal after restart.

## References

- https://developer.hashicorp.com/vault/docs/configuration/seal/awskms
- https://developer.hashicorp.com/vault/tutorials/auto-unseal/autounseal-aws-kms
