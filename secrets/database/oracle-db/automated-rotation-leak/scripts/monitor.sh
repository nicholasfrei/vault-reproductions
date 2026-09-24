#!/usr/bin/env bash

set -euo pipefail
umask 077
[[ $EUID -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }
source /root/oracle-lab/admin.env
root=/var/log/oracle-lab
# Snapshots retain useful old stacks; latest-profile scratch files do not.
find "$root" -mindepth 2 -maxdepth 2 -type f \( -name 'goroutines-latest.txt' -o -name 'goroutines-latest.txt.tmp' \) -delete
run="$root/$(date -u +%Y%m%dT%H%M%SZ)-$$"
mkdir -p "$run"
trap 'rm -f "$run/goroutines-latest.txt" "$run/goroutines-latest.txt.tmp"' EXIT
ln -sfn "$run" "$root/current"
printf 'utc,kind,pid,threads,fds,rss_kib,goroutines\n' > "$run/metrics.csv"
sample=0
shopt -s nullglob

while :; do
  stamp=$(date -u +%FT%TZ)
  vault_pid=$(systemctl show vault.service --property=MainPID --value)
  profile="$run/goroutines-latest.txt"
  # pprof describes Vault only, never the external plugin's Go runtime.
  if ! (ulimit -c 0; ulimit -f 32768; curl --fail --silent --show-error --max-time 5 --max-filesize 33554432 \
    --header "X-Vault-Token: $VAULT_TOKEN" \
    "$VAULT_ADDR/v1/sys/pprof/goroutine?debug=1" > "$profile.tmp"); then
    printf '%s pprof unavailable or exceeds 32 MiB (check Vault state and profile size)\n' "$stamp" >> "$run/monitor.log"
    : > "$profile.tmp"
  fi
  mv "$profile.tmp" "$profile"
  goroutines=$(awk 'NR == 1 && $1 == "goroutine" {print $NF}' "$profile")
  goroutines=${goroutines:-NA}
  pids=()
  [[ $vault_pid =~ ^[1-9][0-9]*$ ]] && pids+=("$vault_pid")
  # Select by executable basename; Linux comm truncates this plugin name.
  for exe in /proc/[0-9]*/exe; do
    target=$(readlink "$exe" 2>/dev/null || true)
    if [[ ${target##*/} == vault-plugin-database-oracle ]]; then
      pid=${exe#/proc/}
      pids+=("${pid%/exe}")
    fi
  done
  for pid in "${pids[@]}"; do
    [[ -r /proc/$pid/status ]] || continue
    kind=oracle-plugin
    count=NA
    if [[ $pid == "$vault_pid" ]]; then kind=vault; count=$goroutines; fi
    threads=$(awk '/^Threads:/ {print $2}' "/proc/$pid/status" 2>/dev/null || true)
    rss=$(awk '/^VmRSS:/ {print $2}' "/proc/$pid/status" 2>/dev/null || true)
    fds=(/proc/"$pid"/fd/*)
    printf '%s,%s,%s,%s,%s,%s,%s\n' "$stamp" "$kind" "$pid" "${threads:-NA}" "${#fds[@]}" "${rss:-NA}" "$count" >> "$run/metrics.csv"
  done

  # Retain recent detailed snapshots; continuous CSV covers the full handoff.
  if (( sample % 6 == 0 )); then
    slot=$(( (sample / 6) % 120 ))
    snapshot="$run/snapshot-$(printf '%04d' "$slot")"
    rm -rf "$snapshot"
    mkdir -p "$snapshot"
    printf '%s\n' "$stamp" > "$snapshot/time.txt"
    cp "$profile" "$snapshot/vault-goroutines.txt"
    ss -xapn > "$snapshot/unix-sockets.txt" 2>&1 || true
    ss -tapn > "$snapshot/tcp-sockets.txt" 2>&1 || true
    for pid in "${pids[@]}"; do
      lsof -nP -a -p "$pid" -U > "$snapshot/unix-fds-$pid.txt" 2>&1 || true
    done
    systemctl show vault.service --property=MainPID,NRestarts,ActiveState,SubState > "$snapshot/vault-service.txt"
    # This is a soft snapshot budget; CSV and other non-snapshot evidence remain.
    while (( $(du -sm "$root" | cut -f1) > 2048 )); do
      oldest=$(find "$root" -type f -path '*/snapshot-*/time.txt' -printf '%T@ %h\n' | sort -n | sed -n '1s/^[^ ]* //p')
      [[ -n $oldest ]] || break
      rm -rf "$oldest"
    done
  fi
  sample=$((sample + 1))
  sleep 10
done
