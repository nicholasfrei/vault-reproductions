#!/bin/bash
# Kubernetes Authentication Setup for Vault
#
# This script demonstrates:
# - Creating multiple Kubernetes ServiceAccounts for testing
# - Configuring Vault's Kubernetes auth method
# - Testing user logins with Vault using K8s ServiceAccount tokens
#
# Prerequisites:
# - kubectl configured and connected to your cluster
# - Vault pod running in the cluster (defaults to vault-0 in vault namespace)
# - Appropriate permissions to create namespaces, ServiceAccounts, and ClusterRoleBindings
#
# Note: This script uses Kubernetes 1.24+ token Secret approach for long-lived tokens

set -e

# --- Configuration ---
NAMESPACE="user-test-ns"           # K8s namespace for test ServiceAccounts
NUM_USERS=10                       # Number of test users to create
VAULT_NAMESPACE="vault"            # K8s namespace where Vault pod is running
VAULT_NS="test"                    # Vault internal namespace (use "root" for non-Enterprise or default namespace)
VAULT_POD="vault-0"                # Name of the Vault pod
VAULT_AUTH_SA="vault-auth"         # ServiceAccount for Vault token review
# ---------------------

echo "=== Part 1: Creating Kubernetes Users ==="
echo ""
echo "Creating namespace $NAMESPACE..."
kubectl create namespace $NAMESPACE || echo "Namespace $NAMESPACE already exists"
echo ""

# --- User Creation Loop ---
for i in $(seq 1 $NUM_USERS); do
  SERVICE_ACCOUNT_NAME="user-$i-sa"
  TOKEN_SECRET_NAME="$SERVICE_ACCOUNT_NAME-token"

  echo "Processing $SERVICE_ACCOUNT_NAME..."

  # 1. Create the ServiceAccount
  kubectl create sa $SERVICE_ACCOUNT_NAME --namespace $NAMESPACE

  # 2. Create the long-lived token Secret for the ServiceAccount
  # This is the modern (K8s 1.24+) way to get a non-expiring token.
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: $TOKEN_SECRET_NAME
  namespace: $NAMESPACE
  annotations:
    kubernetes.io/service-account.name: $SERVICE_ACCOUNT_NAME
type: kubernetes.io/service-account-token
EOF

  echo "Successfully created $SERVICE_ACCOUNT_NAME and its token secret."
  echo ""
done

echo "All $NUM_USERS ServiceAccounts have been created in namespace $NAMESPACE."
echo ""
echo "=== Part 2: Configuring Vault Kubernetes Auth ==="
echo ""

echo "Step 1: Enabling K8s Auth & Creating Vault Policy..."

# Create a dev policy in Vault for our test users
kubectl exec -n $VAULT_NAMESPACE $VAULT_POD -- /bin/sh -c " \
  vault auth enable -namespace=$VAULT_NS kubernetes && \
  echo 'path \"secret/data/dev/*\" { capabilities = [\"read\"] }' | vault policy write dev-policy - \
"
echo "Kubernetes auth enabled and dev-policy created"
echo ""

echo "Step 2: Creating ServiceAccount for Vault to review tokens..."
# Create the ServiceAccount for Vault
kubectl create sa $VAULT_AUTH_SA -n $VAULT_NAMESPACE || echo "ServiceAccount $VAULT_AUTH_SA already exists"

# Create the token Secret for the vault-auth SA
VAULT_AUTH_TOKEN_SECRET="${VAULT_AUTH_SA}-token"
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: $VAULT_AUTH_TOKEN_SECRET
  namespace: $VAULT_NAMESPACE
  annotations:
    kubernetes.io/service-account.name: $VAULT_AUTH_SA
type: kubernetes.io/service-account-token
EOF

# Give Vault permission to review tokens
kubectl create clusterrolebinding vault-token-reviewer \
  --clusterrole=system:auth-delegator \
  --serviceaccount=$VAULT_NAMESPACE:$VAULT_AUTH_SA || echo "ClusterRoleBinding vault-token-reviewer already exists"
echo "Vault ServiceAccount configured with token reviewer permissions"
echo ""

echo "Step 3: Gathering Kubernetes cluster info for Vault..."
# Wait for the token to be populated
VAULT_SA_TOKEN=""
until [ -n "$VAULT_SA_TOKEN" ]; do
  VAULT_SA_TOKEN=$(kubectl get secret $VAULT_AUTH_TOKEN_SECRET -n $VAULT_NAMESPACE -o jsonpath='{.data.token}' | base64 -d)
  sleep 1
done
echo "Vault ServiceAccount token retrieved"

# Get cluster CA cert from kubeconfig
K8S_CA_CERT_B64=$(kubectl config view --raw -o jsonpath='{.clusters[?(@.name=="'$(kubectl config current-context)'")].cluster.certificate-authority-data}')
K8S_CA_CERT=$(echo $K8S_CA_CERT_B64 | base64 -d)
echo "Kubernetes CA certificate retrieved"
echo ""

echo "Step 4: Configuring Vault's Kubernetes auth method..."
kubectl exec -n $VAULT_NAMESPACE $VAULT_POD -- /bin/sh -c \
  "vault write -namespace=$VAULT_NS auth/kubernetes/config \
    token_reviewer_jwt=\"$VAULT_SA_TOKEN\" \
    kubernetes_host=\"https://kubernetes.default.svc\" \
    kubernetes_ca_cert=\"$K8S_CA_CERT\""
echo "Kubernetes auth method configured in Vault"
echo ""

echo "Step 5: Creating Vault role for ServiceAccount users..."
# Create a role that maps all 10 ServiceAccounts to the dev-policy
# Using a wildcard pattern to match user-*-sa
kubectl exec -n $VAULT_NAMESPACE $VAULT_POD -- /bin/sh -c \
  "vault write -namespace=$VAULT_NS auth/kubernetes/role/dev-users \
    bound_service_account_names=user-*-sa \
    bound_service_account_namespaces=$NAMESPACE \
    policies=dev-policy \
    ttl=24h"
echo "Vault role 'dev-users' created"
echo ""

echo "=== Part 3: Testing Vault Logins ==="
echo ""
for i in $(seq 1 10); do
  echo "Testing login as user-$i-sa..."
  
  # Get the JWT token for this ServiceAccount
  USER_JWT=$(kubectl get secret user-$i-sa-token -n $NAMESPACE \
    -o jsonpath='{.data.token}' | base64 -d)

  # Attempt login to Vault using the K8s auth method
  kubectl exec -n $VAULT_NAMESPACE -ti $VAULT_POD -- \
    vault write -namespace=$VAULT_NS auth/kubernetes/login \
    role=dev-users \
    jwt=$USER_JWT
  
  echo "user-$i-sa login successful"
  echo ""
done

echo "=== Setup Complete ==="
echo ""
echo "Created $NUM_USERS ServiceAccounts in namespace: $NAMESPACE"
echo "Configured Vault Kubernetes auth in namespace: $VAULT_NS"
echo "Successfully tested all user logins"
echo ""
echo "Next steps:"
echo "  - ServiceAccounts can authenticate using: vault write auth/kubernetes/login role=dev-users jwt=<token>"
echo "  - They have 'read' access to secret/data/dev/*"