#!/usr/bin/env bash
# JWT Authentication Setup and Login Script for Vault
#
# Prerequisites:
# - kubectl, jq, openssl
# - A running Vault pod in Kubernetes
# - Vault pod is already logged in as a token with permissions to manage auth/policies

set -euo pipefail

JWT_AUTH_PATH="${JWT_AUTH_PATH:-jwt}"
JWT_ISSUER="${JWT_ISSUER:-local-dev-jwt-issuer}"
POLICY_NAME="jwt-dev-reader"
ROLE_PREFIX="jwt-user"
USER_LIST="${USER_LIST:-alice bob charlie}"
CHECK_SECRET_READ="true"
KV_MOUNT_PATH="${KV_MOUNT_PATH:-secret}"
AUTO_ENABLE_KV_MOUNT="${AUTO_ENABLE_KV_MOUNT:-true}"

VAULT_NAMESPACE="${VAULT_NAMESPACE:-vault}"
VAULT_POD="${VAULT_POD:-vault-0}"
VAULT_CONTAINER="${VAULT_CONTAINER:-vault}"

WORK_DIR="$(mktemp -d)"
PRIVATE_KEY_FILE="$WORK_DIR/jwt-private.pem"
PUBLIC_KEY_FILE="$WORK_DIR/jwt-public.pem"
PUBLIC_KEY_IN_POD="/tmp/jwt-public.pem"
POLICY_IN_POD="/tmp/${POLICY_NAME}.hcl"
trap 'kubectl exec "$VAULT_POD" -n "$VAULT_NAMESPACE" -c "$VAULT_CONTAINER" -- rm -f "$PUBLIC_KEY_IN_POD" "$POLICY_IN_POD" >/dev/null 2>&1 || true; rm -rf "$WORK_DIR"' EXIT

generate_jwt() {
  local user="$1"
  local now exp header payload header_b64 payload_b64 signature signing_input

  now="$(date +%s)"
  exp="$((now + 3600))"

  header='{"alg":"RS256","typ":"JWT"}'
  payload="$(jq -cn --arg iss "$JWT_ISSUER" --arg sub "$user" --argjson iat "$now" --argjson exp "$exp" '{iss:$iss,sub:$sub,iat:$iat,exp:$exp}')"

  header_b64="$(printf '%s' "$header" | openssl base64 -A | tr '+/' '-_' | tr -d '=')"
  payload_b64="$(printf '%s' "$payload" | openssl base64 -A | tr '+/' '-_' | tr -d '=')"
  signing_input="${header_b64}.${payload_b64}"
  signature="$(printf '%s' "$signing_input" | openssl dgst -sha256 -sign "$PRIVATE_KEY_FILE" | openssl base64 -A | tr '+/' '-_' | tr -d '=')"

  printf '%s' "${signing_input}.${signature}"
}

echo "Checking prerequisites..."
if ! command -v kubectl >/dev/null 2>&1; then
  echo "Missing required command: kubectl"
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Missing required command: jq"
  exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "Missing required command: openssl"
  exit 1
fi

echo "Using Kubernetes CLI: kubectl"
echo "Target pod: ${VAULT_NAMESPACE}/${VAULT_POD} (container: ${VAULT_CONTAINER})"

echo "Checking Vault connectivity from pod..."
kubectl exec "$VAULT_POD" -n "$VAULT_NAMESPACE" -c "$VAULT_CONTAINER" -- vault status >/dev/null

echo "Generating RSA key pair for JWT signing..."
openssl genrsa -out "$PRIVATE_KEY_FILE" 2048 >/dev/null 2>&1
openssl rsa -in "$PRIVATE_KEY_FILE" -pubout -out "$PUBLIC_KEY_FILE" >/dev/null 2>&1

echo "Uploading JWT public key into Vault pod..."
kubectl exec -i "$VAULT_POD" -n "$VAULT_NAMESPACE" -c "$VAULT_CONTAINER" -- sh -c "cat > '$PUBLIC_KEY_IN_POD'" < "$PUBLIC_KEY_FILE"

echo "Ensuring JWT auth is enabled at ${JWT_AUTH_PATH}/..."
kubectl exec "$VAULT_POD" -n "$VAULT_NAMESPACE" -c "$VAULT_CONTAINER" -- vault auth enable -path="$JWT_AUTH_PATH" jwt >/dev/null 2>&1 || true

echo "Writing policy: $POLICY_NAME"
kubectl exec -i "$VAULT_POD" -n "$VAULT_NAMESPACE" -c "$VAULT_CONTAINER" -- sh -c "cat > '$POLICY_IN_POD'" <<EOF
path "${KV_MOUNT_PATH}/data/dev/*" {
  capabilities = ["read", "list"]
}

path "${KV_MOUNT_PATH}/metadata/dev/*" {
  capabilities = ["read", "list"]
}

path "${KV_MOUNT_PATH}/*" {
  capabilities = ["read", "list"]
}

path "sys/internal/ui/mounts/${KV_MOUNT_PATH}" {
  capabilities = ["read"]
}
EOF
kubectl exec "$VAULT_POD" -n "$VAULT_NAMESPACE" -c "$VAULT_CONTAINER" -- vault policy write "$POLICY_NAME" "$POLICY_IN_POD" >/dev/null

echo "Configuring JWT auth..."
kubectl exec "$VAULT_POD" -n "$VAULT_NAMESPACE" -c "$VAULT_CONTAINER" -- vault write "auth/${JWT_AUTH_PATH}/config" \
  bound_issuer="$JWT_ISSUER" \
  jwt_supported_algs="RS256" \
  jwt_validation_pubkeys=@"$PUBLIC_KEY_IN_POD" >/dev/null

echo "Creating demo secret at ${KV_MOUNT_PATH}/dev/welcome"
if kubectl exec "$VAULT_POD" -n "$VAULT_NAMESPACE" -c "$VAULT_CONTAINER" -- vault secrets list -format=json | jq -e --arg mount "${KV_MOUNT_PATH}/" 'has($mount)' >/dev/null; then
  if secret_put_err="$(kubectl exec "$VAULT_POD" -n "$VAULT_NAMESPACE" -c "$VAULT_CONTAINER" -- vault kv put "${KV_MOUNT_PATH}/dev/welcome" message="hello-from-jwt" 2>&1)"; then
    :
  else
    CHECK_SECRET_READ="false"
    echo "Warning: could not create demo secret at ${KV_MOUNT_PATH}/data/dev/welcome."
    echo "This is usually a policy issue (missing update/create on ${KV_MOUNT_PATH}/data/dev/* for the setup token)."
    echo "Continuing with JWT login validation only."
    echo "Details:"
    echo "$secret_put_err"
  fi
else
  if [[ "$AUTO_ENABLE_KV_MOUNT" == "true" ]]; then
    echo "KV mount ${KV_MOUNT_PATH}/ not found. Attempting to enable KV v2..."
    if kubectl exec "$VAULT_POD" -n "$VAULT_NAMESPACE" -c "$VAULT_CONTAINER" -- vault secrets enable -path="$KV_MOUNT_PATH" -version=2 kv >/dev/null 2>&1; then
      if secret_put_err="$(kubectl exec "$VAULT_POD" -n "$VAULT_NAMESPACE" -c "$VAULT_CONTAINER" -- vault kv put "${KV_MOUNT_PATH}/dev/welcome" message="hello-from-jwt" 2>&1)"; then
        :
      else
        CHECK_SECRET_READ="false"
        echo "Warning: KV mount was enabled, but demo secret write still failed."
        echo "Details:"
        echo "$secret_put_err"
        echo "Continuing with JWT login validation only."
      fi
    else
      CHECK_SECRET_READ="false"
      echo "Warning: no KV mount found at ${KV_MOUNT_PATH}/ and automatic enable failed."
      echo "Continuing with JWT login validation only."
      echo "Tip: ensure the setup token can run: vault secrets enable -path=${KV_MOUNT_PATH} -version=2 kv"
    fi
  else
    CHECK_SECRET_READ="false"
    echo "Warning: no KV mount found at ${KV_MOUNT_PATH}/."
    echo "Skipping demo secret write/read validation and continuing with JWT login validation only."
    echo "Tip: set AUTO_ENABLE_KV_MOUNT=true or point KV_MOUNT_PATH to an existing KV v2 mount."
  fi
fi

echo "Creating JWT roles..."
for user in $USER_LIST; do
  role_name="${ROLE_PREFIX}-${user}"
  kubectl exec "$VAULT_POD" -n "$VAULT_NAMESPACE" -c "$VAULT_CONTAINER" -- vault write "auth/${JWT_AUTH_PATH}/role/${role_name}" \
    role_type="jwt" \
    user_claim="sub" \
    bound_subject="$user" \
    token_policies="$POLICY_NAME" \
    token_ttl="1h" >/dev/null
  echo "  - Created role: $role_name"
done

echo
echo "Testing login for each user..."
for user in $USER_LIST; do
  role_name="${ROLE_PREFIX}-${user}"
  jwt_token="$(generate_jwt "$user")"

  client_token="$(kubectl exec "$VAULT_POD" -n "$VAULT_NAMESPACE" -c "$VAULT_CONTAINER" -- vault write -field=token "auth/${JWT_AUTH_PATH}/login" role="$role_name" jwt="$jwt_token" | tr -d '\r')"
  if [[ "$CHECK_SECRET_READ" == "true" ]]; then
    message="$(kubectl exec "$VAULT_POD" -n "$VAULT_NAMESPACE" -c "$VAULT_CONTAINER" -- env VAULT_TOKEN="$client_token" vault read -format=json "${KV_MOUNT_PATH}/data/dev/welcome" | jq -r '.data.data.message' | tr -d '\r')"
    echo "  - $user login success, secret message: $message"
  else
    echo "  - $user login success"
  fi
done

echo
echo "Done."
echo "Auth path: ${JWT_AUTH_PATH}/"
echo "Users: $USER_LIST"
echo "Policy: $POLICY_NAME"
