#!/usr/bin/env bash
set -euo pipefail

add_host_if_missing() {
  local ip="$1"
  local host="$2"

  if ! grep -qE "[[:space:]]${host}([[:space:]]|\$)" /etc/hosts; then
    echo "${ip} ${host}" | sudo tee -a /etc/hosts >/dev/null
  fi
}

add_host_if_missing "127.0.0.1" "transit-vault"
add_host_if_missing "127.0.0.2" "vault-node-1"
add_host_if_missing "127.0.0.3" "vault-node-2"
