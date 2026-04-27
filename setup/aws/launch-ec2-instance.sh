#!/bin/bash
set -euo pipefail

# Launches an Amazon Linux 2023 EC2 instance and runs Vault Enterprise in dev
# mode via user data. Vault starts automatically on boot using the VAULT_LICENSE
# value exported in your local shell.
#
# Required env vars (export before running):
#   KEY_NAME           - EC2 key pair name for SSH access
#   VAULT_LICENSE      - Vault Enterprise license key
#
# Optional env vars:
#   AWS_REGION         - AWS region (default: us-east-1)
#   VAULT_VERSION      - Vault version to install (default: 1.20.2+ent)
#   INSTANCE_NAME      - Name tag applied to the instance (default: vault-repro)
#
# A security group is created automatically using your current public IP and
# tagged with vault-repro=true for cleanup. It is deleted by cleanup-ec2-instance.sh.

# --- Configuration ---
AWS_REGION="${AWS_REGION:-us-east-1}"
VAULT_VERSION="${VAULT_VERSION:-1.20.2+ent}"
INSTANCE_NAME="${INSTANCE_NAME:-vault-repro}"
INSTANCE_TYPE="t2.medium"
VOLUME_SIZE=30

# --- Required variable checks ---
: "${KEY_NAME:?KEY_NAME must be set (EC2 key pair name)}"
: "${VAULT_LICENSE:?VAULT_LICENSE must be set (Vault Enterprise license key)}"

# --- Prerequisite checks ---
command -v aws > /dev/null 2>&1 || { echo "ERROR: aws CLI not found"; exit 1; }
command -v curl > /dev/null 2>&1 || { echo "ERROR: curl not found"; exit 1; }

# --- Detect current public IP ---
echo "Detecting current public IP..."
MY_IP=$(curl -sf https://checkip.amazonaws.com)
if [[ -z "$MY_IP" ]]; then
  echo "ERROR: Could not detect public IP from checkip.amazonaws.com"
  exit 1
fi
echo "Using IP: ${MY_IP}/32"

# --- Resolve default VPC ---
echo "Resolving default VPC in ${AWS_REGION}..."
VPC_ID=$(aws ec2 describe-vpcs \
  --region "$AWS_REGION" \
  --filters "Name=isDefault,Values=true" \
  --query "Vpcs[0].VpcId" \
  --output text)
if [[ -z "$VPC_ID" || "$VPC_ID" == "None" ]]; then
  echo "ERROR: No default VPC found in ${AWS_REGION}. Set up a default VPC or create one manually."
  exit 1
fi
echo "Using VPC: ${VPC_ID}"

# --- Create security group ---
echo "Creating security group for SSH access from ${MY_IP}/32..."
SG_ID=$(aws ec2 create-security-group \
  --region "$AWS_REGION" \
  --group-name "${INSTANCE_NAME}-sg" \
  --description "SSH access for ${INSTANCE_NAME} vault repro" \
  --vpc-id "$VPC_ID" \
  --query "GroupId" \
  --output text)
aws ec2 authorize-security-group-ingress \
  --region "$AWS_REGION" \
  --group-id "$SG_ID" \
  --protocol tcp \
  --port 22 \
  --cidr "${MY_IP}/32"
aws ec2 create-tags \
  --region "$AWS_REGION" \
  --resources "$SG_ID" \
  --tags "Key=Name,Value=${INSTANCE_NAME}-sg" "Key=vault-repro,Value=true"
echo "Security group created: ${SG_ID}"

# --- Resolve latest Amazon Linux 2023 AMI ---
echo "Resolving latest Amazon Linux 2023 AMI in ${AWS_REGION}..."
AMI_ID=$(aws ssm get-parameter \
  --name "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64" \
  --query "Parameter.Value" \
  --output text \
  --region "$AWS_REGION")
echo "Using AMI: ${AMI_ID}"

# --- Build user data script ---
# VAULT_LICENSE and VAULT_VERSION are expanded from the local shell environment
# and embedded as literal values in the user data that executes on the EC2 instance.
TMPFILE=$(mktemp /tmp/vault-userdata.XXXXXX)
trap 'rm -f "$TMPFILE"' EXIT

cat > "$TMPFILE" << EOF
#!/bin/bash
export VAULT_LICENSE="${VAULT_LICENSE}"
export VAULT_VERSION="${VAULT_VERSION}"
export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="root"

# Persist environment variables for ec2-user SSH sessions
echo "export VAULT_ADDR=http://127.0.0.1:8200" >> /home/ec2-user/.bashrc
echo "export VAULT_TOKEN=root" >> /home/ec2-user/.bashrc

# Install dependencies (user data runs as root; no sudo needed)
dnf install -y wget unzip

wget https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip
unzip vault_${VAULT_VERSION}_linux_amd64.zip
mv vault /usr/local/bin/
vault --version

# Create plugin directory before starting Vault
mkdir -p /etc/vault.d/plugins

# VAULT_LICENSE is already exported above; vault picks it up from the environment
vault server -dev -dev-root-token-id="root" -dev-plugin-dir=/etc/vault.d/plugins > /var/log/vault.log 2>&1 &

until VAULT_ADDR=http://127.0.0.1:8200 vault status > /dev/null 2>&1; do sleep 1; done
EOF

# --- Launch EC2 instance ---
echo "Launching ${INSTANCE_TYPE} instance (${VOLUME_SIZE}GB gp3) in ${AWS_REGION}..."
INSTANCE_ID=$(aws ec2 run-instances \
  --region "$AWS_REGION" \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --security-group-ids "$SG_ID" \
  --block-device-mappings "[{\"DeviceName\":\"/dev/xvda\",\"Ebs\":{\"VolumeSize\":${VOLUME_SIZE},\"VolumeType\":\"gp3\"}}]" \
  --user-data "file://${TMPFILE}" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${INSTANCE_NAME}}]" \
  --query "Instances[0].InstanceId" \
  --output text)
echo "Instance launched: ${INSTANCE_ID}"

# --- Wait for running state ---
echo "Waiting for instance to reach running state..."
aws ec2 wait instance-running \
  --instance-ids "$INSTANCE_ID" \
  --region "$AWS_REGION"

# --- Get public IP ---
PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$AWS_REGION" \
  --query "Reservations[0].Instances[0].PublicIpAddress" \
  --output text)

echo ""
echo "Instance is running."
echo "  Instance ID   : ${INSTANCE_ID}"
echo "  Public IP     : ${PUBLIC_IP}"
echo "  Name          : ${INSTANCE_NAME}"
echo "  Region        : ${AWS_REGION}"
echo "  Security Group: ${SG_ID} (SSH from ${MY_IP}/32)"
echo ""
echo "Connect (allow ~2 min for user data to complete):"
echo "  ssh -i ~/.ssh/<your-key>.pem ec2-user@${PUBLIC_IP}"
echo "  ex: ssh -i ~/.ssh/${KEY_NAME}.pem ec2-user@${PUBLIC_IP}"
echo ""
echo "Vault logs: ssh in and run: cat /var/log/vault.log"
echo ""
echo "To terminate this instance and delete its security group:"
echo "  INSTANCE_ID=${INSTANCE_ID} AWS_REGION=${AWS_REGION} bash setup/aws/cleanup-ec2-instance.sh"
