#!/usr/bin/env bash
set -euo pipefail

# Lab 4: Performance Replication – Environment Bootstrap
#
# This script bootstraps two single-node Vault clusters running in Kubernetes:
#   - Primary:   namespace vault-pr-primary, pod vault-pr-primary-0
#   - Secondary: namespace vault-pr-secondary, pod vault-pr-secondary-0
#
# For each pod it will:
#   1. Initialize Vault
#   2. Save the init output to /tmp/init.json inside the pod
#   3. Unseal the node
#   4. Leave root token and unseal keys in /tmp/init.json inside the pod
#
# IMPORTANT: This script is for lab use only. Do NOT use it in production.

PRIMARY_NS="${PRIMARY_NS:-vault-pr-primary}"
SECONDARY_NS="${SECONDARY_NS:-vault-pr-secondary}"
PRIMARY_RELEASE="${PRIMARY_RELEASE:-vault-pr-primary}"
SECONDARY_RELEASE="${SECONDARY_RELEASE:-vault-pr-secondary}"
MINIKUBE_PROFILE="${MINIKUBE_PROFILE:-vault}"
WAIT_TIMEOUT_SECONDS="${WAIT_TIMEOUT_SECONDS:-180}"
HELM_POD_WAIT_TIMEOUT_SECONDS="${HELM_POD_WAIT_TIMEOUT_SECONDS:-300}"
HELM_TIMEOUT="${HELM_TIMEOUT:-10m}"
VAULT_LICENSE_FILE="${VAULT_LICENSE_FILE:-../vault.hclic}"

if [[ -z "${VAULT_LICENSE:-}" ]]; then
  if [[ -n "${VAULT_LICENSE_FILE}" ]]; then
    if [[ ! -f "${VAULT_LICENSE_FILE}" ]]; then
      echo "VAULT_LICENSE_FILE does not exist: ${VAULT_LICENSE_FILE}" >&2
      exit 1
    fi
    VAULT_LICENSE="$(tr -d '\n' < "${VAULT_LICENSE_FILE}")"
  elif [[ -t 0 ]]; then
    # Interactive fallback: hide license input while typing.
    read -rsp "Enter your Vault Enterprise license: " VAULT_LICENSE
    echo
  else
    echo "No interactive terminal detected for license prompt." >&2
    echo "Set VAULT_LICENSE or VAULT_LICENSE_FILE and rerun." >&2
    exit 1
  fi
fi

if [[ -z "${VAULT_LICENSE:-}" ]]; then
  echo "Vault Enterprise license is empty." >&2
  exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required but was not found in PATH." >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required but was not found in PATH." >&2
  exit 1
fi

if ! command -v minikube >/dev/null 2>&1; then
  echo "minikube is required but was not found in PATH." >&2
  exit 1
fi

if ! command -v helm >/dev/null 2>&1; then
  echo "helm is required but was not found in PATH." >&2
  exit 1
fi

echo "Setting up Lab 4 environment..."
echo "Minikube profile:    ${MINIKUBE_PROFILE}"
echo "Primary namespace:   ${PRIMARY_NS}"
echo "Secondary namespace: ${SECONDARY_NS}"
echo
echo "Starting or reusing minikube profile (this may take a few minutes)..."
minikube start -p "${MINIKUBE_PROFILE}"
echo

echo "Ensuring namespaces exist..."
kubectl get namespace "${PRIMARY_NS}" >/dev/null 2>&1 || kubectl create namespace "${PRIMARY_NS}"
kubectl get namespace "${SECONDARY_NS}" >/dev/null 2>&1 || kubectl create namespace "${SECONDARY_NS}"
echo

echo "Adding or updating Helm repo..."
helm repo add hashicorp https://helm.releases.hashicorp.com >/dev/null 2>&1 || true
helm repo update >/dev/null
echo

install_vault_release() {
  local namespace="$1"
  local release="$2"
  echo "Installing Vault Enterprise release ${release} in namespace ${namespace}..."
  helm upgrade --install "${release}" hashicorp/vault \
    -n "${namespace}" \
    --create-namespace \
    --set "server.image.repository=hashicorp/vault-enterprise" \
    --set "server.image.tag=1.21.0-ent" \
    --set "server.extraEnvironmentVars.VAULT_LICENSE=${VAULT_LICENSE}" \
    --set "server.ha.enabled=true" \
    --set "server.ha.raft.enabled=true" \
    --set "server.ha.replicas=1" \
    --set "injector.enabled=false" \
    --timeout "${HELM_TIMEOUT}"
  echo
}

resolve_vault_sts() {
  local namespace="$1"
  local release="$2"
  local sts_name=""

  if kubectl get statefulset -n "${namespace}" "${release}" >/dev/null 2>&1; then
    sts_name="${release}"
  else
    sts_name="$(kubectl get statefulset -n "${namespace}" -l "app.kubernetes.io/instance=${release}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  fi

  if [[ -z "${sts_name}" ]]; then
    echo "Could not find Vault StatefulSet for release ${release} in namespace ${namespace}." >&2
    kubectl get statefulset -n "${namespace}" || true
    return 1
  fi

  echo "${sts_name}"
}

resolve_vault_pod_from_sts() {
  local namespace="$1"
  local statefulset="$2"
  local timeout_seconds="$3"
  local pod_name="${statefulset}-0"
  local deadline=$((SECONDS + timeout_seconds))

  echo "Waiting for pod ${pod_name} to be created in namespace ${namespace}..." >&2
  while ((SECONDS < deadline)); do
    if kubectl get pod -n "${namespace}" "${pod_name}" >/dev/null 2>&1; then
      echo "${pod_name}"
      return 0
    fi
    sleep 2
  done

  echo "Pod ${pod_name} was not created in namespace ${namespace} after ${timeout_seconds}s." >&2
  kubectl get statefulset -n "${namespace}" "${statefulset}" -o wide || true
  kubectl get pods -n "${namespace}" || true
  return 1
}

wait_for_pod_running() {
  local namespace="$1"
  local pod_name="$2"
  local timeout_seconds="$3"
  local deadline=$((SECONDS + timeout_seconds))
  local phase=""

  while ((SECONDS < deadline)); do
    phase="$(kubectl get pod -n "${namespace}" "${pod_name}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    if [[ "${phase}" == "Running" ]]; then
      return 0
    fi
    sleep 2
  done

  echo "Vault pod ${pod_name} in ${namespace} did not reach phase Running within ${timeout_seconds}s." >&2
  echo "Last observed phase: ${phase:-unknown}" >&2
  return 1
}

get_unseal_key_from_pod_init_json() {
  local namespace="$1"
  local pod_name="$2"
  local unseal_key=""
  unseal_key="$(kubectl exec -n "${namespace}" "${pod_name}" -- cat /tmp/init.json | jq -re '.unseal_keys_b64[0]')"
  if [[ -z "${unseal_key}" ]]; then
    echo "Failed to read unseal key from /tmp/init.json in pod ${pod_name}." >&2
    return 1
  fi
  echo "${unseal_key}"
}

unseal_from_pod_init_json() {
  local namespace="$1"
  local pod_name="$2"
  local unseal_key=""
  unseal_key="$(get_unseal_key_from_pod_init_json "${namespace}" "${pod_name}")"
  kubectl exec -n "${namespace}" "${pod_name}" -- vault operator unseal "${unseal_key}" >/dev/null
}

install_vault_release "${PRIMARY_NS}" "${PRIMARY_RELEASE}"
install_vault_release "${SECONDARY_NS}" "${SECONDARY_RELEASE}"

echo "Waiting for Vault pods to reach phase Running..."
VAULT_STS_PRIMARY="$(resolve_vault_sts "${PRIMARY_NS}" "${PRIMARY_RELEASE}")"
echo "Using StatefulSet for primary: ${VAULT_STS_PRIMARY}"
VAULT_POD_NAME_PRIMARY="$(resolve_vault_pod_from_sts "${PRIMARY_NS}" "${VAULT_STS_PRIMARY}" "${HELM_POD_WAIT_TIMEOUT_SECONDS}")"
if ! wait_for_pod_running "${PRIMARY_NS}" "${VAULT_POD_NAME_PRIMARY}" "${HELM_POD_WAIT_TIMEOUT_SECONDS}"; then
  kubectl get pods -n "${PRIMARY_NS}" -o wide || true
  kubectl get pvc -n "${PRIMARY_NS}" || true
  kubectl describe pod -n "${PRIMARY_NS}" "${VAULT_POD_NAME_PRIMARY}" || true
  exit 1
fi

VAULT_STS_SECONDARY="$(resolve_vault_sts "${SECONDARY_NS}" "${SECONDARY_RELEASE}")"
echo "Using StatefulSet for secondary: ${VAULT_STS_SECONDARY}"
VAULT_POD_NAME_SECONDARY="$(resolve_vault_pod_from_sts "${SECONDARY_NS}" "${VAULT_STS_SECONDARY}" "${HELM_POD_WAIT_TIMEOUT_SECONDS}")"
if ! wait_for_pod_running "${SECONDARY_NS}" "${VAULT_POD_NAME_SECONDARY}" "${HELM_POD_WAIT_TIMEOUT_SECONDS}"; then
  kubectl get pods -n "${SECONDARY_NS}" -o wide || true
  kubectl get pvc -n "${SECONDARY_NS}" || true
  kubectl describe pod -n "${SECONDARY_NS}" "${VAULT_POD_NAME_SECONDARY}" || true
  exit 1
fi
echo

echo "Note: this script is not idempotent. If Vault is already initialized in a namespace, reruns may fail."
echo

NS="${PRIMARY_NS}"
LABEL="PRIMARY"

echo "=== [${LABEL}] Namespace: ${NS} ==="
echo "Waiting for pod ${VAULT_POD_NAME_PRIMARY} in namespace ${NS} to be Running..."
wait_for_pod_running "${NS}" "${VAULT_POD_NAME_PRIMARY}" "${WAIT_TIMEOUT_SECONDS}"

echo "Initializing Vault in ${LABEL}..."
kubectl exec -n "${NS}" "${VAULT_POD_NAME_PRIMARY}" -- \
  sh -c 'vault operator init -format=json -key-shares=1 -key-threshold=1 | tee /tmp/init.json'

echo "Saved init output:"
echo "  - Inside pod: /tmp/init.json"

echo "Unsealing ${LABEL}..."
unseal_from_pod_init_json "${NS}" "${VAULT_POD_NAME_PRIMARY}"

echo "Unseal complete for ${LABEL}."
echo
echo "[${LABEL}] Root token is stored in /tmp/init.json inside pod ${VAULT_POD_NAME_PRIMARY}"
echo

NS="${SECONDARY_NS}"
LABEL="SECONDARY"

echo "=== [${LABEL}] Namespace: ${NS} ==="
echo "Waiting for pod ${VAULT_POD_NAME_SECONDARY} in namespace ${NS} to be Running..."
wait_for_pod_running "${NS}" "${VAULT_POD_NAME_SECONDARY}" "${WAIT_TIMEOUT_SECONDS}"

echo "Initializing Vault in ${LABEL}..."
kubectl exec -n "${NS}" "${VAULT_POD_NAME_SECONDARY}" -- \
  sh -c 'vault operator init -format=json -key-shares=1 -key-threshold=1 | tee /tmp/init.json'

echo "Saved init output:"
echo "  - Inside pod: /tmp/init.json"

echo "Unsealing ${LABEL}..."
unseal_from_pod_init_json "${NS}" "${VAULT_POD_NAME_SECONDARY}"

echo "Unseal complete for ${LABEL}."
echo
echo "[${LABEL}] Root token is stored in /tmp/init.json inside pod ${VAULT_POD_NAME_SECONDARY}"
echo

cat <<EOF
Next steps:
  - Inside each pod, you can view the init output at /tmp/init.json
  - Read root_token and unseal_keys_b64 from /tmp/init.json inside each pod during the lab runbook.

EOF

echo "Lab 4 environment setup complete."
exit 0