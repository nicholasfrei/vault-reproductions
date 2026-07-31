#!/usr/bin/env bash

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
KEY_SHARES=1
KEY_THRESHOLD=1
WAIT_TIMEOUT="180s"
HELM_TIMEOUT="10m"
# ---------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_FILE="$SCRIPT_DIR/init.json"
VAULT_VERSION=""
VAULT_REPLICAS=""

info() { echo "INFO: $*"; }
warn() { echo "WARN: $*"; }
section() {
  echo ""
  echo "=== $* ==="
}

if [[ -t 0 ]]; then
  read -r -p "Enter Vault Version (i.e. 1.21.1): " user_vault_version
  if [[ -z "${user_vault_version// }" ]]; then
    warn "Vault version is required."
    exit 1
  fi
  VAULT_VERSION="$user_vault_version"

  read -r -p "Enter Vault replica count: " user_vault_replicas
  if [[ -z "${user_vault_replicas// }" ]]; then
    warn "Vault replica count is required."
    exit 1
  fi
  VAULT_REPLICAS="$user_vault_replicas"
else
  warn "Non-interactive shell detected; Vault version and replica count prompts require user input."
  exit 1
fi

if ! [[ "$VAULT_REPLICAS" =~ ^[0-9]+$ ]] || (( VAULT_REPLICAS < 1 )); then
  warn "Invalid replica count: '$VAULT_REPLICAS'. Must be a positive integer."
  exit 1
fi

if (( KEY_THRESHOLD > KEY_SHARES )); then
  warn "Invalid key settings: KEY_THRESHOLD ($KEY_THRESHOLD) cannot exceed KEY_SHARES ($KEY_SHARES)."
  exit 1
fi

if [[ -f "$OUTPUT_FILE" ]]; then
  warn "Refusing to overwrite existing file: $OUTPUT_FILE"
  warn "Move/delete it or edit OUTPUT_FILE in this script."
  exit 1
fi

for cmd in minikube kubectl helm jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    warn "Missing required command: $cmd"
    exit 1
  fi
done

section "Starting local Kubernetes cluster"
info "Starting minikube profile: $MINIKUBE_PROFILE..."
minikube start -p "$MINIKUBE_PROFILE" --memory=2g --cpus=2

info "Using kube context: $(kubectl config current-context 2>/dev/null || echo "<none>")"
if ! kubectl get --raw=/version >/dev/null 2>&1; then
  warn "Cannot reach Kubernetes API. Set the context with: kubectl config use-context <name>"
  exit 1
fi

section "Installing Vault with Helm"

info "Adding/updating Helm repo..."
helm repo add "$HELM_REPO_NAME" "$HELM_REPO_URL" >/dev/null 2>&1 || true
helm repo update "$HELM_REPO_NAME" >/dev/null

info "Installing Vault via Helm..."
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

section "Waiting for Vault pods"

info "Detecting Vault server StatefulSet..."
VAULT_STS=""
if kubectl get statefulset -n "$NAMESPACE" "$HELM_RELEASE" >/dev/null 2>&1; then
  VAULT_STS="$HELM_RELEASE"
else
  VAULT_STS="$(kubectl get statefulset -n "$NAMESPACE" -l "app.kubernetes.io/instance=$HELM_RELEASE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
fi
if [[ -z "$VAULT_STS" ]]; then
  warn "Could not find Vault server StatefulSet in namespace $NAMESPACE."
  kubectl get statefulset -n "$NAMESPACE" || true
  exit 1
fi
info "Using StatefulSet: $VAULT_STS"

PODS=()
for ((i = 0; i < VAULT_REPLICAS; i++)); do
  PODS+=("$VAULT_STS-$i")
done
INIT_POD="${PODS[0]}"

info "Waiting for all pods to be created..."
for pod in "${PODS[@]}"; do
  until kubectl get pod -n "$NAMESPACE" "$pod" >/dev/null 2>&1; do sleep 2; done
  info "  $pod: created"
done

section "Vault initialization"

info "Waiting for $INIT_POD to be Running..."
DEADLINE=$(( SECONDS + 180 ))
while true; do
  PHASE="$(kubectl get pod -n "$NAMESPACE" "$INIT_POD" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  [[ "$PHASE" == "Running" ]] && break
  if (( SECONDS >= DEADLINE )); then
    warn "Timed out waiting for $INIT_POD (last phase: '${PHASE:-not found}')."
    kubectl get pods -n "$NAMESPACE" || true
    exit 1
  fi
  sleep 3
done

info "Checking if Vault is already initialized..."
# vault operator init -status exits:
#   0 -> already initialized
#   2 -> not initialized yet
#   1 -> error talking to Vault
if kubectl exec "$INIT_POD" -n "$NAMESPACE" -- vault operator init -status </dev/null >/dev/null 2>&1; then
  warn "Vault is already initialized. This script only handles first-time initialization."
  warn "If you expected a fresh cluster, remove the existing Vault data and rerun."
  exit 1
else
  INIT_STATUS_RC=$?
  if [[ "$INIT_STATUS_RC" -ne 2 ]]; then
    warn "Unable to determine initialization status (exit code: $INIT_STATUS_RC)."
    warn "Check pod logs with: kubectl logs -n $NAMESPACE $INIT_POD"
    exit 1
  fi
fi

info "Initializing Vault (shares=$KEY_SHARES, threshold=$KEY_THRESHOLD)..."
INIT_ERR_FILE="$(mktemp)"
if ! kubectl exec "$INIT_POD" -n "$NAMESPACE" -- \
  vault operator init -format=json -key-shares="$KEY_SHARES" -key-threshold="$KEY_THRESHOLD" </dev/null > "$OUTPUT_FILE" 2>"$INIT_ERR_FILE"; then
  if grep -qi "Vault is already initialized" "$INIT_ERR_FILE"; then
    rm -f "$OUTPUT_FILE"
    warn "Vault became initialized before this command completed."
    warn "Use the existing unseal keys/root token, or reset cluster data and rerun."
    rm -f "$INIT_ERR_FILE"
    exit 1
  fi

  warn "Vault initialization failed."
  cat "$INIT_ERR_FILE" >&2
  rm -f "$INIT_ERR_FILE"
  exit 1
fi
rm -f "$INIT_ERR_FILE"
chmod 600 "$OUTPUT_FILE"

section "Parsing init output"

info "Reading unseal keys and root token from $OUTPUT_FILE..."
UNSEAL_KEYS=()
while IFS= read -r key; do
  UNSEAL_KEYS+=("$key")
done < <(jq -r ".unseal_keys_b64[:$KEY_THRESHOLD][]" "$OUTPUT_FILE")
ROOT_TOKEN="$(jq -r '.root_token' "$OUTPUT_FILE")"

if [[ "${#UNSEAL_KEYS[@]}" -ne "$KEY_THRESHOLD" ]] || [[ -z "$ROOT_TOKEN" || "$ROOT_TOKEN" == "null" ]]; then
  warn "$OUTPUT_FILE is missing expected fields (unseal_keys_b64/root_token)."
  exit 1
fi

section "Unsealing Vault nodes"

info "Unsealing $INIT_POD..."
for key in "${UNSEAL_KEYS[@]}"; do
  kubectl exec "$INIT_POD" -n "$NAMESPACE" -- vault operator unseal "$key" >/dev/null
  sleep 2
done

for pod in "${PODS[@]:1}"; do
  info "Waiting for $pod to be Running..."
  DEADLINE=$(( SECONDS + 180 ))
  while true; do
    PHASE="$(kubectl get pod -n "$NAMESPACE" "$pod" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    [[ "$PHASE" == "Running" ]] && break
    if (( SECONDS >= DEADLINE )); then
      warn "Timed out waiting for $pod (last phase: '${PHASE:-not found}')."
      kubectl get pods -n "$NAMESPACE" || true
      exit 1
    fi
    sleep 3
  done

  sleep 2
  info "Joining $pod to Raft cluster..."
  kubectl exec "$pod" -n "$NAMESPACE" -- vault operator raft join "http://$INIT_POD.vault-internal:8200" </dev/null

  sleep 3
  info "Unsealing $pod..."
  for key in "${UNSEAL_KEYS[@]}"; do
    kubectl exec "$pod" -n "$NAMESPACE" -- vault operator unseal "$key" >/dev/null
    sleep 2
  done
done

section "Readiness checks and login"

info "Waiting for all Vault pods to become Ready..."
for pod in "${PODS[@]}"; do
  kubectl wait -n "$NAMESPACE" --for=condition=Ready "pod/$pod" --timeout="$WAIT_TIMEOUT" >/dev/null
done

info "Logging in on $INIT_POD with root token..."
kubectl exec "$INIT_POD" -n "$NAMESPACE" -- vault login "$ROOT_TOKEN" </dev/null >/dev/null 2>&1
info "Login successful on $INIT_POD."

section "Done"

info "Completed successfully."
info "Init output saved to: $OUTPUT_FILE"
info "$INIT_POD login completed with root token."
exit 0