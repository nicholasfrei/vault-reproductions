#!/bin/bash
set -euo pipefail

# Initializes Vault with PGP-encrypted unseal keys/root token using locally generated GPG keys.
# Intended for sandbox/testing use.

# --- Edit these values directly ---
NAMESPACE="vault"
HELM_RELEASE="vault"
HELM_CHART="hashicorp/vault"
HELM_REPO_NAME="hashicorp"
HELM_REPO_URL="https://helm.releases.hashicorp.com"
MINIKUBE_PROFILE="vault"
VAULT_VERSION="1.20.2"
VAULT_REPLICAS=3
KEY_SHARES=3
KEY_THRESHOLD=2
WAIT_TIMEOUT="180s"
HELM_TIMEOUT="10m"

# Optional override. Leave empty to auto-detect the first Vault pod from StatefulSet.
VAULT_POD=""

# GPG key identities - one per key share. Keys are generated locally and exported to pgp-keys/.
GPG_KEY_IDS=(
  "Vault Unseal Key 1 <unseal1@vault.local>"
  "Vault Unseal Key 2 <unseal2@vault.local>"
  "Vault Unseal Key 3 <unseal3@vault.local>"
)
# ---------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_FILE="$SCRIPT_DIR/init-pgp.txt"

if (( KEY_THRESHOLD > KEY_SHARES )); then
  echo "Invalid key settings: KEY_THRESHOLD ($KEY_THRESHOLD) cannot exceed KEY_SHARES ($KEY_SHARES)."
  exit 1
fi

if (( ${#GPG_KEY_IDS[@]} != KEY_SHARES )); then
  echo "Invalid GPG key settings: GPG_KEY_IDS count (${#GPG_KEY_IDS[@]}) must equal KEY_SHARES ($KEY_SHARES)."
  exit 1
fi


if [[ -f "$OUTPUT_FILE" ]]; then
  echo "Refusing to overwrite existing file: $OUTPUT_FILE"
  echo "Move/delete it or edit OUTPUT_FILE in this script."
  exit 1
fi

# ============================================================
echo ""
echo "=== Starting local Kubernetes cluster ==="
# ============================================================

echo "Starting minikube profile: $MINIKUBE_PROFILE..."
minikube start -p "$MINIKUBE_PROFILE"

echo "Using kube context: $(kubectl config current-context 2>/dev/null || echo "<none>")"

# ============================================================
echo ""
echo "=== Installing Vault with Helm ==="
# ============================================================

echo "Adding/updating Helm repo..."
helm repo add "$HELM_REPO_NAME" "$HELM_REPO_URL" >/dev/null 2>&1 || true
helm repo update "$HELM_REPO_NAME" >/dev/null

echo "Installing Vault via Helm..."
helm upgrade --install "$HELM_RELEASE" "$HELM_CHART" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --set "server.image.tag=$VAULT_VERSION" \
  --set "server.ha.enabled=true" \
  --set "server.ha.raft.enabled=true" \
  --set "server.ha.replicas=$VAULT_REPLICAS" \
  --set "server.affinity=" \
  --set "injector.enabled=false" \
  --timeout "$HELM_TIMEOUT"

# ============================================================
echo ""
echo "=== Waiting for Vault pods ==="
# ============================================================

echo "Detecting Vault server StatefulSet..."
VAULT_STS=""
if kubectl get statefulset -n "$NAMESPACE" "$HELM_RELEASE" >/dev/null 2>&1; then
  VAULT_STS="$HELM_RELEASE"
else
  VAULT_STS="$(kubectl get statefulset -n "$NAMESPACE" -l "app.kubernetes.io/instance=$HELM_RELEASE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
fi
if [[ -z "$VAULT_STS" ]]; then
  echo "Could not find Vault server StatefulSet in namespace $NAMESPACE."
  kubectl get statefulset -n "$NAMESPACE" || true
  exit 1
fi
echo "Using StatefulSet: $VAULT_STS"

PODS=()
for ((i = 0; i < VAULT_REPLICAS; i++)); do
  PODS+=("$VAULT_STS-$i")
done
INIT_POD="${PODS[0]}"

echo "Waiting for all pods to be created..."
for pod in "${PODS[@]}"; do
  until kubectl get pod -n "$NAMESPACE" "$pod" >/dev/null 2>&1; do sleep 2; done
  echo "  $pod: created"
done

if [[ -n "$VAULT_POD" ]]; then
  TARGET_POD="$VAULT_POD"
else
  TARGET_POD="$INIT_POD"
fi

# ============================================================
echo ""
echo "=== Preconditions ==="
# ============================================================

echo "Using namespace: $NAMESPACE"
echo "Using pod: $TARGET_POD"

for cmd in minikube helm kubectl jq gpg; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd"
    exit 1
  fi
done

if ! kubectl get --raw=/version >/dev/null 2>&1; then
  echo "Cannot reach Kubernetes API. Set the context with: kubectl config use-context <name>"
  exit 1
fi

kubectl get pod -n "$NAMESPACE" "$TARGET_POD" -o name >/dev/null 2>&1 || {
  echo "Pod $NAMESPACE/$TARGET_POD not found"
  exit 1
}

echo "Waiting for $TARGET_POD to be Running..."
DEADLINE=$(( SECONDS + 180 ))
while true; do
  PHASE="$(kubectl get pod -n "$NAMESPACE" "$TARGET_POD" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  [[ "$PHASE" == "Running" ]] && break
  if (( SECONDS >= DEADLINE )); then
    echo "Timed out waiting for $TARGET_POD (last phase: '${PHASE:-not found}')."
    kubectl get pods -n "$NAMESPACE" || true
    exit 1
  fi
  sleep 3
done

# ============================================================
echo ""
echo "=== Vault initialization (PGP via local GPG keys) ==="
# ============================================================

echo "Checking if Vault is already initialized..."
VAULT_STATUS_JSON="$(kubectl exec -i "$TARGET_POD" -n "$NAMESPACE" -- vault status -format=json 2>/dev/null || true)"
if [[ "$(jq -r '.initialized // false' <<< "$VAULT_STATUS_JSON")" == "true" ]]; then
  echo "Vault is already initialized. This script only handles first-time initialization."
  exit 1
fi

GPG_KEY_DIR="$SCRIPT_DIR/pgp-keys"
mkdir -p "$GPG_KEY_DIR"

get_pub_fingerprint_by_email() {
  local email="$1"
  gpg --batch --with-colons --list-keys "$email" 2>/dev/null \
    | awk -F: '
        $1 == "pub" { want_fpr = 1; next }
        want_fpr && $1 == "fpr" { last_fpr = $10; want_fpr = 0 }
        END { if (last_fpr != "") print last_fpr }
      '
}

echo "Generating local GPG keys..."
PGP_KEY_FILES=()
for id in "${GPG_KEY_IDS[@]}"; do
  safe_name="$(echo "$id" | sed 's/[^a-zA-Z0-9]/_/g' | tr -s '_')"
  key_file="$GPG_KEY_DIR/${safe_name}.asc"
  real_name="$(echo "$id" | sed 's/ <.*//')"
  email="$(echo "$id" | grep -oE '[^<]+@[^>]+')"

  key_fingerprint="$(get_pub_fingerprint_by_email "$email")"
  if [[ -z "$key_fingerprint" ]]; then
    echo "  Generating key for: $id"
    gpg --batch --gen-key 2>/dev/null <<EOF
%no-protection
Key-Type: RSA
Key-Length: 4096
Name-Real: $real_name
Name-Email: $email
Expire-Date: 0
%commit
EOF
    key_fingerprint="$(get_pub_fingerprint_by_email "$email")"
  fi

  if [[ -z "$key_fingerprint" ]]; then
    echo "  Failed to resolve GPG key fingerprint for: $id"
    exit 1
  fi

  gpg --batch --yes --armor --export "$key_fingerprint" > "$key_file"

  key_count="$(gpg --batch --show-keys --with-colons "$key_file" 2>/dev/null | awk -F: '$1=="pub"{c++} END{print c+0}')"
  if (( key_count != 1 )); then
    echo "  Exported key file must contain exactly 1 public key, found $key_count: $key_file"
    exit 1
  fi

  chmod 644 "$key_file"
  if [[ -f "$key_file" ]]; then
    echo "  Exported single-key public key: $key_file"
  else
    echo "  Failed to export key file: $key_file"
    exit 1
  fi
  PGP_KEY_FILES+=("$key_file")
done

echo "Copying GPG public keys into pod..."
POD_KEY_DIR="/tmp/pgp-keys"
kubectl exec -i "$TARGET_POD" -n "$NAMESPACE" -- mkdir -p "$POD_KEY_DIR"
POD_KEY_FILES=()
for key_file in "${PGP_KEY_FILES[@]}"; do
  pod_path="$POD_KEY_DIR/$(basename "$key_file")"
  kubectl cp "$key_file" "$NAMESPACE/$TARGET_POD:$pod_path"
  echo "  Copied: $(basename "$key_file") -> $pod_path"
  POD_KEY_FILES+=("$pod_path")
done

pgp_list="$(IFS=,; echo "${POD_KEY_FILES[*]}")"
root_token_key="${POD_KEY_FILES[0]}"

INIT_HELP="$(kubectl exec -i "$TARGET_POD" -n "$NAMESPACE" -- vault operator init -h 2>&1 || true)"
USE_ROOT_TOKEN_PGP_KEY=0
if grep -q -- '-root-token-pgp-key' <<< "$INIT_HELP"; then
  USE_ROOT_TOKEN_PGP_KEY=1
fi

echo "Initializing Vault (shares=$KEY_SHARES, threshold=$KEY_THRESHOLD)..."
echo "Unseal key IDs: ${GPG_KEY_IDS[*]}"

if (( USE_ROOT_TOKEN_PGP_KEY == 1 )); then
  kubectl exec -i "$TARGET_POD" -n "$NAMESPACE" -- \
    vault operator init \
    -key-shares="$KEY_SHARES" \
    -key-threshold="$KEY_THRESHOLD" \
    -root-token-pgp-key="$root_token_key" \
    -pgp-keys="$pgp_list" \
    > "$OUTPUT_FILE"
else
  echo "Warning: this Vault version does not support -root-token-pgp-key. Root token will not be PGP-encrypted."
  kubectl exec -i "$TARGET_POD" -n "$NAMESPACE" -- \
    vault operator init \
    -key-shares="$KEY_SHARES" \
    -key-threshold="$KEY_THRESHOLD" \
    -pgp-keys="$pgp_list" \
    > "$OUTPUT_FILE"
fi
chmod 600 "$OUTPUT_FILE"

kubectl exec -i "$TARGET_POD" -n "$NAMESPACE" -- rm -rf "$POD_KEY_DIR"

get_init_value() {
  local label="$1"
  grep -m1 "^$label: " "$OUTPUT_FILE" | awk -F': ' '{print $2}'
}

decrypt_b64_pgp() {
  local ciphertext_b64="$1"
  printf '%s' "$ciphertext_b64" \
    | (base64 -d 2>/dev/null || base64 -D) \
    | gpg --decrypt 2>/dev/null \
    | tr -d '\r\n'
}

echo ""
echo "=== Unsealing and login ==="

UNSEAL_KEY_1_ENC="$(get_init_value "Unseal Key 1")"
UNSEAL_KEY_2_ENC="$(get_init_value "Unseal Key 2")"
ROOT_TOKEN_RAW="$(get_init_value "Initial Root Token")"

if [[ -z "$UNSEAL_KEY_1_ENC" || -z "$UNSEAL_KEY_2_ENC" || -z "$ROOT_TOKEN_RAW" ]]; then
  echo "Failed to parse required values from $OUTPUT_FILE"
  exit 1
fi

UNSEAL_KEY_1="$(decrypt_b64_pgp "$UNSEAL_KEY_1_ENC")"
UNSEAL_KEY_2="$(decrypt_b64_pgp "$UNSEAL_KEY_2_ENC")"
if [[ -z "$UNSEAL_KEY_1" || -z "$UNSEAL_KEY_2" ]]; then
  echo "Failed to decrypt one or more unseal keys with local GPG keyring."
  exit 1
fi

if (( USE_ROOT_TOKEN_PGP_KEY == 1 )); then
  ROOT_TOKEN="$(decrypt_b64_pgp "$ROOT_TOKEN_RAW")"
else
  ROOT_TOKEN="$ROOT_TOKEN_RAW"
fi
if [[ -z "$ROOT_TOKEN" ]]; then
  echo "Failed to resolve root token from $OUTPUT_FILE"
  exit 1
fi

kubectl exec -i "$TARGET_POD" -n "$NAMESPACE" -- vault operator unseal "$UNSEAL_KEY_1" >/dev/null
kubectl exec -i "$TARGET_POD" -n "$NAMESPACE" -- vault operator unseal "$UNSEAL_KEY_2" >/dev/null
kubectl exec -i "$TARGET_POD" -n "$NAMESPACE" -- vault login "$ROOT_TOKEN" >/dev/null

STATUS_JSON="$(kubectl exec -i "$TARGET_POD" -n "$NAMESPACE" -- vault status -format=json 2>/dev/null || true)"
if [[ "$(jq -r '.sealed // true' <<< "$STATUS_JSON")" == "false" ]]; then
  echo "Vault is unsealed and login succeeded on $TARGET_POD."
else
  echo "Vault is still sealed after unseal attempts. Check key decryption and retry manually."
  exit 1
fi

# ============================================================
echo ""
echo "=== Done ==="
# ============================================================

echo "Completed successfully."
echo "PGP-encrypted init output saved to: $OUTPUT_FILE"
echo "Decrypt using the local GPG key matching each identity in GPG_KEY_IDS."
echo "Example: echo '<encrypted_unseal_key>' | (base64 -d 2>/dev/null || base64 -D) | gpg --decrypt"
echo "Example: echo '<encrypted_root_token>' | (base64 -d 2>/dev/null || base64 -D) | gpg --decrypt"
echo "GPG keys exported to: $GPG_KEY_DIR"
echo "Unseal and login were executed automatically by this script."
echo "Optional readiness check: kubectl wait -n $NAMESPACE --for=condition=Ready pod/$TARGET_POD --timeout=$WAIT_TIMEOUT"
