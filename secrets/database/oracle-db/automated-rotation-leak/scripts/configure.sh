#!/usr/bin/env bash

set -euo pipefail
umask 077
trap 'echo "Lab configuration failed at line $LINENO; repair and restart oracle-lab-configure.service" >&2' ERR
[[ $EUID -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_CLIENT_TIMEOUT=30s
cd /root/oracle-lab

# Vault status exits 2 while sealed; inspect its JSON rather than its exit code.
deadline=$((SECONDS + 300))
until vault status -format=json > status.json 2>/dev/null || jq -e 'has("initialized")' status.json >/dev/null 2>&1; do
  (( SECONDS < deadline )) || { echo 'Vault API did not become available.' >&2; exit 1; }
  sleep 2
done
if jq -e '.initialized == false' status.json >/dev/null; then
  vault operator init -format=json -recovery-shares=1 -recovery-threshold=1 > init.json.tmp
  mv init.json.tmp init.json
fi
[[ -s init.json ]] || { echo 'Vault is initialized but /root/oracle-lab/init.json is missing. Restore the lab initialization material.' >&2; exit 1; }
export VAULT_TOKEN
VAULT_TOKEN=$(jq -er '.root_token' init.json)
cat > admin.env <<'EOF'
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_CLIENT_TIMEOUT=30s
export VAULT_TOKEN
VAULT_TOKEN=$(jq -er '.root_token' /root/oracle-lab/init.json)
EOF

deadline=$((SECONDS + 300))
until vault status -format=json > status.json 2>/dev/null && jq -e '.sealed == false' status.json >/dev/null; do
  (( SECONDS < deadline )) || { echo 'KMS auto-unseal did not complete; inspect journalctl -u vault.' >&2; exit 1; }
  sleep 2
done

echo 'Waiting for Oracle XE initialization (up to 30 minutes).'
deadline=$((SECONDS + 1800))
until [[ $(docker inspect --format '{{.State.Health.Status}}' oracle-db) == healthy ]]; do
  (( SECONDS < deadline )) || { echo 'Oracle did not become healthy; inspect docker logs oracle-db.' >&2; exit 1; }
  sleep 10
done

[[ -f db-password ]] || openssl rand -hex 12 > db-password
db_password=$(cat db-password)
if [[ ! $db_password =~ ^[0-9a-f]{1,30}$ ]]; then
  echo 'Saved Oracle setup password must contain 1–30 hex characters. See the runbook password-length recovery; the saved value was not changed.' >&2
  exit 1
fi
# SQLPlus exits on SQL errors; never echo generated passwords into the journal.
docker exec --user oracle -i oracle-db sqlplus -s / as sysdba > sql-setup.log <<EOF
WHENEVER SQLERROR EXIT SQL.SQLCODE
WHENEVER OSERROR EXIT FAILURE
ALTER SESSION SET CONTAINER = XEPDB1;
DECLARE n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM dba_users WHERE username = 'VAULTUSER';
  IF n = 0 THEN
    EXECUTE IMMEDIATE 'CREATE USER vaultuser IDENTIFIED BY "$db_password"';
  END IF;
END;
/
GRANT CREATE SESSION, ALTER USER TO vaultuser;
DECLARE n NUMBER; u VARCHAR2(30);
BEGIN
  FOR i IN 1..10 LOOP
    u := 'LEAKREPRO' || TO_CHAR(i, 'FM00');
    SELECT COUNT(*) INTO n FROM dba_users WHERE username = u;
    IF n = 0 THEN
      EXECUTE IMMEDIATE 'CREATE USER ' || u || ' IDENTIFIED BY "$db_password"';
      EXECUTE IMMEDIATE 'GRANT CREATE SESSION TO ' || u;
    END IF;
  END LOOP;
END;
/
EXIT
EOF

if ! vault secrets list -format=json | jq -e 'has("database/")' >/dev/null; then
  vault secrets enable database
fi
vault plugin register -version='0.11.0+ent' -download=true database vault-plugin-database-oracle

jq -n --arg password "$db_password" '{
  plugin_name: "vault-plugin-database-oracle",
  plugin_version: "0.11.0+ent",
  allowed_roles: ["leak-repro-*"],
  verify_connection: true,
  connection_url: "{{username}}/{{password}}@172.30.250.10:1521/XEPDB1",
  username: "vaultuser",
  password: $password
}' > database-config.json
vault write database/config/oracle @database-config.json > /dev/null
rm database-config.json
unset db_password

for i in $(seq -w 1 10); do
  role="leak-repro-$i"
  if ! vault read -format=json "database/static-roles/$role" > /dev/null 2>&1; then
    vault write "database/static-roles/$role" \
      db_name=oracle username="LEAKREPRO$i" rotation_period=10s \
      rotation_statements='ALTER USER {{name}} IDENTIFIED BY "{{password}}" ACCOUNT UNLOCK'
  fi
  vault read -format=json "database/static-creds/$role" |
    jq '{last_vault_rotation: .data.last_vault_rotation}' > "baseline-$role.json"
done

# Require a later automatic rotation for every role, not just import rotation.
deadline=$((SECONDS + 180))
for i in $(seq -w 1 10); do
  role="leak-repro-$i"
  baseline=$(jq -er '.last_vault_rotation' "baseline-$role.json")
  while :; do
    current=$(vault read -format=json "database/static-creds/$role" | jq -er '.data.last_vault_rotation')
    [[ $current != "$baseline" ]] && break
    (( SECONDS < deadline )) || { echo "No automatic rotation observed for $role." >&2; exit 1; }
    sleep 2
  done
  printf '%s automatic rotation advanced: %s -> %s\n' "$role" "$baseline" "$current"
done

plugin_binary=/opt/vault/plugins/.runtime/vault-plugin-database-oracle_0.11.0+ent_linux_amd64/vault-plugin-database-oracle
ldd "$plugin_binary" > plugin-linker.txt
if grep -Fq 'not found' plugin-linker.txt; then
  echo 'Unresolved plugin dependencies; inspect /root/oracle-lab/plugin-linker.txt.' >&2
  exit 1
fi
awk '$1 == "libclntsh.so.19.1" && $2 == "=>" && $3 ~ /^\// { found=1; print } END { exit !found }' plugin-linker.txt
systemctl enable --now oracle-lab-monitor.service
date -u +%FT%TZ > READY
echo 'READY: ten roles rotated automatically; Oracle remains reachable. Fault service is disabled.'
