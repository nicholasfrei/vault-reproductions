#!/usr/bin/env bash
set -euo pipefail

export VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
export VAULT_TOKEN="${VAULT_TOKEN:-root}"
VAULT_DEV_LISTEN_ADDRESS="${VAULT_DEV_LISTEN_ADDRESS:-0.0.0.0:8200}"

# Some Codespaces/container runtimes reject file capabilities on /usr/bin/vault.
# Clearing capabilities makes vault executable in both old and rebuilt images.
if command -v setcap >/dev/null 2>&1; then
  setcap -r "$(command -v vault)" >/dev/null 2>&1 || true
fi

if pgrep -x vault >/dev/null 2>&1; then
  exit 0
fi

nohup vault server -dev -dev-root-token-id="${VAULT_TOKEN}" -dev-listen-address="${VAULT_DEV_LISTEN_ADDRESS}" >/tmp/vault-dev.log 2>&1 &

for _ in $(seq 1 30); do
  if curl -fsS "${VAULT_ADDR}/v1/sys/health" >/dev/null 2>&1; then
    exit 0
  fi
  sleep 1
done

echo "Vault dev server did not become ready within 30 seconds." >&2
exit 1
