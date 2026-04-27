#!/bin/bash
set -euo pipefail

# Terminates EC2 instances launched by launch-ec2-instance.sh and deletes the
# security groups created by that script (tagged vault-repro=true).
#
# Usage — by instance ID (single instance):
#   INSTANCE_ID=i-0abc123 bash setup/aws/cleanup-ec2-instance.sh
#
# Usage — by Name tag (all matching instances):
#   INSTANCE_NAME=vault-repro bash setup/aws/cleanup-ec2-instance.sh
#
# Optional env vars:
#   AWS_REGION    - AWS region (default: us-east-1)

# --- Configuration ---
AWS_REGION="${AWS_REGION:-us-east-1}"
INSTANCE_ID="${INSTANCE_ID:-}"
INSTANCE_NAME="${INSTANCE_NAME:-}"

# --- Prerequisite checks ---
command -v aws > /dev/null 2>&1 || { echo "ERROR: aws CLI not found"; exit 1; }

if [[ -z "$INSTANCE_ID" && -z "$INSTANCE_NAME" ]]; then
  echo "ERROR: Set INSTANCE_ID or INSTANCE_NAME before running."
  echo ""
  echo "  INSTANCE_ID=i-0abc123 bash setup/cleanup-ec2-instance.sh"
  echo "  INSTANCE_NAME=vault-repro bash setup/cleanup-ec2-instance.sh"
  exit 1
fi

# --- Resolve instance IDs and associated managed security groups ---
if [[ -n "$INSTANCE_ID" ]]; then
  TARGET_IDS="$INSTANCE_ID"
  # Collect SG IDs attached to this instance that were created by launch-ec2-instance.sh
  MANAGED_SGS=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$AWS_REGION" \
    --query "Reservations[0].Instances[0].SecurityGroups[].GroupId" \
    --output text | tr '\t' ' ')
  # Filter to only SGs tagged vault-repro=true
  MANAGED_SGS=$(aws ec2 describe-security-groups \
    --region "$AWS_REGION" \
    --group-ids $MANAGED_SGS \
    --filters "Name=tag:vault-repro,Values=true" \
    --query "SecurityGroups[].GroupId" \
    --output text 2>/dev/null || true)
else
  echo "Looking up instances with Name tag '${INSTANCE_NAME}' in ${AWS_REGION}..."
  TARGET_IDS=$(aws ec2 describe-instances \
    --region "$AWS_REGION" \
    --filters \
      "Name=tag:Name,Values=${INSTANCE_NAME}" \
      "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query "Reservations[].Instances[].InstanceId" \
    --output text)

  if [[ -z "$TARGET_IDS" ]]; then
    echo "No running instances found with Name tag '${INSTANCE_NAME}' in ${AWS_REGION}."
    exit 0
  fi

  # Look up SGs with the matching name tag and vault-repro=true
  MANAGED_SGS=$(aws ec2 describe-security-groups \
    --region "$AWS_REGION" \
    --filters \
      "Name=tag:Name,Values=${INSTANCE_NAME}-sg" \
      "Name=tag:vault-repro,Values=true" \
    --query "SecurityGroups[].GroupId" \
    --output text 2>/dev/null || true)
fi

# --- Print instances to be terminated ---
echo ""
echo "The following instances will be TERMINATED in ${AWS_REGION}:"
for ID in $TARGET_IDS; do
  DETAILS=$(aws ec2 describe-instances \
    --instance-ids "$ID" \
    --region "$AWS_REGION" \
    --query "Reservations[0].Instances[0].[InstanceId,InstanceType,PublicIpAddress,Tags[?Key=='Name'].Value|[0],State.Name]" \
    --output text)
  echo "  $DETAILS"
done
echo ""

# --- Confirmation prompt ---
read -r -p "Terminate these instances? This cannot be undone. [y/N] " CONFIRM
if [[ "${CONFIRM}" != "y" && "${CONFIRM}" != "Y" ]]; then
  echo "Aborted."
  exit 0
fi

# --- Terminate instances ---
echo "Terminating instances..."
aws ec2 terminate-instances \
  --instance-ids $TARGET_IDS \
  --region "$AWS_REGION" \
  --query "TerminatingInstances[].{ID:InstanceId,State:CurrentState.Name}" \
  --output table

echo ""
echo "Waiting for instances to reach terminated state..."
aws ec2 wait instance-terminated \
  --instance-ids $TARGET_IDS \
  --region "$AWS_REGION"

echo ""
echo "Done. All targeted instances have been terminated."

# --- Delete managed security groups ---
if [[ -n "${MANAGED_SGS:-}" ]]; then
  echo "Deleting managed security groups: ${MANAGED_SGS}..."
  for SG in $MANAGED_SGS; do
    if aws ec2 delete-security-group \
        --group-id "$SG" \
        --region "$AWS_REGION" 2>/dev/null; then
      echo "  Deleted: ${SG}"
    else
      echo "  WARNING: Could not delete ${SG} (may still be in use or already deleted)."
    fi
  done
else
  echo "No managed security groups found to delete."
fi
