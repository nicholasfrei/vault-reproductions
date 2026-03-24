#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

mkdir -p /tmp/vault-node-1/data /tmp/vault-node-2/data

bash "${SCRIPT_DIR}/setup-loopback-hosts.sh"
bash "${SCRIPT_DIR}/../run/start-vault.sh"
