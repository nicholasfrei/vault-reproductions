#!/bin/bash
set -euo pipefail

# Cleanup script for local Vault sandbox runs.
# Safe to run multiple times.

# --- Edit these values directly ---
NAMESPACE="vault"
HELM_RELEASE="vault"
MINIKUBE_PROFILE="vault"
KUBE_CONTEXT="vault"
DELETE_NAMESPACE=true
DELETE_MINIKUBE_PROFILE=true
DELETE_INIT_JSON=true
DELETE_INIT_PGP=true
# ---------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INIT_JSON_PATH="$SCRIPT_DIR/init.json"

# ============================================================
echo ""
echo "=== Vault sandbox cleanup ==="
# ============================================================

echo "Namespace: $NAMESPACE"
echo "Helm release: $HELM_RELEASE"
echo "Minikube profile: $MINIKUBE_PROFILE"

# ============================================================
echo ""
echo "=== Uninstalling Helm release ==="
# ============================================================

echo "Uninstalling Helm release (if present)..."
if helm --kube-context "$KUBE_CONTEXT" -n "$NAMESPACE" status "$HELM_RELEASE" >/dev/null 2>&1; then
  helm --kube-context "$KUBE_CONTEXT" -n "$NAMESPACE" uninstall "$HELM_RELEASE"
  echo "Helm release removed."
else
  echo "Helm release not found; skipping."
fi

if [[ "$DELETE_NAMESPACE" == true ]]; then
  # ============================================================
  echo ""
  echo "=== Deleting namespace ==="
  # ============================================================

  echo "Deleting namespace (if present)..."
  if kubectl --context "$KUBE_CONTEXT" get namespace "$NAMESPACE" >/dev/null 2>&1; then
    kubectl --context "$KUBE_CONTEXT" delete namespace "$NAMESPACE" --wait=true
    echo "Namespace deleted."
  else
    echo "Namespace not found; skipping."
  fi
fi

if [[ "$DELETE_MINIKUBE_PROFILE" == true ]]; then
  # ============================================================
  echo ""
  echo "=== Deleting minikube profile ==="
  # ============================================================

  echo "Deleting minikube profile (if present)..."
  if minikube delete -p "$MINIKUBE_PROFILE" >/dev/null 2>&1; then
    echo "Minikube profile deleted."
  else
    echo "Minikube profile not found or already removed; skipping."
  fi
fi

if [[ "$DELETE_INIT_JSON" == true ]]; then
  # ============================================================
  echo ""
  echo "=== Removing init output file ==="
  # ============================================================

  echo "Removing init output file (if present)..."
  if [[ -f "$INIT_JSON_PATH" ]]; then
    rm -f "$INIT_JSON_PATH"
    echo "Removed: $INIT_JSON_PATH"
  else
    echo "init.json not found; skipping."
  fi
fi

if [[ "$DELETE_INIT_PGP" == true ]]; then
  # ============================================================
  echo ""
  echo "=== Removing init-pgp output file ==="
  # ============================================================

  INIT_PGP_PATH="$SCRIPT_DIR/init-pgp.txt"
  echo "Removing init-pgp output file (if present)..."
  if [[ -f "$INIT_PGP_PATH" ]]; then
    rm -f "$INIT_PGP_PATH"
    echo "Removed: $INIT_PGP_PATH"
  else
    echo "init-pgp.txt not found; skipping."
  fi

  PGP_KEYS_DIR="$SCRIPT_DIR/pgp-keys"
  if [[ -d "$PGP_KEYS_DIR" ]]; then
    rm -rf "$PGP_KEYS_DIR"
    echo "Removed directory: $PGP_KEYS_DIR"
  else
    echo "pgp-keys directory not found; skipping."
  fi


fi


# ============================================================
echo ""
echo "=== Done ==="
# ============================================================

echo "Cleanup complete."
