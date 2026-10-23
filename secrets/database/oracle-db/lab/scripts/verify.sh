#!/usr/bin/env bash
# Verify the populated baseline on its VM. Mutates one static password and issues/
# revokes one credential per dynamic role. Run as root before introducing faults.
set -euo pipefail
set +x
umask 077
[[ $EUID -eq 0 ]] || { echo 'Run as root on the Oracle baseline VM.' >&2; exit 1; }
for tool in vault jq docker timeout; do
  command -v "$tool" >/dev/null || { echo "Missing prerequisite: $tool" >&2; exit 1; }
done
cd /root/oracle-baseline
[[ $(jq -er '.node_index' config.json) == 0 ]] || { echo 'Run cluster verification on node 1, which hosts Oracle and the private admin credentials.' >&2; exit 1; }
rm -f READY
for pending in /root/oracle-baseline/verify.*/unrevoked-lease; do
  [[ -e $pending ]] || continue
  echo "Resolve the previous verification lease in $pending before retrying." >&2
  exit 1
done
# shellcheck source=/dev/null
source admin.env
static_count=$(jq -er '.static_role_count' config.json)
dynamic_count=$(jq -er '.dynamic_role_count' config.json)
rotation_period=$(jq -er '.static_rotation_period_seconds' config.json)
plugin_version=$(jq -er '.oracle_plugin_version' config.json)
work=$(mktemp -d /root/oracle-baseline/verify.XXXXXX)
lease=''
finish() {
  local rc=$?
  trap - EXIT
  if [[ -n $lease ]]; then
    if ! vault lease revoke "$lease" >/dev/null 2>&1; then
      printf '%s\n' "$lease" > "$work/unrevoked-lease"
      rm -f READY
      echo "Failed to revoke a verification lease; private details retained in $work." >&2
      exit 1
    fi
  fi
  rm -rf "$work"
  if (( rc != 0 )); then
    rm -f READY
    echo 'Baseline verification failed; readiness was removed. Inspect the named check and Vault/Oracle logs privately.' >&2
  fi
  exit "$rc"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

vault status -format=json > "$work/status.json"
jq -e --arg version "$(jq -r '.vault_version' config.json)" \
  '.initialized and (.sealed == false) and .storage_type == "raft" and .version == $version' "$work/status.json" >/dev/null
cluster_id=$(jq -er '.cluster_id' "$work/status.json")
node_count=$(jq -er '.nodes | length' config.json)
echo "Waiting for $node_count unsealed Raft voters in the same cluster."
deadline=$((SECONDS + 1800))
while :; do
  healthy=true
  while read -r ip; do
    if ! VAULT_ADDR="http://$ip:8200" vault status -format=json > "$work/peer-status.json" 2>/dev/null ||
      ! jq -e --arg id "$cluster_id" --arg version "$(jq -r '.vault_version' config.json)" \
        '.initialized and (.sealed == false) and .cluster_id == $id and .version == $version' "$work/peer-status.json" >/dev/null; then
      healthy=false
    fi
  done < <(jq -r '.nodes[].private_ip' config.json)
  if ! vault operator raft list-peers -format=json > "$work/peers.json" 2>/dev/null ||
    ! jq -e --slurpfile config config.json '
      .data.config.servers as $peers |
      ($peers | map(.node_id) | sort) == ($config[0].nodes | map(.node_id) | sort) and
      ($peers | all(.voter == true))' "$work/peers.json" >/dev/null; then
    healthy=false
  fi
  [[ $healthy == true ]] && break
  (( SECONDS < deadline )) || { echo 'Expected Raft voters did not become healthy; inspect configure services on each node.' >&2; exit 1; }
  sleep 5
done
vault read -format=json oracle-db/config/oracle > "$work/connection.json"
jq -e --arg version "$plugin_version" \
  '.data.plugin_name == "vault-plugin-database-oracle" and (.data.plugin_version | ltrimstr("v")) == $version' "$work/connection.json" >/dev/null
vault list -format=json oracle-db/static-roles > "$work/static-roles.json"
vault list -format=json oracle-db/roles > "$work/dynamic-roles.json"
jq -e --argjson n "$static_count" 'map(select(test("^static-[0-9]{4}$"))) | length == $n' "$work/static-roles.json" >/dev/null
jq -e --argjson n "$dynamic_count" 'map(select(test("^dynamic-[0-9]{4}$"))) | length == $n' "$work/dynamic-roles.json" >/dev/null

# Feed passwords on stdin, not the SQLPlus command line; require a SQL result marker.
check_login() {
  local username=$1 password=$2 result
  [[ $username =~ ^[A-Z][A-Z0-9_]{0,29}$ && $password =~ ^[a-zA-Z0-9]{1,30}$ ]] || {
    echo 'Credential format is unsuitable for this lab SQLPlus check.' >&2; return 1;
  }
  result=$(timeout 30 docker exec --user oracle -i oracle-db sqlplus -L -s /nolog 2>/dev/null <<SQL
WHENEVER SQLERROR EXIT FAILURE
WHENEVER OSERROR EXIT FAILURE
SET HEADING OFF FEEDBACK OFF ECHO OFF VERIFY OFF
CONNECT $username/"$password"@//127.0.0.1:1521/XEPDB1
SELECT 'LOGIN_OK' FROM dual;
EXIT
SQL
  ) && [[ $result == *LOGIN_OK* ]]
}

echo "Checking Oracle authentication for all $static_count static roles."
for ((i=1; i<=static_count; i++)); do
  printf -v suffix '%04d' "$i"
  vault read -format=json "oracle-db/static-roles/static-$suffix" > "$work/role.json"
  jq -e --arg username "LAB_STATIC_$suffix" --argjson period "$rotation_period" \
    '.data.db_name == "oracle" and .data.username == $username and .data.rotation_period == $period' "$work/role.json" >/dev/null
  vault read -format=json "oracle-db/static-creds/static-$suffix" > "$work/creds.json"
  check_login "$(jq -er '.data.username' "$work/creds.json")" "$(jq -er '.data.password' "$work/creds.json")" || {
    echo "Oracle authentication failed for static-$suffix." >&2; exit 1;
  }
done

vault read -format=json oracle-db/static-creds/static-0001 > "$work/before.json"
sleep 2
vault write -f oracle-db/rotate-role/static-0001 >/dev/null
vault read -format=json oracle-db/static-creds/static-0001 > "$work/after.json"
jq -e --slurpfile old "$work/before.json" \
  '.data.password != $old[0].data.password and .data.last_vault_rotation != $old[0].data.last_vault_rotation' "$work/after.json" >/dev/null
check_login "$(jq -er '.data.username' "$work/after.json")" "$(jq -er '.data.password' "$work/after.json")"

echo "Checking issuance, Oracle authentication, and revocation for all $dynamic_count dynamic roles."
for ((i=1; i<=dynamic_count; i++)); do
  printf -v suffix '%04d' "$i"
  vault read -format=json "oracle-db/creds/dynamic-$suffix" > "$work/creds.json"
  lease=$(jq -er '.lease_id' "$work/creds.json")
  printf '%s\n' "$lease" > "$work/unrevoked-lease"
  username=$(jq -er '.data.username' "$work/creds.json")
  check_login "$username" "$(jq -er '.data.password' "$work/creds.json")" || {
    echo "Oracle authentication failed for dynamic-$suffix." >&2; exit 1;
  }
  vault lease revoke "$lease" >/dev/null
  lease=''
  rm "$work/unrevoked-lease"
  # Check account removal, rather than accepting any failed login as revocation proof.
  result=$(timeout 30 docker exec --user oracle -i oracle-db sqlplus -L -s / as sysdba 2>/dev/null <<SQL
WHENEVER SQLERROR EXIT FAILURE
WHENEVER OSERROR EXIT FAILURE
SET HEADING OFF FEEDBACK OFF
ALTER SESSION SET CONTAINER = XEPDB1;
SELECT 'USER_REMOVED' FROM dual WHERE NOT EXISTS (SELECT 1 FROM dba_users WHERE username = '$username');
EXIT
SQL
  )
  [[ $result == *USER_REMOVED* ]] || { echo "Oracle user remains after revoking dynamic-$suffix." >&2; exit 1; }
done

jq -n --arg checked_at "$(date -u +%FT%TZ)" --slurpfile config config.json \
  --arg oracle_image "$(docker inspect --format '{{.Image}}' oracle-db)" --argjson nodes "$node_count" '{
    checked_at: $checked_at, configuration: $config[0], oracle_image_id: $oracle_image,
    static_logins_verified: $config[0].static_role_count,
    manual_static_rotations_verified: 1,
    unsealed_raft_voters_verified: $nodes,
    dynamic_issue_login_revoke_cycles_verified: $config[0].dynamic_role_count,
    retained_verification_leases: 0
  }' > "$work/verification.json"
mv "$work/verification.json" verification.json
date -u +%FT%TZ > READY
echo 'Verification passed; all temporary dynamic credentials were revoked.'
