#!/usr/bin/env bash
# Initialize and populate the Terraform-created Oracle baseline as root on the VM.
# Resume incomplete setup without resetting existing Oracle users or Vault roles.
set -euo pipefail
set +x
umask 077
trap 'echo "Configuration failed at line $LINENO; inspect the private log, then restart oracle-baseline-configure.service." >&2' ERR
[[ $EUID -eq 0 ]] || { echo 'Run as root on the lab VM.' >&2; exit 1; }
for tool in vault jq docker openssl timeout; do
  command -v "$tool" >/dev/null || { echo "Missing prerequisite: $tool" >&2; exit 1; }
done
cd /root/oracle-baseline
[[ ! -e READY ]] || { echo 'Baseline already completed; run oracle-baseline-verify or rebuild to repopulate.' >&2; exit 1; }
unset VAULT_NAMESPACE VAULT_TOKEN
export VAULT_ADDR=http://127.0.0.1:8200 VAULT_CLIENT_TIMEOUT=60s
static_count=$(jq -er '.static_role_count' config.json)
dynamic_count=$(jq -er '.dynamic_role_count' config.json)
rotation_period=$(jq -er '.static_rotation_period_seconds' config.json)
plugin_version=$(jq -er '.oracle_plugin_version' config.json)
node_index=$(jq -er '.node_index' config.json)
oracle_host=$(jq -er '.oracle_host' config.json)

if (( node_index > 0 )); then
  echo 'Waiting for Raft join and KMS auto-unseal; only node 1 initializes the cluster.'
  deadline=$((SECONDS + 1800))
  until vault status -format=json > status.json 2>/dev/null && jq -e '.initialized and (.sealed == false)' status.json >/dev/null; do
    (( SECONDS < deadline )) || { echo 'Raft join did not complete; inspect node 1, peer networking, and KMS access.' >&2; exit 1; }
    sleep 5
  done
  date -u +%FT%TZ > NODE_READY
  echo 'Follower joined and unsealed; node 1 owns population and cluster-wide verification.'
  exit 0
fi

# A sealed/uninitialized Vault returns exit code 2 with valid status JSON.
deadline=$((SECONDS + 300))
until vault status -format=json > status.json 2>/dev/null || jq -e 'has("initialized")' status.json >/dev/null 2>&1; do
  (( SECONDS < deadline )) || { echo 'Vault API unavailable; inspect journalctl -u vault.' >&2; exit 1; }
  sleep 2
done
if [[ -e init.json.tmp ]]; then
  jq -e '.root_token and .recovery_keys_b64' init.json.tmp >/dev/null || {
    echo 'Incomplete init.json.tmp; inspect initialization state before retrying.' >&2; exit 1;
  }
  [[ ! -e init.json ]] || { echo 'Both initialization files exist; inspect before retrying.' >&2; exit 1; }
  mv init.json.tmp init.json
fi
if jq -e '.initialized == false' status.json >/dev/null; then
  [[ ! -e init.json ]] || { echo 'Saved initialization material exists but Vault is uninitialized; refusing to overwrite.' >&2; exit 1; }
  vault operator init -format=json -recovery-shares=1 -recovery-threshold=1 > init.json.tmp
  mv init.json.tmp init.json
fi
[[ -s init.json ]] || { echo 'Vault is initialized but saved init.json is missing; restore the lab recovery material.' >&2; exit 1; }
export VAULT_TOKEN
VAULT_TOKEN=$(jq -er '.root_token' init.json)
cat > admin.env <<'ENV'
unset VAULT_NAMESPACE
export VAULT_ADDR=http://127.0.0.1:8200 VAULT_CLIENT_TIMEOUT=60s
export VAULT_TOKEN
VAULT_TOKEN=$(jq -er '.root_token' /root/oracle-baseline/init.json)
ENV
deadline=$((SECONDS + 300))
until vault status -format=json > status.json 2>/dev/null && jq -e '.sealed == false' status.json >/dev/null; do
  (( SECONDS < deadline )) || { echo 'Vault did not auto-unseal; inspect KMS access and Vault logs.' >&2; exit 1; }
  sleep 2
done

echo 'Waiting up to 30 minutes for Oracle XEPDB1 to open.'
deadline=$((SECONDS + 1800))
while :; do
  if result=$(timeout 30 docker exec --user oracle -i oracle-db sqlplus -L -s / as sysdba 2>/dev/null <<'SQL'
WHENEVER SQLERROR EXIT FAILURE
WHENEVER OSERROR EXIT FAILURE
SET HEADING OFF FEEDBACK OFF
ALTER SESSION SET CONTAINER = XEPDB1;
SELECT 'PDB_READY' FROM v$pdbs WHERE name = 'XEPDB1' AND open_mode = 'READ WRITE';
EXIT
SQL
  ) && [[ $result == *PDB_READY* ]]; then break; fi
  (( SECONDS < deadline )) || { echo 'Oracle not ready; inspect docker logs oracle-db privately.' >&2; exit 1; }
  sleep 10
done

[[ -s manager-password ]] || printf 'A1%s\n' "$(openssl rand -hex 12)" > manager-password
password=$(cat manager-password)
[[ $password =~ ^A1[0-9a-f]{24}$ ]] || { echo 'Unexpected saved manager-password format.' >&2; exit 1; }
# Only new accounts receive initial passwords. Import rotation owns static passwords afterward.
docker exec --user oracle -i oracle-db sqlplus -L -s / as sysdba > sql-setup.log 2>&1 <<SQL
WHENEVER SQLERROR EXIT FAILURE
WHENEVER OSERROR EXIT FAILURE
SET ECHO OFF VERIFY OFF
ALTER SESSION SET CONTAINER = XEPDB1;
DECLARE n NUMBER; u VARCHAR2(30);
BEGIN
  SELECT COUNT(*) INTO n FROM dba_users WHERE username = 'VAULT_MANAGER';
  IF n = 0 THEN
    EXECUTE IMMEDIATE 'CREATE USER VAULT_MANAGER IDENTIFIED BY "$password"';
  END IF;
  FOR i IN 1..$static_count LOOP
    u := 'LAB_STATIC_' || TO_CHAR(i, 'FM0000');
    SELECT COUNT(*) INTO n FROM dba_users WHERE username = u;
    IF n = 0 THEN
      EXECUTE IMMEDIATE 'CREATE USER ' || u || ' IDENTIFIED BY "A1' || DBMS_RANDOM.STRING('x', 24) || '"';
      EXECUTE IMMEDIATE 'GRANT CREATE SESSION TO ' || u;
    END IF;
  END LOOP;
END;
/
GRANT CREATE SESSION TO VAULT_MANAGER WITH ADMIN OPTION;
GRANT CREATE USER, ALTER USER, DROP USER, ALTER SYSTEM TO VAULT_MANAGER;
GRANT SELECT ON SYS.GV_\$SESSION TO VAULT_MANAGER;
GRANT SELECT ON SYS.V_\$SESSION TO VAULT_MANAGER;
GRANT SELECT ON SYS.V_\$SQL TO VAULT_MANAGER;
EXIT
SQL

vault secrets list -format=json > mounts.json
if ! jq -e 'has("oracle-db/")' mounts.json >/dev/null; then
  vault secrets enable -path=oracle-db database >/dev/null
fi
vault plugin register -version="$plugin_version" database vault-plugin-database-oracle >/dev/null
plugin_binary="/opt/vault/plugins/vault-plugin-database-oracle_${plugin_version}_linux_amd64/vault-plugin-database-oracle"
test -x "$plugin_binary"
runuser -u vault -- ldd "$plugin_binary" > plugin-libraries.txt
if grep -q 'not found' plugin-libraries.txt; then
  echo 'Oracle plugin has missing libraries; inspect plugin-libraries.txt.' >&2; exit 1
fi

cat > password-policy.hcl <<'HCL'
length = 24
rule "charset" {
  charset = "abcdefghijklmnopqrstuvwxyz"
  min-chars = 1
}
rule "charset" {
  charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  min-chars = 1
}
rule "charset" {
  charset = "0123456789"
  min-chars = 1
}
HCL
vault write sys/policies/password/oracle-baseline policy=@password-policy.hcl >/dev/null
if ! vault read oracle-db/config/oracle >/dev/null 2>&1; then
  jq -n --arg password "$password" --arg version "$plugin_version" --arg host "$oracle_host" '{
    plugin_name: "vault-plugin-database-oracle", plugin_version: $version,
    allowed_roles: ["static-*", "dynamic-*"], verify_connection: true,
    connection_url: ("{{username}}/{{password}}@" + $host + ":1521/XEPDB1"),
    username: "VAULT_MANAGER", password: $password, password_policy: "oracle-baseline"
  }' > connection.json
  vault write oracle-db/config/oracle @connection.json >/dev/null
  rm connection.json
fi
unset password

echo "Creating $static_count static roles and $dynamic_count dynamic-role definitions."
for ((i=1; i<=static_count; i++)); do
  printf -v suffix '%04d' "$i"
  if ! vault read "oracle-db/static-roles/static-$suffix" >/dev/null 2>&1; then
    vault write "oracle-db/static-roles/static-$suffix" db_name=oracle username="LAB_STATIC_$suffix" \
      rotation_period="$rotation_period" \
      rotation_statements='ALTER USER {{name}} IDENTIFIED BY "{{password}}" ACCOUNT UNLOCK' >/dev/null
  fi
done
for ((i=1; i<=dynamic_count; i++)); do
  printf -v suffix '%04d' "$i"
  if ! vault read "oracle-db/roles/dynamic-$suffix" >/dev/null 2>&1; then
    vault write "oracle-db/roles/dynamic-$suffix" db_name=oracle default_ttl=1h max_ttl=24h \
      creation_statements='CREATE USER {{name}} IDENTIFIED BY "{{password}}"; GRANT CREATE SESSION TO {{name}}' \
      revocation_statements='DROP USER {{name}} CASCADE' >/dev/null
  fi
done

/usr/local/sbin/oracle-baseline-verify
echo 'Healthy Oracle baseline ready. Read verification.json for actual checks and versions.'
