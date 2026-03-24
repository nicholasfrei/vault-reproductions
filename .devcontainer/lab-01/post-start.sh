#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

mkdir -p /tmp/vault-node-1/data /tmp/vault-node-2/data

bash "${SCRIPT_DIR}/setup-loopback-hosts.sh"
# Lab 01 transit node must bind only 127.0.0.1 so node1/node2 can use
# 127.0.0.2:8200 and 127.0.0.3:8200 without listener conflicts.
export VAULT_DEV_LISTEN_ADDRESS="127.0.0.1:8200"
bash "${SCRIPT_DIR}/../run/start-vault.sh"
