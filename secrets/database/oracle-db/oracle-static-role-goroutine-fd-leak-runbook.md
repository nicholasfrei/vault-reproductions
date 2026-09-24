# Oracle Static-Role Rotation Goroutine, Thread, and FD Leak Runbook

## Overview

This runbook reproduces the resource-growth pattern behind `VAULT-50722` using the Oracle database plugin in Vault `1.21.9+ent`. It also demonstrates an interim mitigation for this resource growth.

The pattern traces back to `VAULT-43596`, where a hanging MySQL handshake stalled an entire static-role rotation queue. The fix for that ticket (`vault-enterprise` [PR #13697](https://github.com/hashicorp/vault-enterprise/pull/13697)) added a goroutine-plus-timeout race around the plugin's `UpdateUser` and `Initialize` calls so one hung connection could not block rotation for every other role in the mount. That fix bounds Vault's own wait, but it does not stop the underlying plugin call from continuing to run if the driver ignores context cancellation (which the Oracle driver does). 

With the Oracle database plugin, the driver (`github.com/mattn/go-oci8`) never implements Go's `driver.DriverContext`, so establishing a new physical connection against an unreachable target can block indefinitely. Each forced or automatic rotation attempt against a stale static role then abandons another goroutine, and because the blocking call is cgo, it also pins a real OS thread and the partially-established socket/file descriptor, with nothing available to interrupt it.

This runbook builds a Vault node and Oracle container, deliberately makes the Oracle target unreachable, forces repeated static-role rotation against it, and compares goroutine, OS thread, and file descriptor counts before and after applying a client connect timeout. 

The runbook uses these versions:

- Vault Enterprise `1.21.9+ent`
- Oracle Instant Client `19.32`
- `vault-plugin-database-oracle` `0.11.0+ent`
- Oracle Database XE `21.3.0-xe`

## Objective

- Provision a single EC2 host and install Vault Enterprise `1.21.9+ent`, the Oracle database secrets engine, Oracle Instant Client `19.32`, and `vault-plugin-database-oracle` `0.11.0+ent` from scratch.
- Stand up an Oracle container and configure a static role pointed at a target that will be made unreachable.
- Confirm the target hangs on connect (not a fast failure) before running the full reproduction.
- Force repeated static-role rotation against the unreachable target and record goroutine, OS thread, and file descriptor counts across attempts.
- Apply the `sqlnet.ora`/`TNS_ADMIN` mitigation, restart Vault, and repeat the same measurement loop.
- Compare the two loops and confirm growth becomes bounded after the mitigation.

## Prerequisites

- An AWS EC2 instance running Amazon Linux 2023 or later, `t3.medium` or larger, at least 30 GiB of root storage, with a security group allowing inbound SSH (port 22) from your admin CIDR and outbound HTTPS (port 443) to `releases.hashicorp.com` and `download.oracle.com`.
- A Vault Enterprise license.
- `sudo` access on that instance.
- `jq`, `curl`, `lsof`, `unzip`, and `wget`. On Amazon Linux 2023 install what is missing with `sudo dnf install -y jq curl lsof unzip wget`.

## Step 1: Connect to the EC2 instance

SSH into the instance you provisioned under Prerequisites:

```bash
ssh -i <path_to_key.pem> ec2-user@<instance_public_ip>
```

Run every remaining step on this instance unless noted otherwise.

## Step 2: Install Vault Enterprise 1.21.9+ent

```bash
export VAULT_VERSION="1.21.9+ent"
wget "https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip"
unzip "vault_${VAULT_VERSION}_linux_amd64.zip"
sudo mv vault /usr/local/bin/
vault --version
```

```text
Vault v1.21.9+ent (...)
```

Create the plugin directory Vault will use, before starting the server:

```bash
sudo mkdir -p /etc/vault.d/plugins
sudo chmod 755 /etc/vault.d/plugins
```

## Step 3: Start the Vault dev server

In terminal A, set the license and start the dev server in the foreground. Leave this terminal open for the rest of the runbook:

```bash
export VAULT_LICENSE="<vault_license>"
export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="root"
sudo -E vault server -dev -dev-root-token-id="root" -dev-plugin-dir=/etc/vault.d/plugins
```

In terminal B, confirm the server is reachable:

```bash
export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="root"
vault status
```

```text
Version              1.21.9+ent
Storage Type          inmem
HA Enabled             false
```

The dev server uses in-memory storage. Every Vault configuration made in this runbook is lost if the Vault process restarts, including during Step 13. That is expected and is called out again there.

## Step 4: Install Docker and start the Oracle container

```bash
sudo dnf install -y docker
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker "$(whoami)"
```

Log out and back in for the group change to take effect, or prefix Docker commands with `sudo` for the rest of this runbook.

Start the Oracle Database XE container used as the reproduction target:

```bash
sudo docker run -d --name oracle-db -p 1521:1521 -e ORACLE_PWD=admin container-registry.oracle.com/database/express:21.3.0-xe
```

Wait for the container to finish initializing:

```bash
sudo docker logs -f oracle-db
```

Wait until `DATABASE IS READY TO USE` appears, then `Ctrl+C` to stop following the logs. Confirm the container is running:

```bash
sudo docker ps --filter "name=oracle-db"
```

## Step 5: Create the Oracle admin account Vault will use

```bash
sudo docker exec -it oracle-db sqlplus sys as sysdba
```

Enter password `admin` when prompted, then run:

```sql
ALTER SESSION SET CONTAINER = XEPDB1;
CREATE USER vaultuser IDENTIFIED BY "vault";
GRANT DBA TO vaultuser;
GRANT CREATE USER TO vaultuser WITH ADMIN OPTION;
GRANT ALTER USER TO vaultuser WITH ADMIN OPTION;
GRANT DROP USER TO vaultuser WITH ADMIN OPTION;
GRANT CONNECT TO vaultuser WITH ADMIN OPTION;
GRANT CREATE SESSION TO vaultuser WITH ADMIN OPTION;
GRANT SELECT ON gv_$session TO vaultuser;
GRANT SELECT ON v_$sql TO vaultuser;
GRANT ALTER SYSTEM TO vaultuser WITH ADMIN OPTION;
exit;
```

This is the admin user Vault's connection config will authenticate as; it needs `ALTER USER` privilege to run the static role's rotation statement against other accounts.

## Step 6: Install Oracle Instant Client 19.32

```bash
cd "$HOME"
wget https://download.oracle.com/otn_software/linux/instantclient/1932000/instantclient-basic-linux.x64-19.32.0.0.0dbru.zip
sudo mkdir -p /opt/oracle
sudo unzip -q instantclient-basic-linux.x64-19.32.0.0.0dbru.zip -d /opt/oracle
sudo dnf install -y libaio libnsl
```

The Basic package is sufficient for the prebuilt Oracle plugin; the SDK package is only needed if you are compiling software against Instant Client headers.

Point the system dynamic linker at the new client and refresh its cache:

```bash
echo /opt/oracle/instantclient_19_32 | sudo tee /etc/ld.so.conf.d/oracle-instantclient.conf
sudo ldconfig
```

Confirm the linker resolves the client library:

```bash
ldconfig -p | grep 'libclntsh.so.19.1'
```

```text
libclntsh.so.19.1 (libc6,x86-64) => /opt/oracle/instantclient_19_32/libclntsh.so.19.1
```

## Step 7: Enable the database secrets engine and register the Oracle plugin

```bash
vault secrets enable database
vault plugin register -version="0.11.0+ent" -download=true database vault-plugin-database-oracle
```

Confirm the registration:

```bash
vault plugin info -version="0.11.0+ent" database vault-plugin-database-oracle
```

```text
Key                   Value
---                   -----
args                  []
builtin               false
name                  vault-plugin-database-oracle
version               v0.11.0+ent
```

Confirm the downloaded plugin binary resolves the 19.32 client library before you use it:

```bash
PLUGIN_BINARY=/etc/vault.d/plugins/.runtime/vault-plugin-database-oracle_0.11.0+ent_linux_amd64/vault-plugin-database-oracle
sudo ldd "$PLUGIN_BINARY" | grep 'libclntsh.so.19.1'
```

```text
libclntsh.so.19.1 => /opt/oracle/instantclient_19_32/libclntsh.so.19.1 (0x...)
```

If this instead needs to be checked against a running Vault process later, also confirm Vault itself was not started with an `LD_LIBRARY_PATH` pinned to a different Instant Client directory, which would override the linker cache for the plugin subprocess:

```bash
VAULT_PID=$(pgrep -x vault)
sudo cat "/proc/$VAULT_PID/environ" | tr '\0' '\n' | grep '^LD_LIBRARY_PATH=' || true
```

This runbook does not set `LD_LIBRARY_PATH`, so this should print nothing. If you ever need to change the linked Instant Client version later without restarting the whole dev server (which would discard its in-memory configuration), reload just the plugin process instead of the Vault server:

```bash
vault plugin reload -type=database -plugin=vault-plugin-database-oracle
```

## Step 8: Configure the Oracle database connection in Vault

```bash
vault write database/config/oracle \
  plugin_name=vault-plugin-database-oracle \
  allowed_roles="*" \
  connection_url="vaultuser/vault@localhost:1521/XEPDB1"
```

```bash
vault read database/config/oracle
```

Expected result: the connection config is returned without error. This write also spawns the Oracle plugin subprocess for the first time. Confirm the running plugin process loaded the 19.32 client library:

```bash
sudo lsof -nP | grep 'libclntsh.so.19.1'
```

```text
vault-plu 12345 root  mem    REG  259,1  ... /opt/oracle/instantclient_19_32/libclntsh.so.19.1
```

## Step 9: Create the dedicated static role for this reproduction

Use a separate role and username from any other static roles you may add later, so cleanup stays isolated:

```bash
sudo docker exec -it oracle-db sqlplus sys as sysdba
```

Enter password `admin` when prompted, then run:

```sql
ALTER SESSION SET CONTAINER = XEPDB1;
CREATE USER leakrepro IDENTIFIED BY "TempPassword8";
GRANT CONNECT TO leakrepro;
GRANT CREATE SESSION TO leakrepro;
exit;
```

Create the static role against the `oracle` connection:

```bash
vault write database/static-roles/leak-repro-static \
  db_name=oracle \
  username=leakrepro \
  rotation_statements='ALTER USER {{name}} IDENTIFIED BY "{{password}}" ACCOUNT UNLOCK' \
  rotation_period="24h"
```

Confirm it rotates successfully against the reachable target before breaking anything:

```bash
vault write -f database/rotate-role/leak-repro-static
```

Expected result: the command returns quickly with no error.

## Step 10: Capture a baseline

Baseline goroutine count:

```bash
VAULT_PID=$(pgrep -x vault)
curl -s --header "X-Vault-Token: $VAULT_TOKEN" \
  "$VAULT_ADDR/v1/sys/pprof/goroutine?debug=1" | head -1
```

Baseline OS thread count and file descriptor count:

```bash
awk '/^Threads:/{print $2}' "/proc/$VAULT_PID/status"
sudo lsof -p "$VAULT_PID" | wc -l
```

A supplied lab run recorded this baseline:

```text
goroutine profile: total 478
Threads: 8
lsof output lines: 20
```

The `lsof` count includes its header line. Record the current values from your own run; counts vary by environment and are the "before" values for later comparisons.

## Step 11: Make the target a network black hole

This step is destructive to host networking until it is removed in Step 13 or Cleanup. It only affects outbound traffic to `127.0.0.1:1521` from this host.

Add an `iptables` rule that silently drops packets to the Oracle container's published port, instead of the OS immediately refusing the connection:

```bash
sudo iptables -I OUTPUT 1 -p tcp -d 127.0.0.1 --dport 1521 -j DROP
```

Confirm this produces a hang rather than a fast failure before running the full loop:

```bash
time timeout 5 bash -c 'echo > /dev/tcp/127.0.0.1/1521'
```

```text
real	0m5.002s
```

Expected result: the command blocks for the full 5 seconds and then is killed by `timeout`, rather than returning immediately with `Connection refused`. If it returns immediately, the `DROP` rule is not being hit (check for an earlier `ACCEPT` rule in the `OUTPUT` chain) and the rest of this runbook will not reproduce the leak.

## Step 12: Force repeated rotation and observe unbounded growth

Each `rotate-role` call now blocks for approximately 10 seconds (Vault's internal `staticUpdateUserTimeout`) before returning a timeout error, because the underlying connection attempt is abandoned, not completed.

```bash
for i in $(seq 1 6); do
  start=$(date +%s)
  vault write -f database/rotate-role/leak-repro-static >/tmp/rotate-attempt-"$i".log 2>&1
  duration=$(( $(date +%s) - start ))
  goroutines=$(curl -s --header "X-Vault-Token: $VAULT_TOKEN" \
    "$VAULT_ADDR/v1/sys/pprof/goroutine?debug=1" | head -1 | awk '{print $NF}')
  threads=$(awk '/^Threads:/{print $2}' "/proc/$VAULT_PID/status")
  fds=$(sudo lsof -p "$VAULT_PID" | wc -l)
  echo "attempt=$i duration=${duration}s goroutines=$goroutines threads=$threads fds=$fds"
done
```

Example output (yours will vary in absolute numbers, but should trend the same way):

```text
attempt=1 duration=10s goroutines=89 threads=24 fds=142
attempt=2 duration=10s goroutines=91 threads=25 fds=146
attempt=3 duration=10s goroutines=93 threads=26 fds=150
attempt=4 duration=10s goroutines=95 threads=27 fds=154
attempt=5 duration=10s goroutines=97 threads=28 fds=158
attempt=6 duration=10s goroutines=99 threads=29 fds=162
```

Observed result: goroutines, threads, and file descriptors each climb by a roughly constant amount every attempt, and every attempt takes the full ~10 seconds. Nothing plateaus. Check one of the logged attempts:

```bash
cat /tmp/rotate-attempt-1.log
```

```text
Error writing data to database/rotate-role/leak-repro-static: Error making API request.

URL: PUT http://127.0.0.1:8200/v1/database/rotate-role/leak-repro-static
Code: 400. Errors:

* error setting credentials: timeout exceeded during UpdateUser
```

This is Vault giving up waiting, not the plugin reporting a real Oracle error. The abandoned goroutine, its pinned OS thread, and its socket are still out there.

## Step 13: Apply the sqlnet.ora and TNS_ADMIN mitigation

Create a dedicated Oracle Net admin directory so this change is scoped to Vault and does not affect other Oracle clients on the host:

```bash
sudo mkdir -p /etc/vault.d/oracle-network-admin
```

```bash
sudo tee /etc/vault.d/oracle-network-admin/sqlnet.ora >/dev/null <<'EOF'
SQLNET.OUTBOUND_CONNECT_TIMEOUT=3
TCP.CONNECT_TIMEOUT=5
EOF
```

`SQLNET.RECV_TIMEOUT`/`SQLNET.SEND_TIMEOUT` only bound how long a client waits for data after a connection is already established — they don't apply to a hang during the connect phase itself, so they're omitted here.

`TNS_ADMIN` is read by the Oracle client library from the environment of the process that loads it. The already-running Vault process does not have it set, and a plugin subprocess only inherits environment variables from Vault at the moment Vault spawns it, so this requires restarting the Vault process itself, not just reloading the plugin.

In terminal A, stop the dev server (`Ctrl+C`), then restart it with `TNS_ADMIN` exported:

```bash
export TNS_ADMIN=/etc/vault.d/oracle-network-admin
export VAULT_LICENSE="<vault_license>"
sudo -E vault server -dev -dev-root-token-id="root" -dev-plugin-dir=/etc/vault.d/plugins
```

The dev server's storage is in-memory, so the restart discarded the database secrets engine mount, the connection, and the static role. In terminal B, replay the configuration from Steps 7 through 9:

```bash
export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="root"
VAULT_PID=$(pgrep -x vault)

vault secrets enable database
vault plugin register -version="0.11.0+ent" -download=true database vault-plugin-database-oracle

vault write database/config/oracle \
  plugin_name=vault-plugin-database-oracle \
  allowed_roles="*" \
  connection_url="vaultuser/vault@localhost:1521/XEPDB1"

vault write database/static-roles/leak-repro-static \
  db_name=oracle \
  username=leakrepro \
  rotation_statements='ALTER USER {{name}} IDENTIFIED BY "{{password}}" ACCOUNT UNLOCK' \
  rotation_period="24h"
```

The `leakrepro` Oracle user itself still exists in the database container, since only Vault's process restarted, not the Oracle container; you do not need to recreate it.

Restarting Vault also resets goroutine, thread, and file descriptor counts to a fresh baseline. That is expected: this step demonstrates a change in behavior going forward, not retroactive cleanup of anything already leaked.

## Step 14: Repeat the loop and observe bounded growth

The `iptables` `DROP` rule from Step 11 should still be in place; the target must still be unreachable so this step demonstrates a bounded failure, not a restored connection.

```bash
for i in $(seq 1 6); do
  start=$(date +%s)
  vault write -f database/rotate-role/leak-repro-static >/tmp/rotate-attempt-fixed-"$i".log 2>&1
  duration=$(( $(date +%s) - start ))
  goroutines=$(curl -s --header "X-Vault-Token: $VAULT_TOKEN" \
    "$VAULT_ADDR/v1/sys/pprof/goroutine?debug=1" | head -1 | awk '{print $NF}')
  threads=$(awk '/^Threads:/{print $2}' "/proc/$VAULT_PID/status")
  fds=$(sudo lsof -p "$VAULT_PID" | wc -l)
  echo "attempt=$i duration=${duration}s goroutines=$goroutines threads=$threads fds=$fds"
done
```

Example output (yours will vary in absolute numbers, but should stay flat rather than trend upward):

```text
attempt=1 duration=3s goroutines=88 threads=23 fds=141
attempt=2 duration=3s goroutines=88 threads=23 fds=141
attempt=3 duration=3s goroutines=89 threads=23 fds=142
attempt=4 duration=3s goroutines=88 threads=23 fds=141
attempt=5 duration=3s goroutines=89 threads=23 fds=142
attempt=6 duration=3s goroutines=88 threads=23 fds=141
```

Observed result: each attempt now returns in roughly the configured `sqlnet.ora` timeout instead of Vault's 10-second internal timeout, and goroutine, thread, and file descriptor counts stay flat across attempts instead of climbing. Check a logged attempt:

```bash
cat /tmp/rotate-attempt-fixed-1.log
```

## Validation

Compare the two loops from Steps 12 and 14 side by side:

- Goroutine count
- OS thread count
- File descriptor count
- Error text: `timeout exceeded during UpdateUser` (Vault gave up) versus an `ORA-` error (the driver actually returned).

If Step 14 still shows climbing counts, confirm `TNS_ADMIN` was exported in the same shell that started `vault server`, and that no other `sqlnet.ora` earlier in Oracle's search path (`ORACLE_BASE_HOME/network/admin`, `ORACLE_HOME/network/admin`) is taking precedence.

## Cleanup

Remove the firewall rule so the host's networking returns to normal:

```bash
sudo iptables -D OUTPUT -p tcp -d 127.0.0.1 --dport 1521 -j DROP
```

Stop and remove the Oracle container:

```bash
sudo docker stop oracle-db
sudo docker rm oracle-db
```

Stop the Vault dev server (`Ctrl+C` in terminal A) and remove log files:

```bash
rm -f /tmp/rotate-attempt-*.log
```

## Conclusion

The goroutine-plus-timeout pattern introduced for `VAULT-43596` bounds how long Vault itself waits on a blocking database call, but it cannot stop a plugin call that ignores context cancellation from continuing to run. With the Oracle database plugin, that gap is at the driver's connection-establishment layer, which is not interruptible from Go. Bounding the driver's own connect timeout with `SQLNET.OUTBOUND_CONNECT_TIMEOUT` converts an unbounded per-retry leak into a self-resolving failure without requiring a new Vault or plugin binary. 

>Disclaimer: It does not fix the cancellation itself, and it applies to every Oracle connection made under the same `TNS_ADMIN` scope, so choose the timeout value with legitimately slow, healthy listeners in mind.

## References

- [mattn/go-oci8 issue #419: Context cancelation not being honored](https://github.com/mattn/go-oci8/issues/419)
- [Oracle Net Services Reference: Parameters for the sqlnet.ora File](https://docs.oracle.com/en/database/oracle/oracle-database/21/netrf/parameters-for-the-sqlnet.ora.html)
- [Oracle Instant Client for Linux x86-64 Downloads](https://www.oracle.com/database/technologies/instant-client/linux-x86-64-downloads.html)
- [Vault Enterprise PR #13697](https://github.com/hashicorp/vault-enterprise/pull/13697)