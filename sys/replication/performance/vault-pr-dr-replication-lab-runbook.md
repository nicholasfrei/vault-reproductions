# Vault Enterprise PR and DR Replication Lab Runbook

## Overview

This runbook deploys a nine-node Vault Enterprise lab across three integrated-storage clusters using Terraform on AWS. The three clusters form a full replication topology:

- Primary cluster (3 nodes)
- Performance replication secondary cluster (3 nodes)
- DR secondary cluster (3 nodes)
  
All clusters use AWS KMS auto unseal. Each cluster runs Vault Enterprise `2.0.0+ent`. All nodes share a VPC and security group so that inter-cluster replication traffic on ports 8200 and 8201 is permitted without additional configuration.

## Objective

- Deploy three independent Vault Raft clusters on AWS using Terraform.
- Initialize and unseal each cluster independently.
- Enable performance replication between the primary and the PR secondary.
- Enable DR replication between the primary and the DR secondary.
- Validate replication state on all three clusters.

## Architecture

```text
us-east-1 VPC (10.0.0.0/16)
|-- Subnet-1 (10.0.10.0/24, AZ-a)
|-- Subnet-2 (10.0.20.0/24, AZ-b)
`-- Subnet-3 (10.0.30.0/24, AZ-c)

Primary cluster
  vault-pr-lab-primary-1   10.0.10.10
  vault-pr-lab-primary-2   10.0.20.10
  vault-pr-lab-primary-3   10.0.30.10

Performance secondary cluster
  vault-pr-lab-pr-1        10.0.10.20
  vault-pr-lab-pr-2        10.0.20.20
  vault-pr-lab-pr-3        10.0.30.20

DR secondary cluster
  vault-pr-lab-dr-1        10.0.10.30
  vault-pr-lab-dr-2        10.0.20.30
  vault-pr-lab-dr-3        10.0.30.30
```

All nodes use m6i.large (2 vCPU, 8 GB RAM) with a 40 GiB encrypted gp3 root volume.

## Prerequisites

- AWS CLI configured on your workstation.
- AWS permissions to create VPC, EC2, IAM, and security group resources.
- Terraform `1.6.0` or newer on your workstation.
- An existing EC2 key pair in `us-east-1`.
- Vault Enterprise license with performance replication and DR replication entitlements.
- The license stored in your shell as `$VAULT_LICENSE`.

Do not commit `terraform.tfvars`, private key files, Vault root tokens, or license contents.

## Step 1: Configure Terraform Variables

Run this on your workstation from the repository root.

```bash
cd sys/replication/performance/terraform
cp terraform.tfvars.example terraform.tfvars
vi terraform.tfvars
```

Fill in the required values:

```hcl
aws_region     = "us-east-1"
aws_profile    = null
name_prefix    = "vault-pr-lab"
key_name       = "<ec2_key_pair_name>"
admin_ssh_cidr = "<your_admin_ip_cidr>"

instance_type    = "m6i.large"
root_volume_size = 40

vault_version   = "2.0.0"
vault_log_level = "info"
```

Pass the Vault Enterprise license as an environment variable:

```bash
export TF_VAR_vault_license="$VAULT_LICENSE"
```

## Step 2: Deploy the Infrastructure

Run Terraform from `sys/replication/performance/terraform`:

```bash
terraform init
terraform plan
terraform apply
```

Terraform creates:

- VPC, internet gateway, route table, and three public subnets in `us-east-1`.
- One security group shared by all nine nodes with intra-group rules for ports 8200 and 8201.
- Nine Amazon Linux 2023 EC2 instances with fixed private IPs.
- Vault Enterprise `2.0.0+ent`, license file, `vault.hcl`, `vault.env`, and systemd unit on each node.
- Vault is enabled and started automatically on every node.

## Step 3: Capture Terraform Outputs

Run this on your workstation.

```bash
terraform output
terraform output -json primary_nodes > /tmp/vault-primary-nodes.json
terraform output -json pr_secondary_nodes > /tmp/vault-pr-nodes.json
terraform output -json dr_secondary_nodes > /tmp/vault-dr-nodes.json
```

Export node IPs using `jq`:

```bash
export PRIMARY_1_PUBLIC_IP=$(jq -r '."vault-humana-lab-primary-1".public_ip' /tmp/vault-primary-nodes.json)
export PRIMARY_2_PUBLIC_IP=$(jq -r '."vault-humana-lab-primary-2".public_ip' /tmp/vault-primary-nodes.json)
export PRIMARY_3_PUBLIC_IP=$(jq -r '."vault-humana-lab-primary-3".public_ip' /tmp/vault-primary-nodes.json)

export PR_1_PUBLIC_IP=$(jq -r '."vault-humana-lab-pr-1".public_ip' /tmp/vault-pr-nodes.json)
export PR_2_PUBLIC_IP=$(jq -r '."vault-humana-lab-pr-2".public_ip' /tmp/vault-pr-nodes.json)
export PR_3_PUBLIC_IP=$(jq -r '."vault-humana-lab-pr-3".public_ip' /tmp/vault-pr-nodes.json)

export DR_1_PUBLIC_IP=$(jq -r '."vault-humana-lab-dr-1".public_ip' /tmp/vault-dr-nodes.json)
export DR_2_PUBLIC_IP=$(jq -r '."vault-humana-lab-dr-2".public_ip' /tmp/vault-dr-nodes.json)
export DR_3_PUBLIC_IP=$(jq -r '."vault-humana-lab-dr-3".public_ip' /tmp/vault-dr-nodes.json)

export PRIMARY_1_PRIVATE_IP=$(jq -r '."vault-humana-lab-primary-1".private_ip' /tmp/vault-primary-nodes.json)
export PR_1_PRIVATE_IP=$(jq -r '."vault-humana-lab-pr-1".private_ip' /tmp/vault-pr-nodes.json)
export DR_1_PRIVATE_IP=$(jq -r '."vault-humana-lab-dr-1".private_ip' /tmp/vault-dr-nodes.json)
```

Set the SSH key path:

```bash
export SSH_PRIVATE_KEY=<path_to_private_key>
```

## Step 4: Initialize and Join the Clusters

Initialize node 1 of each cluster. With AWS KMS auto-unseal, each node unseals automatically after `vault operator init`.

```bash
for HOST in \
  "$PRIMARY_1_PUBLIC_IP" "$PR_1_PUBLIC_IP" "$DR_1_PUBLIC_IP"
do
  ssh -i "$SSH_PRIVATE_KEY" ec2-user@"$HOST" "
    export VAULT_ADDR=http://127.0.0.1:8200
    vault status
    vault operator init -format=json > /tmp/vault-init.json
    chmod 0600 /tmp/vault-init.json
    jq -r '.root_token' /tmp/vault-init.json | VAULT_ADDR=http://127.0.0.1:8200 vault login -
  "
done
```

Join nodes 2 and 3 to each cluster using the private IP of node 1 as the leader address. After joining, each node restarts its seal mechanism and auto-unseals via KMS.

```bash
# Primary cluster — nodes 2 and 3 join primary-1
for HOST in "$PRIMARY_2_PUBLIC_IP" "$PRIMARY_3_PUBLIC_IP"; do
  ssh -i "$SSH_PRIVATE_KEY" ec2-user@"$HOST" "
    export VAULT_ADDR=http://127.0.0.1:8200
    vault operator raft join http://10.0.10.10:8200
    sudo systemctl restart vault
    sleep 5
    vault status
  "
done

# PR secondary cluster — nodes 2 and 3 join pr-1
for HOST in "$PR_2_PUBLIC_IP" "$PR_3_PUBLIC_IP"; do
  ssh -i "$SSH_PRIVATE_KEY" ec2-user@"$HOST" "
    export VAULT_ADDR=http://127.0.0.1:8200
    vault operator raft join http://10.0.10.20:8200
    sudo systemctl restart vault
    sleep 5
    vault status
  "
done

# DR secondary cluster — nodes 2 and 3 join dr-1
for HOST in "$DR_2_PUBLIC_IP" "$DR_3_PUBLIC_IP"; do
  ssh -i "$SSH_PRIVATE_KEY" ec2-user@"$HOST" "
    export VAULT_ADDR=http://127.0.0.1:8200
    vault operator raft join http://10.0.10.30:8200
    sudo systemctl restart vault
    sleep 5
    vault status
  "
done
```

Check the peers and autopilot state on all 3 clusters:

```bash
for HOST in \
  "$PRIMARY_1_PUBLIC_IP" "$PR_1_PUBLIC_IP" "$DR_1_PUBLIC_IP"
do
  ssh -i "$SSH_PRIVATE_KEY" ec2-user@"$HOST" "
    vault operator raft list-peers
    vault operator raft autopilot state
  "
done
```

## Step 5: Enable Performance Replication on the Primary

Run this on the active primary node (`primary-1` if it is still the leader):

```bash
ssh -i "$SSH_PRIVATE_KEY" ec2-user@"$PRIMARY_1_PUBLIC_IP" "
vault write -f sys/replication/performance/primary/enable
vault read sys/replication/performance/status
vault write sys/replication/performance/primary/secondary-token id='pr-secondary'
"
```

Save the `wrapping_token` from the output. It is a one-time-use wrapped token with a short TTL (typically 30 minutes). Pass it to the PR secondary in the next step before it expires.

## Step 6: Enable Performance Replication on the PR Secondary

Run this on the active PR secondary node (`pr-1`):

```bash
ssh -i "$SSH_PRIVATE_KEY" ec2-user@"$PR_1_PUBLIC_IP" "
vault write sys/replication/performance/secondary/enable \
  token='$wrapping_token_from_step_8'
vault read sys/replication/performance/status
"
```

The node will re-join as a secondary. This triggers a wipe and resync. Once complete, `pr-1` and the other PR secondary nodes will no longer have their own root tokens — authentication is federated through the primary.


Success looks like:

```text
Key                    Value
connection_state       ready
last_remote_wal        <wal_index>
mode                   secondary
primary_cluster_addr   https://10.0.10.10:8201
state                  stream-wals
```

## Step 7: Enable DR Replication on the Primary

Run this on the active primary node:

```bash
ssh -i "$SSH_PRIVATE_KEY" ec2-user@"$PRIMARY_1_PUBLIC_IP" "
vault write -f sys/replication/dr/primary/enable
vault read sys/replication/dr/status
vault write sys/replication/dr/primary/secondary-token id="dr-secondary"
"
```

Save the `wrapping_token` from the output.

## Step 8: Enable DR Replication on the DR Secondary

Run this on the active DR secondary node (`dr-1`):

```bash
ssh -i "$SSH_PRIVATE_KEY" ec2-user@"$DR_1_PUBLIC_IP" "
vault write sys/replication/dr/secondary/enable \
  token='$wrapping_token_from_step_10'
sleep 10
vault read sys/replication/dr/status
"
```

Success looks like:

```text
Key                    Value
connection_state       ready
last_remote_wal        <wal_index>
mode                   secondary
primary_cluster_addr   https://10.0.10.10:8201
state                  stream-wals
```

## Step 9: Enable Audit devices

Enable a file and syslog audit device: 

```bash
ssh -i "$SSH_PRIVATE_KEY" ec2-user@"$PRIMARY_1_PUBLIC_IP" "
vault audit enable file file_path=/var/log/vault/vault_audit_log.log
vault audit enable syslog tag=vault-audit
vault audit list --detailed
"
```

Success looks like:

```text
vault audit list --detailed
Path       Type      Description    Replication    Options
----       ----      -----------    -----------    -------
file/      file      n/a            replicated     file_path=/var/log/vault/vault_audit.log
syslog/    syslog    n/a            replicated     tag=vault-audit
```

## Step 10: Create Policies and User on the Primary 

Create 1,000 policies and then login with a user created with these policies attached:

```bash
# enable userpass auth method
vault auth enable userpass 2>/dev/null || true

# create 1,000 policies with a single wildcard capability
for i in $(seq -f '%05g' 1 1000); do
  vault policy write "test-policy-${i}" - <<EOF
path "*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
EOF
done

seq -f 'test-policy-%05g' 1 1000 | paste -sd, > /tmp/testuser-policies.csv

# create a user with all 1,000 policies attached
vault write auth/userpass/users/testuser \
  password="Password1!" \
  token_policies=@/tmp/testuser-policies.csv

# verify the user was created with all policies attached
vault read auth/userpass/users/testuser
```

## Step 11: Enable Secrets Engine And Login with the User

```bash
# Enable KV secrets engine at kv/ with version 2
vault secrets enable -version=2 kv

# login with the user
vault login -method=userpass username=testuser password="Password1!"
```

## Step 12: Run some tests! 

Small Test

```bash
for i in $(seq 1 500); do
  vault kv put "kv/test-d2-$i" data=data >/dev/null &
  while [ "$(jobs -r | wc -l)" -ge 25 ]; do
    sleep 0.1
  done
done
```

Large Test

```bash
head -c 50000 /dev/urandom | base64 | tr -d '\n' > /tmp/blob.txt
seq 1 10000 | xargs -P 50 -I {} vault kv put "kv/test-d2-{}" data=@/tmp/blob.txt >/dev/null
```


## Cleanup

Destroy the Terraform-managed lab from `sys/replication/performance/terraform`:

```bash
terraform destroy
```

Remove local temporary files:

```bash
rm -f /tmp/vault-primary-nodes.json /tmp/vault-pr-nodes.json /tmp/vault-dr-nodes.json
rm -f /tmp/vault-primary-init.json /tmp/vault-pr-init.json /tmp/vault-dr-init.json
```

## References

- https://developer.hashicorp.com/vault/docs/enterprise/replication
- https://developer.hashicorp.com/vault/docs/configuration/storage/raft
- https://developer.hashicorp.com/vault/docs/commands/operator/raft
- https://developer.hashicorp.com/vault/api-docs/system/replication/replication-performance
- https://developer.hashicorp.com/vault/api-docs/system/replication/replication-dr
