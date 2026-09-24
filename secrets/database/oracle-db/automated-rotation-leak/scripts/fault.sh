#!/usr/bin/env bash

set -euo pipefail
[[ $EUID -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }
chain=ORACLE_LAB_FAULT
# Match the bridge destination directly, avoiding Docker's published-port DNAT.
rule=(-d 172.30.250.10/32 -p tcp --dport 1521 -j "$chain")
case ${1:-} in
  start)
    iptables -w -N "$chain" 2>/dev/null || iptables -w -L "$chain" >/dev/null
    iptables -w -C "$chain" -j DROP 2>/dev/null || iptables -w -A "$chain" -j DROP
    iptables -w -C OUTPUT "${rule[@]}" 2>/dev/null || iptables -w -I OUTPUT 1 "${rule[@]}"
    ;;
  stop)
    # A successful table read distinguishes absence from a broken backend.
    rules=$(iptables -w -S)
    while :; do
      if iptables -w -C OUTPUT "${rule[@]}" 2>/dev/null; then
        iptables -w -D OUTPUT "${rule[@]}"
      else
        rc=$?
        [[ $rc -eq 1 ]] || exit "$rc"
        break
      fi
    done
    if grep -Fxq -- "-N $chain" <<< "$rules"; then
      iptables -w -F "$chain"
      iptables -w -X "$chain"
    fi
    remaining=$(iptables -w -S)
    if grep -Eq -- "^-N $chain$| -j $chain( |$)" <<< "$remaining"; then
      echo 'Oracle fault rules remain after removal.' >&2
      exit 1
    fi
    ;;
  verify-if-enabled)
    enabled=$(systemctl is-enabled oracle-lab-fault.service 2>/dev/null) || true
    case $enabled in
      disabled) exit 0 ;;
      enabled|enabled-runtime)
        systemctl is-active --quiet oracle-lab-fault.service
        iptables -w -C OUTPUT "${rule[@]}"
        iptables -w -C "$chain" -j DROP
        ;;
      *) echo "Unexpected fault unit state: $enabled" >&2; exit 1 ;;
    esac
    ;;
  *) echo 'Usage: fault.sh start|stop|verify-if-enabled' >&2; exit 2 ;;
esac
