# AWS CloudHSM PKCS11 Seal Wrap KV Latency Reproduction Runbook

## Overview

This runbook builds a Vault Enterprise lab with 6 EC2 instances using integrated storage, AWS CloudHSM PKCS#11 auto-unseal, and a seal-wrapped KV v2 secrets engine (all using terraform). There are manual steps for CloudHSM initialization, CloudHSM crypto-user creation, Vault initialization, and the latency workload.

The goal is to reproduce Vault log messages like:

```text
POTENTIAL DEADLOCK:
Previous place where the lock was grabbed
goroutine <id> lock <addr>
.../vault/sealwrap_backend_ent.go:417 vault.(*sealWrapBackend).getUnderlying
.../vault/sealwrap_backend_ent.go:437 vault.(*sealWrapBackend).getInternal
.../vault/sealwrap_backend_ent.go:292 vault.(*sealWrapBackend).privateGet
```

Run this in a sandbox AWS account. 

## Objective

- Deploy the AWS lab with Terraform in `us-east-1`.
- Install and configure Vault Enterprise `v1.19.15+ent.hsm` on six EC2 instances.
- Configure five integrated storage voters and one permanent non-voter.
- Configure AWS CloudHSM Client SDK 5 PKCS#11 as the Vault seal.
- Enable KV v2 with `seal_wrap=true`.
- Load 10,000 KV secrets with configurable concurrency and payload size.
- Add `5000ms` latency with `1000ms` jitter to CloudHSM network traffic.
- Validate whether Vault emits `POTENTIAL DEADLOCK` messages under seal-wrap pressure.

## Architecture

```text
us-east-1 VPC
|-- AWS CloudHSM cluster
|   `-- HSM ENI private IPs on TCP 2223-2225
`-- Vault EC2 instances, Amazon Linux 2023
    |-- vault-1  raft voter, initial leader candidate
    |-- vault-2  raft voter
    |-- vault-3  raft voter
    |-- vault-4  raft voter
    |-- vault-5  raft voter
    `-- vault-6  raft non-voter
```

Vault talks to a local PKCS#11 library, and the AWS CloudHSM PKCS#11 library talks to CloudHSM over the VPC. Because of that, this runbook injects latency with Linux `tc netem` on each Vault node, targeting the CloudHSM HSM ENI private IPs (`CLOUDHSM_IPS` captured in Step 5).

The EC2 instances are m6i.large (2 vCPU, 8 GB RAM). 

## Prerequisites

Before starting, ensure you have:

- AWS permissions to create and delete VPC, EC2, IAM, security group, and CloudHSM resources.
- AWS CLI configured on your workstation.
- Terraform `1.6.0` or newer on your workstation.
- An existing EC2 key pair in `us-east-1`.
- OpenSSL on the workstation for CloudHSM cluster initialization.
- Vault Enterprise license text (`.hclic` content) with HSM/seal wrap entitlement.
- A disposable test environment.

Do not commit `terraform.tfvars`, public IPs, private keys, HSM user passwords, Vault root tokens, or Vault license contents.

## Step 1: Configure Terraform Variables

Run this on your workstation from the repository root.

```bash
cd sys/seal/pkcs11/terraform
cp terraform.tfvars.example terraform.tfvars
vi terraform.tfvars
```

Use `terraform.tfvars` for non-sensitive lab values:

```hcl
aws_region     = "us-east-1"
aws_profile    = null
name_prefix    = "vault-hsm-deadlock"
key_name       = "<ec2_key_pair_name>"
admin_ssh_cidr = "<your_admin_ip_cidr>"

ami_id           = null
instance_type    = "m6i.large"
root_volume_size = 40

vault_version = "1.19.15"

hsm_user             = "vault_user"
hsm_token_label      = "cavium"
hsm_key_label        = "vault-hsm-key"
hsm_hmac_key_label   = "vault-hsm-hmac-key"
pkcs11_max_parallel  = 1

extra_tags = {
  Owner = "<email_or_name>"
}
```

`pkcs11_max_parallel = 1` forces Vault to serialize PKCS#11 calls into the HSM. This amplifies lock contention under added latency, which is the condition this runbook is trying to surface.

Set the Vault license and HSM crypto user password as environment variables to avoid writing secrets to disk. Terraform will pass them to the Vault nodes for the systemd service environment:

```bash
export AWS_REGION="us-east-1"
export TF_VAR_vault_license="$(cat /path/to/vault.hclic)"
export TF_VAR_hsm_password='<hsm_crypto_user_password>'
```

AWS CloudHSM enforces password complexity on the crypto user (minimum 7 characters, with at least one upper-case letter, one lower-case letter, & one digit). Pick a value that satisfies those rules now — if it does not, CloudHSM will reject it interactively in Step 6 and Vault will fail to log in to the HSM.

The CloudHSM crypto user and password are placed on the Vault nodes for the systemd service in this step, but the user itself is not created inside CloudHSM until Step 6.

## Step 2: Deploy the AWS Infrastructure and Vault Hosts

Run Terraform from `sys/seal/pkcs11/terraform`.

```bash
terraform init
terraform plan
terraform apply
```

Terraform creates:

- VPC, internet gateway, route table, and three public subnets in `us-east-1`.
- Vault security group and CloudHSM cluster security group attachment.
- AWS CloudHSM cluster with one initial HSM.
- IAM instance profile allowing Vault nodes to call `cloudhsm:DescribeClusters`.
- Six Amazon Linux 2023 EC2 instances with fixed private IPs.
- Vault Enterprise `v1.19.15+ent.hsm`, Vault license file, `vault.hcl`, `vault.env`, and systemd unit.
- Helper scripts in `/opt/vault/scripts/`.

The Vault service is enabled but intentionally not started until CloudHSM is initialized and the PKCS#11 client is configured.

## Step 3: Capture Terraform Outputs

Run this on your workstation.

```bash
terraform output
terraform output -json vault_nodes > /tmp/vault-hsm-nodes.json
export CLOUDHSM_CLUSTER_ID=$(terraform output -raw cloudhsm_cluster_id)
```

Extract the node addresses if you have `jq` locally:

```bash
export VAULT_1_PUBLIC_IP=$(jq -r '."vault-1".public_ip' /tmp/vault-hsm-nodes.json)
export VAULT_2_PUBLIC_IP=$(jq -r '."vault-2".public_ip' /tmp/vault-hsm-nodes.json)
export VAULT_3_PUBLIC_IP=$(jq -r '."vault-3".public_ip' /tmp/vault-hsm-nodes.json)
export VAULT_4_PUBLIC_IP=$(jq -r '."vault-4".public_ip' /tmp/vault-hsm-nodes.json)
export VAULT_5_PUBLIC_IP=$(jq -r '."vault-5".public_ip' /tmp/vault-hsm-nodes.json)
export VAULT_6_PUBLIC_IP=$(jq -r '."vault-6".public_ip' /tmp/vault-hsm-nodes.json)

export VAULT_1_PRIVATE_IP=$(jq -r '."vault-1".private_ip' /tmp/vault-hsm-nodes.json)
export VAULT_2_PRIVATE_IP=$(jq -r '."vault-2".private_ip' /tmp/vault-hsm-nodes.json)
export VAULT_3_PRIVATE_IP=$(jq -r '."vault-3".private_ip' /tmp/vault-hsm-nodes.json)
export VAULT_4_PRIVATE_IP=$(jq -r '."vault-4".private_ip' /tmp/vault-hsm-nodes.json)
export VAULT_5_PRIVATE_IP=$(jq -r '."vault-5".private_ip' /tmp/vault-hsm-nodes.json)
export VAULT_6_PRIVATE_IP=$(jq -r '."vault-6".private_ip' /tmp/vault-hsm-nodes.json)
```

Success looks like:

```text
You have the CloudHSM cluster ID and the public/private IP addresses for vault-1 through vault-6.
```

## Step 4: Initialize the CloudHSM Cluster

Run this on your workstation.

```bash
aws cloudhsmv2 describe-clusters \
  --region $AWS_REGION \
  --filters clusterIds="$CLOUDHSM_CLUSTER_ID" \
  --query 'Clusters[0].[State,Hsms[0].State,SecurityGroup]' \
  --output table
```

Wait until the HSM exists and the cluster is ready to initialize. The HSM must report `ACTIVE` before the CSR is available:

```bash
while [ "$(aws cloudhsmv2 describe-clusters \
  --region $AWS_REGION \
  --filters clusterIds="$CLOUDHSM_CLUSTER_ID" \
  --query 'Clusters[0].Hsms[0].State' \
  --output text)" != "ACTIVE" ]; do
  printf 'waiting for HSM to become ACTIVE...\n'
  sleep 30
done
```

Then download the cluster CSR:

```bash
aws cloudhsmv2 describe-clusters \
  --region $AWS_REGION \
  --filters clusterIds="$CLOUDHSM_CLUSTER_ID" \
  --query 'Clusters[0].Certificates.ClusterCsr' \
  --output text > "${CLOUDHSM_CLUSTER_ID}_ClusterCsr.csr"
```

Create a lab root CA and sign the CloudHSM CSR:

```bash
openssl genrsa -out customerRootCA.key 2048

openssl req -new -x509 -days 3652 \
  -key customerRootCA.key \
  -out customerRootCA.crt \
  -subj "/C=US/ST=Lab/L=Lab/O=VaultRepro/OU=CloudHSM/CN=vault-hsm-deadlock-root-ca"

openssl x509 -req -days 3652 \
  -in "${CLOUDHSM_CLUSTER_ID}_ClusterCsr.csr" \
  -CA customerRootCA.crt \
  -CAkey customerRootCA.key \
  -CAcreateserial \
  -out "${CLOUDHSM_CLUSTER_ID}_CustomerHsmCertificate.crt"
```

Initialize the cluster:

```bash
aws cloudhsmv2 initialize-cluster \
  --region $AWS_REGION \
  --cluster-id "$CLOUDHSM_CLUSTER_ID" \
  --signed-cert "file://${CLOUDHSM_CLUSTER_ID}_CustomerHsmCertificate.crt" \
  --trust-anchor file://customerRootCA.crt
```

Wait until the cluster state is `INITIALIZED`:

```bash
aws cloudhsmv2 describe-clusters \
  --region $AWS_REGION \
  --filters clusterIds="$CLOUDHSM_CLUSTER_ID" \
  --query 'Clusters[0].State' \
  --output text
```

Success looks like:

```text
INITIALIZED
```

## Step 5: Copy the CloudHSM CA and Configure PKCS11 on Every Vault Node

Run this on your workstation. Replace the SSH key path with your key for the EC2 key pair. Angle brackets are placeholders — do not include them in the actual value.

```bash
export SSH_PRIVATE_KEY=<path_to_private_key>

for HOST in \
  "$VAULT_1_PUBLIC_IP" \
  "$VAULT_2_PUBLIC_IP" \
  "$VAULT_3_PUBLIC_IP" \
  "$VAULT_4_PUBLIC_IP" \
  "$VAULT_5_PUBLIC_IP" \
  "$VAULT_6_PUBLIC_IP"; do
  scp -i "$SSH_PRIVATE_KEY" customerRootCA.crt ec2-user@"$HOST":/tmp/customerRootCA.crt
  ssh -i "$SSH_PRIVATE_KEY" ec2-user@"$HOST" \
    "sudo mkdir -p /opt/cloudhsm/etc && sudo cp /tmp/customerRootCA.crt /opt/cloudhsm/etc/customerCA.crt && sudo chmod 0644 /opt/cloudhsm/etc/customerCA.crt && sudo CLOUDHSM_CLUSTER_ID=$CLOUDHSM_CLUSTER_ID AWS_REGION=$AWS_REGION /opt/vault/scripts/configure-cloudhsm-pkcs11.sh"
done
```

`configure-cloudhsm-pkcs11.sh` runs both `configure-pkcs11` (required for the Vault seal) and `configure-cli` (required for the `cloudhsm-cli interactive` tool used in Step 6) against `$CLOUDHSM_CLUSTER_ID` in `$AWS_REGION`, using `/opt/cloudhsm/etc/customerCA.crt` as the trust anchor. It exits non-zero if either sub-command fails — both must succeed before proceeding.

Get the HSM ENI private IPs for later latency injection:

```bash
export CLOUDHSM_IPS=$(aws cloudhsmv2 describe-clusters \
  --region $AWS_REGION \
  --filters clusterIds="$CLOUDHSM_CLUSTER_ID" \
  --query 'Clusters[0].Hsms[].EniIp' \
  --output text)

printf 'CLOUDHSM_IPS=%s\n' "$CLOUDHSM_IPS"
```

## Step 6: Activate CloudHSM and Create the Vault Crypto User

Use `vault-1` as the CloudHSM administration client. Start an SSH session to `vault-1`:

```bash
ssh -i "$SSH_PRIVATE_KEY" ec2-user@"$VAULT_1_PUBLIC_IP"
```

Start CloudHSM CLI (if you run into an issue here, rerun the for loop in step 5 to ensure `configure-cli` completed successfully on that node):

```bash
/opt/cloudhsm/bin/cloudhsm-cli interactive
```

Inside the CloudHSM CLI, activate the cluster. `cluster activate` does not take a password as an argument — the CLI prompts for it interactively:

```text
cluster activate
```

You will see:

```text
Enter password:
Confirm password:
```

Enter a strong lab-only admin password at both prompts and store it securely. You will need it for the `login --role admin` step that follows.

Log in as the admin user and create the crypto user that Vault will use:

```text
login --username admin --role admin
user create --username vault_user --role crypto-user
quit
```

`login` and `user create` both prompt interactively for the password (they do not accept it on the command line). When `user create` prompts for the new crypto user's password, enter the exact value you set in `TF_VAR_hsm_password` in Step 1 — they must match or Vault will fail to log in to the HSM. The `--username` value (`vault_user`) must match the `hsm_user` value in `terraform.tfvars`.

## Step 7: Start Vault and Initialize the Cluster

Start Vault on `vault-1` first:

```bash
sudo systemctl start vault
sudo journalctl -u vault -n 100 --no-pager
```

Initialize Vault from `vault-1`:

```bash
export VAULT_ADDR=http://127.0.0.1:8200
vault status
vault operator init > /tmp/vault-init.txt
chmod 0600 /tmp/vault-init.txt
cat /tmp/vault-init.txt
```

Because this cluster uses HSM auto-unseal, `vault operator init` returns recovery keys along with the initial root token. Save both securely for this lab.

Start Vault on the remaining nodes from your workstation:

```bash
for HOST in \
  "$VAULT_2_PUBLIC_IP" \
  "$VAULT_3_PUBLIC_IP" \
  "$VAULT_4_PUBLIC_IP" \
  "$VAULT_5_PUBLIC_IP" \
  "$VAULT_6_PUBLIC_IP"; do
  ssh -i "$SSH_PRIVATE_KEY" ec2-user@"$HOST" "sudo systemctl start vault && sudo journalctl -u vault -n 50 --no-pager"
done
```

Because this cluster uses auto-unseal, joined nodes should unseal automatically after they contact the leader and access the HSM seal. Terraform configures vault-2 through vault-5 with `retry_join` blocks pointing at the three subnet leaders and configures vault-6 the same way plus `retry_join_as_non_voter = true`, so vault-6 joins as a permanent non-voter without any manual `raft join` command.

## Step 8: Validate Cluster Membership

Run this on `vault-1` after logging in with the initial root token.

```bash
export VAULT_ADDR=http://127.0.0.1:8200
vault login <root_token>

vault operator raft list-peers
vault operator raft autopilot state 
done
```

Success looks like:

```text
The peer list includes vault-1 through vault-6.
vault-1 through vault-5 all reach Voter state once autopilot stabilization completes
  (this can take 10s of seconds; intermediate non-voter states are expected).
vault-6 stays as a non-voter permanently.
```

If a node did not auto-join (the `retry_join` configuration normally handles this), run this on that node before it has local Raft data:

```bash
export VAULT_ADDR=http://127.0.0.1:8200
vault operator raft join http://<leader_private_ip>:8200
```

For the non-voter, use (only needed if vault-6's automatic `retry_join_as_non_voter` did not take effect):

```bash
vault operator raft join -non-voter http://<leader_private_ip>:8200
```

## Step 9: Enable Seal-Wrapped KV v2

Run this on the active node.

```bash
export VAULT_ADDR=http://127.0.0.1:8200
vault secrets enable -path=swkv -version=2 -seal-wrap kv
vault secrets list -detailed
```

Success looks like:

```text
Path    Type    Seal Wrap
swkv/   kv      true
```

## Step 10: Seed Seal Wrapped KV

Terraform stages the workload script at `/opt/vault/scripts/kv-sealwrap-load.sh` on every node. Run this from `vault-1`.

Use the initial root token from Step 7. If you would prefer to scope the workload, create a dedicated token first with a policy that grants `create`, `update`, and `read` on `swkv/*`, and use that instead.

```bash
export VAULT_TOKEN=<root_token>
for HOST in \
  "$VAULT_1_PUBLIC_IP"; do
  ssh -i "$SSH_PRIVATE_KEY" ec2-user@"$HOST" \
    "sudo env VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN='$VAULT_TOKEN' TOTAL_SECRETS=5000 CONCURRENCY=100 PAYLOAD_SIZE_BYTES=8000 MODE=write-read /opt/vault/scripts/kv-sealwrap-load.sh" &
done
wait
```

Success looks like:

```text
mode=write-read total_secrets=5000 concurrency=100 payload_size_bytes=8000 duration_seconds=<seconds> error_files=0
```

This process will take a 15-20 minutes. So, feel free to step away from the keyboard while it runs.

## Step 11: Reproduce the Issue / Quorum Loss Under Latency

Run this from your workstation to apply latency on every Vault node. The script is staged by Terraform at `/opt/vault/scripts/apply-cloudhsm-latency.sh`.

Important: Vault's `POTENTIAL DEADLOCK` detector (from `sasha-s/go-deadlock`) only fires when a single lock holder is blocked for at least 30 seconds. To reliably surface the seal-wrap deadlock, at least one HSM PKCS#11 call needs to block for 30+ seconds. This doesn't necessarily need to be during a leadership transfer. This error has appeared during reads to the seal-wrapped KV. 

`NETEM_LATENCY=` with `NETEM_JITTER=` is applied per packet on egress to the CloudHSM ENIs.

```bash
for HOST in \
  "$VAULT_1_PUBLIC_IP"; do
  ssh -i "$SSH_PRIVATE_KEY" ec2-user@"$HOST" \
    "sudo CLOUDHSM_IPS='$CLOUDHSM_IPS' NETEM_LATENCY=250ms NETEM_JITTER=50ms /opt/vault/scripts/apply-cloudhsm-latency.sh"
done
wait
```

```bash
for HOST in \
  "$VAULT_1_PUBLIC_IP"; do
  ssh -i "$SSH_PRIVATE_KEY" ec2-user@"$HOST" \
    "sudo env VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN='$VAULT_TOKEN' TOTAL_SECRETS=10000 CONCURRENCY=300 PAYLOAD_SIZE_BYTES=8000 MODE=read /opt/vault/scripts/kv-sealwrap-load.sh" &
done
wait
```

When monitoring this, keep an eye on the logs for these errors (open in a new terminal to the leader node):

```bash
journalctl -u vault -f | grep -iE "POTENTIAL DEADLOCK:|lost leadership|SIGSEGV:|raft"
```

If you need to kill the process/load for any reason, you can run this command:

```bash
for HOST in \
  "$VAULT_1_PUBLIC_IP" \
  "$VAULT_2_PUBLIC_IP" \
  "$VAULT_3_PUBLIC_IP" \
  "$VAULT_4_PUBLIC_IP" \
  "$VAULT_5_PUBLIC_IP" \
  "$VAULT_6_PUBLIC_IP"; do
  ssh -i "$SSH_PRIVATE_KEY" ec2-user@"$HOST" \
    "sudo pkill -f 'bash /opt/vault/scripts/kv-sealwrap-load.sh'"
done
```

## Step 12: Watch for Potential Deadlock Logs

Run this from your workstation:

```bash
for HOST in \
  "$VAULT_1_PUBLIC_IP" \
  "$VAULT_2_PUBLIC_IP" \
  "$VAULT_3_PUBLIC_IP" \
  "$VAULT_4_PUBLIC_IP" \
  "$VAULT_5_PUBLIC_IP"; do
  printf '\n===== %s =====\n' "$HOST"
  ssh -i "$SSH_PRIVATE_KEY" ec2-user@"$HOST" \
    "matches=\$(sudo journalctl -u vault --since '30 minutes ago' --no-pager | grep -c 'POTENTIAL DEADLOCK' || true); echo \"matches: \$matches\"; sudo journalctl -u vault --since '30 minutes ago' --no-pager | grep -A40 -B2 'POTENTIAL DEADLOCK' | head -200"
done
```

## Step 13: Remove Latency Injection

Run this from your workstation.

```bash
for HOST in \
  "$VAULT_1_PUBLIC_IP" \
  "$VAULT_2_PUBLIC_IP" \
  "$VAULT_3_PUBLIC_IP" \
  "$VAULT_4_PUBLIC_IP" \
  "$VAULT_5_PUBLIC_IP" \
  "$VAULT_6_PUBLIC_IP"; do
  ssh -i "$SSH_PRIVATE_KEY" ec2-user@"$HOST" \
    "sudo CLOUDHSM_IPS='$CLOUDHSM_IPS' /opt/vault/scripts/remove-cloudhsm-latency.sh"
done
```

Check if latency is removed:

```bash
for HOST in \
  "$VAULT_1_PUBLIC_IP" \
  "$VAULT_2_PUBLIC_IP" \
  "$VAULT_3_PUBLIC_IP" \
  "$VAULT_4_PUBLIC_IP" \
  "$VAULT_5_PUBLIC_IP"; do
  printf '\n===== %s =====\n' "$HOST"
  ssh -i "$SSH_PRIVATE_KEY" ec2-user@"$HOST" \
  "sudo tc -s qdisc show dev ens5"
done
```

Validate Vault returns to normal latency:

```bash
vault status
vault kv get swkv/load/1 >/dev/null
```

## Step 14: Test on `1.16.24+ent.hsm`

Run this to change the Vault binary on the Vault nodes:

```bash
for HOST in \
  "$VAULT_1_PUBLIC_IP" \
  "$VAULT_2_PUBLIC_IP" \
  "$VAULT_3_PUBLIC_IP" \
  "$VAULT_4_PUBLIC_IP" \
  "$VAULT_5_PUBLIC_IP" \
  "$VAULT_6_PUBLIC_IP"; do
  ssh -i "$SSH_PRIVATE_KEY" ec2-user@"$HOST" bash <<'EOF'
    set -euo pipefail
    sudo systemctl stop vault
    sudo rm -rf /opt/vault/data/*
    curl -fsSL -o /tmp/vault.zip \
      "https://releases.hashicorp.com/vault/1.16.24+ent.hsm/vault_1.16.24+ent.hsm_linux_amd64.zip"
    sudo unzip -o /tmp/vault.zip vault -d /usr/local/bin/
    sudo chmod 755 /usr/local/bin/vault
    rm -f /tmp/vault.zip
    which vault
    /usr/local/bin/vault version
    sudo systemctl start vault
EOF
done
```

Then repeat Steps 10 through 12 to see if the older version has the same behavior under latency.

## Cleanup

Destroy the Terraform-managed lab from `sys/seal/pkcs11/terraform`:

```bash
terraform destroy
```

Terraform deletes the HSM first and then the cluster — the cluster cannot be deleted until it contains no HSMs. If `terraform destroy` fails because an HSM is still in the `DELETING` state, wait for it to fully delete and run `terraform destroy` again.

AWS CloudHSM also retains a cluster backup by default (typically 7 to 90 days) and continues to bill for it. List and delete the backup once the cluster is gone:

```bash
aws cloudhsmv2 describe-backups \
  --region $AWS_REGION \
  --filters clusterIds="$CLOUDHSM_CLUSTER_ID" \
  --query 'Backups[].[BackupId,BackupState,CreateTimestamp]' \
  --output table

aws cloudhsmv2 delete-backup \
  --region $AWS_REGION \
  --backup-id <backup_id>
```

Remove local temporary files from your workstation:

```bash
rm -f customerRootCA.key customerRootCA.crt customerRootCA.srl
rm -f "${CLOUDHSM_CLUSTER_ID}_ClusterCsr.csr"
rm -f "${CLOUDHSM_CLUSTER_ID}_CustomerHsmCertificate.crt"
rm -f /tmp/vault-hsm-nodes.json
```

## References

- https://developer.hashicorp.com/vault/docs/configuration/seal/pkcs11
- https://developer.hashicorp.com/vault/docs/enterprise/sealwrap
- https://developer.hashicorp.com/vault/docs/configuration/storage/raft
- https://developer.hashicorp.com/vault/docs/commands/operator/raft
- https://docs.aws.amazon.com/cloudhsm/latest/userguide/pkcs11-library.html
- https://docs.aws.amazon.com/cloudhsm/latest/userguide/pkcs11-library-install.html
- https://docs.aws.amazon.com/cloudhsm/latest/userguide/initialize-cluster.html
- https://docs.aws.amazon.com/cloudhsm/latest/userguide/configure-sdk-5.html
