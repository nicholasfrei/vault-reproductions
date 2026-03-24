#!/usr/bin/env bash
set -euo pipefail

append_hosts_line() {
  local line="$1"

  if [ "$(id -u)" -eq 0 ]; then
    echo "${line}" >> /etc/hosts
    return
  fi

  if command -v sudo >/dev/null 2>&1; then
    echo "${line}" | sudo tee -a /etc/hosts >/dev/null
    return
  fi

  echo "Unable to update /etc/hosts: need root or sudo." >&2
  exit 1
}

add_host_if_missing() {
  local ip="$1"
  local host="$2"

  if ! grep -qE "[[:space:]]${host}([[:space:]]|\$)" /etc/hosts; then
    append_hosts_line "${ip} ${host}"
  fi
}

add_host_if_missing "127.0.0.1" "transit-vault"
add_host_if_missing "127.0.0.2" "vault-node-1"
add_host_if_missing "127.0.0.3" "vault-node-2"
