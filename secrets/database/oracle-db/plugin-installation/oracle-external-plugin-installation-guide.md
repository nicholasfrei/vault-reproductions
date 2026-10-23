# Install the external Oracle database plugin

This command-by-command guide is for customers and support engineers installing the official Enterprise Oracle plugin on existing Vault servers. It explains the host libraries, plugin files, catalog registration, and database connection as separate steps.

For automated Vault/Oracle provisioning and a 100/100 role population, use the [Oracle EC2 setup runbook](../oracle-ec2-setup-runbook.md). This guide configures an existing deployment and uses one temporary dynamic role to check the installation.

## Prerequisites and execution contexts

- An initialized, unsealed Vault Enterprise deployment with a license and a compatible Oracle plugin release. The examples select plugin `0.14.1+ent` and Instant Client `19.32`; consult the [compatibility matrix](https://developer.hashicorp.com/vault/docs/secrets/databases/oracle#oracle-plugin-compatibility) for the Vault requirement. These selections are not a new runtime-validation claim.
- Linux AMD64 Vault servers. The package commands below target Amazon Linux 2023; other distributions need their equivalent `libaio`/`libnsl` packages.
- Server access with `sudo`; `curl`, `unzip`, and `sha256sum`; and the actual OS user that runs Vault. Examples use `vault`.
- An administrative Bash/Vault CLI session and `jq` for catalog and database-mount configuration. Set `VAULT_ADDR`, the correct Vault namespace, and authentication for your intended cluster.
- For the connection check: a reachable Oracle PDB and a dedicated Oracle management account with the [documented user-management/session privileges](https://developer.hashicorp.com/vault/docs/secrets/databases/oracle#configure-the-plugin). Database provisioning and account creation are prerequisites here.

Commands marked “each Vault server” run on the machines where Vault executes plugins, not on your laptop. In HA, install the client libraries and manually distributed plugin files on every node that may become active. Register the plugin once in the cluster catalog after the files are ready.

## 1. Prepare the plugin directory on each Vault server

On each server, inspect the running Vault service's configuration to find its `plugin_directory` and OS user. Use that directory in subsequent commands:

```bash
set -euo pipefail
export PLUGIN_DIR=/opt/vault/plugins
export VAULT_OS_USER=vault
export VAULT_OS_GROUP
VAULT_OS_GROUP=$(id -gn "$VAULT_OS_USER")
export ORACLE_PLUGIN_VERSION=0.14.1+ent
export PLUGIN_ARCHIVE="vault-plugin-database-oracle_${ORACLE_PLUGIN_VERSION}_linux_amd64"

sudo install -d -m 0750 -o "$VAULT_OS_USER" -g "$VAULT_OS_GROUP" "$PLUGIN_DIR"
```

The running server configuration must include the matching path:

```hcl
plugin_directory = "/opt/vault/plugins"
```

If you changed this setting, restart Vault using your deployment's maintenance procedure. A restart interrupts that node; in HA, preserve quorum by restarting one node at a time and confirming it is unsealed before continuing. For the systemd lab:

```bash
sudo systemctl restart vault
vault status
```

Have the deployment's unseal mechanism available when restarting. An already-correct plugin directory does not require a restart.

## 2. Install Oracle Instant Client on each Vault server

Instant Client Basic supplies the runtime library `libclntsh.so.19.1`. The SDK supplies build headers and is needed when compiling a plugin, rather than running the released binary. Vault downloading the plugin does not install Instant Client for you.

If a compatible client is already installed and resolves correctly as the Vault OS user, retain it and proceed to the plugin installation.

On each Amazon Linux 2023 server:

```bash
sudo dnf install -y libaio libnsl unzip
work=$(mktemp -d)
curl --fail --location --retry 3 \
  https://download.oracle.com/otn_software/linux/instantclient/1932000/instantclient-basic-linux.x64-19.32.0.0.0dbru.zip \
  -o "$work/instantclient.zip"
sudo install -d -m 0755 /opt/oracle
sudo unzip -n "$work/instantclient.zip" -d /opt/oracle
printf '%s\n' /opt/oracle/instantclient_19_32 | \
  sudo tee /etc/ld.so.conf.d/oracle-instantclient.conf >/dev/null
sudo ldconfig
ldconfig -p | grep libclntsh
rm -rf "$work"
```

Expect the loader to resolve `libclntsh.so.19.1` to the installed client directory. A path configured only in your interactive shell's `LD_LIBRARY_PATH` does not establish that the systemd Vault process can find the library.

## 3. Install and register the official plugin

Choose one of the following distribution methods. Both use the same plugin name, version, and database connection configuration.

### A. Download and extract the release yourself

Use this path to see exactly which files Vault loads or to distribute approved artifacts to hosts without direct release-service access. For offline hosts, transfer the downloaded archive through your normal artifact-distribution process, then perform extraction on each Vault server.

On each server, using the variables from Step 1:

```bash
work=$(mktemp -d)
release_url="https://releases.hashicorp.com/vault-plugin-database-oracle/$ORACLE_PLUGIN_VERSION"
curl --fail --location --retry 3 "$release_url/$PLUGIN_ARCHIVE.zip" \
  -o "$work/$PLUGIN_ARCHIVE.zip"
curl --fail --location --retry 3 \
  "$release_url/vault-plugin-database-oracle_${ORACLE_PLUGIN_VERSION}_SHA256SUMS" \
  -o "$work/SHA256SUMS"
awk -v archive="$PLUGIN_ARCHIVE.zip" '$2 == archive { print; found=1 } END { exit !found }' \
  "$work/SHA256SUMS" > "$work/checksum"
(cd "$work" && sha256sum -c checksum)
```

For a new version, extract into a directory whose name matches the archive basename. If that version is already installed, verify the existing installation instead of overwriting a running plugin:

```bash
if sudo test -e "$PLUGIN_DIR/$PLUGIN_ARCHIVE"; then
  printf '%s\n' 'This version is already present; verify it with the checks below.'
else
  sudo install -d -m 0750 -o root -g "$VAULT_OS_GROUP" "$PLUGIN_DIR/$PLUGIN_ARCHIVE"
  sudo unzip "$work/$PLUGIN_ARCHIVE.zip" -d "$PLUGIN_DIR/$PLUGIN_ARCHIVE"
  sudo chown -R root:"$VAULT_OS_GROUP" "$PLUGIN_DIR/$PLUGIN_ARCHIVE"
  sudo chmod -R g+rX "$PLUGIN_DIR/$PLUGIN_ARCHIVE"
  sudo chmod 0750 "$PLUGIN_DIR/$PLUGIN_ARCHIVE/vault-plugin-database-oracle"
fi
rm -rf "$work"
```

Keep the complete extracted archive, including metadata and signatures. The required layout is:

```text
<plugin_directory>/
  vault-plugin-database-oracle_0.14.1+ent_linux_amd64/
    vault-plugin-database-oracle
    <other files supplied in the official archive>
```

On every server, verify execution permission and library resolution as the actual Vault OS user:

```bash
sudo -u "$VAULT_OS_USER" test -x "$PLUGIN_DIR/$PLUGIN_ARCHIVE/vault-plugin-database-oracle"
sudo -u "$VAULT_OS_USER" ldd "$PLUGIN_DIR/$PLUGIN_ARCHIVE/vault-plugin-database-oracle"
```

Resolve every `not found` dependency before continuing. If your Vault deployment enables `mlock`, apply the [documented plugin `ipc_lock` requirement](https://developer.hashicorp.com/vault/docs/secrets/databases/oracle#configure-the-plugin) as well.

From an authenticated Vault CLI session, register the official package once:

```bash
export ORACLE_PLUGIN_VERSION=0.14.1+ent
vault plugin register -version="$ORACLE_PLUGIN_VERSION" \
  database vault-plugin-database-oracle
vault plugin info -version="$ORACLE_PLUGIN_VERSION" \
  database vault-plugin-database-oracle
```

For this official Enterprise package, use version-based registration. Keep its archive directory and official name; `-sha256`/`-command` instructions for a standalone community binary are a different registration format. Vault validates the official package's metadata/signatures during registration.

### B. Let Vault download the release

Vault Enterprise `1.20+` supports managed downloads. Each Vault node needs release-service access, a writable configured plugin directory, and the host libraries from Step 2. Check the selected plugin's compatibility requirements as well.

From an authenticated Vault CLI session:

```bash
export ORACLE_PLUGIN_VERSION=0.14.1+ent
vault plugin register -download=true -version="$ORACLE_PLUGIN_VERSION" \
  database vault-plugin-database-oracle
vault plugin info -version="$ORACLE_PLUGIN_VERSION" \
  database vault-plugin-database-oracle
```

Inspect the returned `command` path instead of assuming it matches the manual extraction path. Managed downloads use Vault's runtime directory. Check that binary's dependencies as the Vault OS user on the node where it is executed. Additional HA/DR nodes still require their own Oracle client libraries and release-download access.

## 4. Verify database connectivity and credential generation

Catalog registration establishes that Vault recognizes the package. A successful database configuration with `verify_connection=true` and credential generation additionally exercises loading the plugin, loading Oracle libraries, and contacting the database.

From an authenticated Bash/Vault CLI session, choose a fresh test mount and supply the existing Oracle management account. `oracle-plugin-check/` must be unused. Use the PDB service name, such as `XEPDB1`, rather than the container database service when appropriate:

```bash
set -euo pipefail
export ORACLE_HOST='<oracle-host-reachable-from-vault>'
export ORACLE_SERVICE=XEPDB1
export ORACLE_USERNAME='<oracle-management-user>'
export ORACLE_PLUGIN_VERSION=0.14.1+ent
umask 077
work=$(mktemp -d)
read -r -s -p 'Oracle management password: ' ORACLE_PASSWORD
printf '\n'
printf '%s' "$ORACLE_PASSWORD" > "$work/password"
unset ORACLE_PASSWORD

vault secrets enable -path=oracle-plugin-check database
vault write oracle-plugin-check/config/oracle \
  plugin_name=vault-plugin-database-oracle \
  plugin_version="$ORACLE_PLUGIN_VERSION" \
  connection_url="{{username}}/{{password}}@$ORACLE_HOST:1521/$ORACLE_SERVICE" \
  username="$ORACLE_USERNAME" password=@"$work/password" \
  allowed_roles=plugin-check verify_connection=true
rm "$work/password"

vault write oracle-plugin-check/roles/plugin-check \
  db_name=oracle default_ttl=5m max_ttl=10m \
  creation_statements='CREATE USER {{name}} IDENTIFIED BY "{{password}}"; GRANT CREATE SESSION TO {{name}}' \
  revocation_statements='DROP USER {{name}} CASCADE'
vault read -format=json oracle-plugin-check/creds/plugin-check > "$work/credentials.json"
```

This uses the generic `database` secrets engine with the external Oracle plugin selected on its connection. Do not attempt to enable the Oracle database plugin as a standalone secrets engine.

The successful credential read should contain a lease ID and database username/password; keep the file private. It demonstrates user creation, not an independently observed application login. Your Oracle administrator can confirm that the returned user exists or use the credentials with an Oracle client.

### Clean up the connection check

Revoke the test lease, then disable only the mount created above. Disabling that mount removes its connection and roles; the existing Oracle management account and installed plugin remain available:

```bash
vault lease revoke "$(jq -er '.lease_id' "$work/credentials.json")"
vault secrets disable oracle-plugin-check
rm -rf "$work"
```

If setup failed before credential issuance, remove the temporary mount if it was created and remove the local temporary directory after inspecting the failure. Retain the private lease details until revocation succeeds. Do not deregister a shared plugin version as part of this check's cleanup.

## Common installation problems

- `libclntsh.so.19.1: cannot open shared object file`: check Instant Client installation, parent-directory permissions, `ldconfig`, and `ldd` as the Vault OS user on the node executing the plugin.
- `permission denied`: check the service's OS identity, execute/traverse permissions, and whether the plugin filesystem is mounted `noexec`.
- `Unrecognized remote plugin message`: inspect the Vault server log for the underlying loader/startup error; verify Linux AMD64 architecture, dependencies, and `mlock` requirements.
- Registration cannot find or validate the package: compare the configured plugin directory, archive basename, selected version, and retained metadata/signature files. For managed downloads, also check the release endpoints documented in the registration prerequisites.
- Registration succeeds but the Oracle configuration fails: investigate PDB/service name, database reachability from the active Vault node, and the management account's password/privileges.
- Works until a leadership change: inspect the new active node's client libraries and plugin distribution. A catalog entry alone does not establish identical host dependencies on every node.

## Verification and references

This guide replaces the earlier broadly named Oracle reproduction with an installation-focused walkthrough. Commands were checked against the referenced documentation and statically reviewed; this revision has not been executed against an Oracle deployment.

- [Oracle plugin requirements and compatibility](https://developer.hashicorp.com/vault/docs/secrets/databases/oracle)
- [External plugin registration and package layouts](https://developer.hashicorp.com/vault/docs/plugins/register)
- [Plugin catalog API](https://developer.hashicorp.com/vault/api-docs/system/plugins-catalog)
- [Oracle database connection API](https://developer.hashicorp.com/vault/api-docs/secret/databases/oracle)
- [Database role and credential APIs](https://developer.hashicorp.com/vault/api-docs/secret/databases)
