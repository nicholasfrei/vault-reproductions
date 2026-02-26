#!/bin/bash
set -euo pipefail

# Installs a 3-node Vault HA cluster with Raft via Helm, then initializes,
# unseals, and logs into vault-0. Intended for sandbox/testing use.

# --- Edit these values directly ---
NAMESPACE="vault"
HELM_RELEASE="vault"
HELM_CHART="hashicorp/vault"
HELM_REPO_NAME="hashicorp"
HELM_REPO_URL="https://helm.releases.hashicorp.com"
MINIKUBE_PROFILE="vault"
VAULT_VERSION="1.20.2"
VAULT_REPLICAS=3
KEY_SHARES=5
KEY_THRESHOLD=3
WAIT_TIMEOUT="180s"
HELM_TIMEOUT="10m"
# ---------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_FILE="$SCRIPT_DIR/init.json"

if (( KEY_THRESHOLD > KEY_SHARES )); then
  echo "Invalid key settings: KEY_THRESHOLD ($KEY_THRESHOLD) cannot exceed KEY_SHARES ($KEY_SHARES)."
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
if ! kubectl get --raw=/version >/dev/null 2>&1; then
  echo "Cannot reach Kubernetes API. Set the context with: kubectl config use-context <name>"
  exit 1
fi

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

# ============================================================
echo ""
echo "=== Vault initialization ==="
# ============================================================

echo "Waiting for $INIT_POD to be Running..."
DEADLINE=$(( SECONDS + 180 ))
while true; do
  PHASE="$(kubectl get pod -n "$NAMESPACE" "$INIT_POD" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  [[ "$PHASE" == "Running" ]] && break
  if (( SECONDS >= DEADLINE )); then
    echo "Timed out waiting for $INIT_POD (last phase: '${PHASE:-not found}')."
    kubectl get pods -n "$NAMESPACE" || true
    exit 1
  fi
  sleep 3
done

echo "Checking if Vault is already initialized..."
# vault status exits 2 when sealed, 1 on error — capture JSON before piping to avoid pipefail
VAULT_STATUS_JSON="$(kubectl exec -i "$INIT_POD" -n "$NAMESPACE" -- vault status -format=json 2>/dev/null || true)"
if [[ "$(jq -r '.initialized' <<< "$VAULT_STATUS_JSON")" == "true" ]]; then
  echo "Vault is already initialized. This script only handles first-time initialization."
  exit 1
fi

echo "Initializing Vault (shares=$KEY_SHARES, threshold=$KEY_THRESHOLD)..."
kubectl exec -i "$INIT_POD" -n "$NAMESPACE" -- \
  vault operator init -format=json -key-shares="$KEY_SHARES" -key-threshold="$KEY_THRESHOLD" > "$OUTPUT_FILE"
chmod 600 "$OUTPUT_FILE"

# ============================================================
echo ""
echo "=== Parsing init output ==="
# ============================================================

echo "Reading unseal keys and root token from $OUTPUT_FILE..."
UNSEAL_KEYS=()
while IFS= read -r key; do
  UNSEAL_KEYS+=("$key")
done < <(jq -r ".unseal_keys_b64[:$KEY_THRESHOLD][]" "$OUTPUT_FILE")
ROOT_TOKEN="$(jq -r '.root_token' "$OUTPUT_FILE")"

if [[ "${#UNSEAL_KEYS[@]}" -ne "$KEY_THRESHOLD" ]] || [[ -z "$ROOT_TOKEN" || "$ROOT_TOKEN" == "null" ]]; then
  echo "$OUTPUT_FILE is missing expected fields (unseal_keys_b64/root_token)."
  exit 1
fi

# ============================================================
echo ""
echo "=== Unsealing Vault nodes ==="
# ============================================================

echo "Unsealing $INIT_POD..."
for key in "${UNSEAL_KEYS[@]}"; do
  kubectl exec -i "$INIT_POD" -n "$NAMESPACE" -- vault operator unseal "$key" >/dev/null
  sleep 2
done

for pod in "${PODS[@]:1}"; do
  echo "Waiting for $pod to be Running..."
  DEADLINE=$(( SECONDS + 180 ))
  while true; do
    PHASE="$(kubectl get pod -n "$NAMESPACE" "$pod" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    [[ "$PHASE" == "Running" ]] && break
    if (( SECONDS >= DEADLINE )); then
      echo "Timed out waiting for $pod (last phase: '${PHASE:-not found}')."
      kubectl get pods -n "$NAMESPACE" || true
      exit 1
    fi
    sleep 3
  done

  sleep 2
  echo "Joining $pod to Raft cluster..."
  kubectl exec -i "$pod" -n "$NAMESPACE" -- vault operator raft join "http://$INIT_POD.vault-internal:8200"

  sleep 3
  echo "Unsealing $pod..."
  for key in "${UNSEAL_KEYS[@]}"; do
    kubectl exec -i "$pod" -n "$NAMESPACE" -- vault operator unseal "$key" >/dev/null
    sleep 2
  done
done

# ============================================================
echo ""
echo "=== Readiness checks and login ==="
# ============================================================

echo "Waiting for all Vault pods to become Ready..."
for pod in "${PODS[@]}"; do
  kubectl wait -n "$NAMESPACE" --for=condition=Ready "pod/$pod" --timeout="$WAIT_TIMEOUT"
done

echo "Logging in on $INIT_POD with root token..."
kubectl exec -i "$INIT_POD" -n "$NAMESPACE" -- vault login "$ROOT_TOKEN" >/dev/null
kubectl exec -i "$INIT_POD" -n "$NAMESPACE" -- vault token lookup >/dev/null

# ============================================================
echo ""
echo "=== Done ==="
# ============================================================

echo "Completed successfully."
echo "Init output saved to: $OUTPUT_FILE"
echo "$INIT_POD login completed with root token."
kubectl exec -ti -n vault vault-0 -- sh