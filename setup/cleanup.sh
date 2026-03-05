#!/usr/bin/env bash
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
INIT_PGP_PATH="$SCRIPT_DIR/init-pgp.txt"
PGP_KEYS_DIR="$SCRIPT_DIR/pgp-keys"

info() { echo "INFO: $*"; }
section() {
  echo ""
  echo "=== $* ==="
}

section "Vault sandbox cleanup"

info "Namespace: $NAMESPACE"
info "Helm release: $HELM_RELEASE"
info "Minikube profile: $MINIKUBE_PROFILE"

section "Uninstalling Helm release"

info "Uninstalling Helm release (if present)..."
if helm --kube-context "$KUBE_CONTEXT" -n "$NAMESPACE" status "$HELM_RELEASE" >/dev/null 2>&1; then
  helm --kube-context "$KUBE_CONTEXT" -n "$NAMESPACE" uninstall "$HELM_RELEASE"
  info "Helm release removed."
else
  info "Helm release not found; skipping."
fi

if [[ "$DELETE_NAMESPACE" == true ]]; then
  section "Deleting namespace"

  info "Deleting namespace (if present)..."
  if kubectl --context "$KUBE_CONTEXT" get namespace "$NAMESPACE" >/dev/null 2>&1; then
    kubectl --context "$KUBE_CONTEXT" delete namespace "$NAMESPACE" --wait=true
    info "Namespace deleted."
  else
    info "Namespace not found; skipping."
  fi
fi

if [[ "$DELETE_MINIKUBE_PROFILE" == true ]]; then
  section "Deleting minikube profile"

  info "Deleting minikube profile (if present)..."
  if minikube delete -p "$MINIKUBE_PROFILE" >/dev/null 2>&1; then
    info "Minikube profile deleted."
  else
    info "Minikube profile not found or already removed; skipping."
  fi
fi

if [[ "$DELETE_INIT_JSON" == true ]]; then
  section "Removing init output file"

  info "Removing init output file (if present)..."
  if [[ -f "$INIT_JSON_PATH" ]]; then
    rm -f "$INIT_JSON_PATH"
    info "Removed: $INIT_JSON_PATH"
  else
    info "init.json not found; skipping."
  fi
fi

if [[ "$DELETE_INIT_PGP" == true ]]; then
  section "Removing init-pgp output file"

  info "Removing init-pgp output file (if present)..."
  if [[ -f "$INIT_PGP_PATH" ]]; then
    rm -f "$INIT_PGP_PATH"
    info "Removed: $INIT_PGP_PATH"
  else
    info "init-pgp.txt not found; skipping."
  fi

  if [[ -d "$PGP_KEYS_DIR" ]]; then
    rm -rf "$PGP_KEYS_DIR"
    info "Removed directory: $PGP_KEYS_DIR"
  else
    info "pgp-keys directory not found; skipping."
  fi
fi

section "Done"
info "Cleanup complete."
