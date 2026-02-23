#!/bin/bash

# DRAFT #

# Setup PGP keys for Vault init (Kubernetes)
#
# Generates N PGP key pairs, exports public keys in base64, copies them into
# the Vault pod, and runs vault operator init with PGP-encrypted unseal keys.
# Unseal keys and root token are encrypted so only holders of the matching
# private keys can decrypt.
#
# Prerequisites:
#   - kubectl configured for the cluster
#   - gpg (GnuPG) installed
#   - Vault pod running and not yet initialized (vault-0 in namespace vault)
#
# Output: Encrypted unseal keys and root token; private keys remain in local GPG keyring.

set -e

# --- Configuration ---
VAULT_NAMESPACE="${VAULT_NAMESPACE:-vault}"
VAULT_POD="${VAULT_POD:-vault-0}"
KEY_SHARES="${KEY_SHARES:-5}"
KEY_THRESHOLD="${KEY_THRESHOLD:-3}"
if [[ -z "${WORKDIR:-}" ]]; then
  WORKDIR=$(mktemp -d)
  CLEANUP_WORKDIR=1
else
  CLEANUP_WORKDIR=0
fi
PGP_POD_PATH="/tmp/vault-pgp-keys"
# ---------------------

echo "=== PGP key setup for Vault init ==="
echo "Namespace: $VAULT_NAMESPACE  Pod: $VAULT_POD"
echo "Key shares: $KEY_SHARES  Threshold: $KEY_THRESHOLD"
echo "Work dir: $WORKDIR"
echo ""

kubectl get pod -n "$VAULT_NAMESPACE" "$VAULT_POD" -o name >/dev/null || { echo "Pod $VAULT_NAMESPACE/$VAULT_POD not found"; exit 1; }

mkdir -p "$WORKDIR"
[[ "$CLEANUP_WORKDIR" -eq 1 ]] && trap 'rm -rf "$WORKDIR"' EXIT

echo "--- Generating $KEY_SHARES PGP keys ---"
for i in $(seq 1 "$KEY_SHARES"); do
  batch="$WORKDIR/batch-$i.txt"
  cat > "$batch" << EOF
Key-Type: RSA
Key-Length: 2048
Name-Real: Vault Unseal Key $i
Name-Email: vault-unseal-$i@localhost
%no-protection
%commit
EOF
  gpg --batch --gen-key "$batch" 2>/dev/null
  keyid=$(gpg --list-keys --with-colons "vault-unseal-$i@localhost" 2>/dev/null | awk -F: '$1=="pub"{print $5; exit}')
  gpg --export "$keyid" | base64 > "$WORKDIR/key-$i.b64"
  echo "  Key $i: $keyid -> key-$i.b64"
done

echo ""
echo "--- Copying public keys into pod ---"
kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD" -- mkdir -p "$PGP_POD_PATH"
for i in $(seq 1 "$KEY_SHARES"); do
  kubectl cp -n "$VAULT_NAMESPACE" "$WORKDIR/key-$i.b64" "$VAULT_NAMESPACE/$VAULT_POD:$PGP_POD_PATH/key-$i.b64"
done

pgp_list=""
for i in $(seq 1 "$KEY_SHARES"); do
  pgp_list="${pgp_list}${PGP_POD_PATH}/key-${i}.b64,"
done
pgp_list="${pgp_list%,}"

echo ""
echo "--- Running vault operator init (PGP-encrypted) ---"
init_out="$WORKDIR/vault-init-output.txt"
kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD" -- vault operator init \
  -key-shares="$KEY_SHARES" \
  -key-threshold="$KEY_THRESHOLD" \
  -pgp-keys="$pgp_list" \
  | tee "$init_out"

kubectl exec -n "$VAULT_NAMESPACE" "$VAULT_POD" -- rm -rf "$PGP_POD_PATH" 2>/dev/null || true

echo ""
echo "--- Done ==="
echo "Init output saved to: $init_out"
echo "Private keys are in your GPG keyring (vault-unseal-N@localhost)."
echo "To decrypt an unseal key: echo '<encrypted_key>' | base64 -d | gpg -dq"
echo "To unseal: vault operator unseal"
