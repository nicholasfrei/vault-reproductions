#!/usr/bin/env bash
set -euo pipefail
set +x
umask 077
source /etc/oracle-lab/lab.env

if [[ $(id -u) -ne 0 ]]; then
  echo 'Run setup as root on the disposable Oracle lab VM.' >&2
  exit 1
fi

export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN
VAULT_TOKEN=$(cat /root/oracle-lab/token)
rm -f /root/oracle-lab/READY

for i in $(seq 1 60); do
  if vault status >/dev/null 2>&1; then break; fi
  if (( i == 60 )); then echo 'Vault dev API did not become ready.' >&2; exit 1; fi
  sleep 2
done

echo 'Waiting for Oracle XE and XEPDB1 (up to 30 minutes).'
for i in $(seq 1 180); do
  if result=$(docker exec --user oracle -i oracle-lab sqlplus -L -s / as sysdba 2>/dev/null <<'SQL'
WHENEVER SQLERROR EXIT FAILURE
ALTER SESSION SET CONTAINER = XEPDB1;
SELECT 'LAB_PDB_READY' FROM v$pdbs WHERE name = 'XEPDB1' AND open_mode = 'READ WRITE';
EXIT
SQL
  ) && [[ $result == *LAB_PDB_READY* ]]; then
    break
  fi
  if (( i == 180 )); then echo 'Oracle XEPDB1 did not become ready; inspect Docker logs privately.' >&2; exit 1; fi
  sleep 10
done

if [[ ! -s /root/oracle-lab/root-password ]]; then
  openssl rand -hex 12 > /root/oracle-lab/root-password
fi
password=$(cat /root/oracle-lab/root-password)
control_old=$(openssl rand -hex 12)
control_new=$(openssl rand -hex 12)
trap 'unset password control_old control_new VAULT_TOKEN' EXIT
if [[ ! $password =~ ^[0-9a-f]{24}$ ]]; then
  echo 'Unexpected test password format; refusing to embed it in Oracle SQL.' >&2
  exit 1
fi

if ! docker exec --user oracle -i oracle-lab sqlplus -L -s / as sysdba >/dev/null 2>&1 <<SQL
WHENEVER SQLERROR EXIT FAILURE
WHENEVER OSERROR EXIT FAILURE
SET ECHO OFF VERIFY OFF
ALTER SESSION SET CONTAINER = XEPDB1;
DECLARE n NUMBER;
BEGIN
  SELECT COUNT(*) INTO n FROM dba_objects WHERE owner = 'SYS' AND object_name = 'LAB_VERIFY';
  IF n = 0 THEN
    EXECUTE IMMEDIATE 'CREATE FUNCTION LAB_VERIFY (username VARCHAR2, password VARCHAR2, old_password VARCHAR2) RETURN BOOLEAN IS BEGIN RETURN LENGTH(password) >= 12; END;';
  END IF;
  SELECT COUNT(*) INTO n FROM dba_profiles WHERE profile = 'LAB_PROFILE';
  IF n = 0 THEN
    EXECUTE IMMEDIATE 'CREATE PROFILE LAB_PROFILE LIMIT PASSWORD_VERIFY_FUNCTION LAB_VERIFY';
  END IF;
  SELECT COUNT(*) INTO n FROM dba_profiles WHERE profile = 'LAB_PROFILE' AND resource_name = 'PASSWORD_VERIFY_FUNCTION' AND limit = 'LAB_VERIFY';
  IF n != 1 THEN RAISE_APPLICATION_ERROR(-20001, 'unexpected test password verification function'); END IF;
  SELECT COUNT(*) INTO n FROM dba_users WHERE username = 'VAULT_LAB';
  IF n = 0 THEN
    EXECUTE IMMEDIATE 'CREATE USER VAULT_LAB IDENTIFIED BY "$password" PROFILE LAB_PROFILE';
    EXECUTE IMMEDIATE 'GRANT CREATE SESSION TO VAULT_LAB';
  ELSE
    SELECT COUNT(*) INTO n FROM dba_users WHERE username = 'VAULT_LAB' AND profile = 'LAB_PROFILE';
    IF n != 1 THEN RAISE_APPLICATION_ERROR(-20001, 'unexpected test account profile'); END IF;
    SELECT COUNT(*) INTO n FROM dba_sys_privs WHERE grantee = 'VAULT_LAB' AND privilege != 'CREATE SESSION';
    IF n != 0 THEN RAISE_APPLICATION_ERROR(-20001, 'unexpected test account privileges'); END IF;
    SELECT COUNT(*) INTO n FROM dba_sys_privs WHERE grantee = 'VAULT_LAB' AND privilege = 'CREATE SESSION';
    IF n != 1 THEN RAISE_APPLICATION_ERROR(-20001, 'missing test account session privilege'); END IF;
    SELECT COUNT(*) INTO n FROM dba_role_privs WHERE grantee = 'VAULT_LAB';
    IF n != 0 THEN RAISE_APPLICATION_ERROR(-20001, 'unexpected test account roles'); END IF;
    EXECUTE IMMEDIATE 'ALTER USER VAULT_LAB IDENTIFIED BY "$password"';
  END IF;
  SELECT COUNT(*) INTO n FROM dba_users WHERE username = 'LAB_CONTROL';
  IF n = 0 THEN
    EXECUTE IMMEDIATE 'CREATE USER LAB_CONTROL IDENTIFIED BY "$control_old" PROFILE LAB_PROFILE';
    EXECUTE IMMEDIATE 'GRANT CREATE SESSION TO LAB_CONTROL';
  ELSE
    SELECT COUNT(*) INTO n FROM dba_users WHERE username = 'LAB_CONTROL' AND profile = 'LAB_PROFILE';
    IF n != 1 THEN RAISE_APPLICATION_ERROR(-20001, 'unexpected control account profile'); END IF;
    SELECT COUNT(*) INTO n FROM dba_sys_privs WHERE grantee = 'LAB_CONTROL' AND privilege != 'CREATE SESSION';
    IF n != 0 THEN RAISE_APPLICATION_ERROR(-20001, 'unexpected control account privileges'); END IF;
    SELECT COUNT(*) INTO n FROM dba_role_privs WHERE grantee = 'LAB_CONTROL';
    IF n != 0 THEN RAISE_APPLICATION_ERROR(-20001, 'unexpected control account roles'); END IF;
    EXECUTE IMMEDIATE 'ALTER USER LAB_CONTROL IDENTIFIED BY "$control_old"';
  END IF;
END;
/
EXIT
SQL
then
  echo 'Oracle test account setup failed; SQL output suppressed to protect passwords.' >&2
  exit 1
fi

if ! printf 'WHENEVER SQLERROR EXIT FAILURE\nCONNECT LAB_CONTROL/%s@//127.0.0.1:1521/XEPDB1\nALTER USER LAB_CONTROL IDENTIFIED BY "%s" REPLACE "%s";\nEXIT\n' \
  "$control_old" "$control_new" "$control_old" |
  docker exec --user oracle -i oracle-lab sqlplus -L -s /nolog >/dev/null 2>&1; then
  echo 'Oracle REPLACE control failed without ALTER USER; check the test profile privately.' >&2
  exit 1
fi
if ! printf 'WHENEVER SQLERROR EXIT FAILURE\nCONNECT LAB_CONTROL/%s@//127.0.0.1:1521/XEPDB1\nSELECT 1 FROM dual;\nEXIT\n' "$control_new" |
  docker exec --user oracle -i oracle-lab sqlplus -L -s /nolog >/dev/null 2>&1; then
  echo 'The Oracle control password did not authenticate after REPLACE.' >&2
  exit 1
fi
echo 'Oracle self-rotation with REPLACE succeeded without ALTER USER.'

if ! vault plugin info -version="$ORACLE_PLUGIN_VERSION" database vault-plugin-database-oracle >/dev/null 2>&1; then
  vault plugin register -version="$ORACLE_PLUGIN_VERSION" -download=true database vault-plugin-database-oracle >/dev/null
fi

plugin_binary="/opt/vault/plugins/.runtime/vault-plugin-database-oracle_${ORACLE_PLUGIN_VERSION}_linux_amd64/vault-plugin-database-oracle"
if [[ ! -x $plugin_binary ]]; then
  echo 'The downloaded Oracle plugin binary is missing or not executable.' >&2
  exit 1
fi
if ! dependencies=$(sudo -u vault ldd "$plugin_binary" 2>&1); then
  echo 'Unable to inspect Oracle plugin library dependencies as the vault user.' >&2
  exit 1
fi
if [[ $dependencies == *'not found'* ]]; then
  printf '%s\n' "$dependencies" | grep 'not found' >&2
  echo 'Oracle plugin libraries are missing or inaccessible to the vault user.' >&2
  exit 1
fi

if vault secrets list -format=json | python3 -c 'import json,sys; sys.exit("oracle-db/" not in json.load(sys.stdin))'; then
  if vault read -format=json oracle-db/config/oracle >/dev/null 2>&1; then
    echo 'oracle-db/ already has a connection; refusing to overwrite an engineer’s test configuration.' >&2
    exit 1
  fi
  echo 'Resuming the existing oracle-db/ mount after an incomplete setup.'
else
  vault secrets enable -path=oracle-db database >/dev/null
fi
if ! printf '%s' "$password" | vault write oracle-db/config/oracle \
  plugin_name=vault-plugin-database-oracle \
  plugin_version="$ORACLE_PLUGIN_VERSION" \
  connection_url='{{username}}/{{password}}@127.0.0.1:1521/XEPDB1' \
  username=VAULT_LAB password=- verify_connection=true >/dev/null 2>&1; then
  echo 'Vault Oracle connection verification failed; check plugin and Instant Client privately.' >&2
  exit 1
fi

date -u +%FT%TZ > /root/oracle-lab/READY
echo 'Oracle lab ready: stock Oracle connection at oracle-db/config/oracle.'
