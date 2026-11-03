# Oracle Database Secrets Engine Reproduction

This reproduction provides a complete setup for testing Vault's Oracle Database secrets engine on an AWS EC2 instance running Amazon Linux.

## Prerequisites

- AWS EC2 instance (Amazon Linux 2023 or later recommended)
  - Instance Type: t2.medium or larger (for better performance with Oracle and Vault)
  - Storage: At least 30GB EBS volume 
- Vault Enterprise license
- Internet connectivity for downloading dependencies

## Environment Setup

### 1. Download and Install Vault

You can also add this step to the startup script for the EC2 instance to automate the setup process ([AWS docs](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html)).

```bash
#!/bin/bash

export VAULT_LICENSE="<your-license-key>"
export VAULT_VERSION="1.20.2+ent"
export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="root"

# Persist environment variables for ec2-user SSH sessions
echo "export VAULT_ADDR=http://127.0.0.1:8200" >> /home/ec2-user/.bashrc
echo "export VAULT_TOKEN=root" >> /home/ec2-user/.bashrc

wget https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip
unzip vault_${VAULT_VERSION}_linux_amd64.zip
sudo mv vault /usr/local/bin/
vault --version

# Create plugin directory before starting Vault
sudo mkdir -p /etc/vault.d/plugins

# Use -E to preserve VAULT_LICENSE in the sudo environment
sudo -E vault server -dev -dev-root-token-id="root" -dev-plugin-dir=/etc/vault.d/plugins > /var/log/vault.log 2>&1 &

until VAULT_ADDR=http://127.0.0.1:8200 vault status > /dev/null 2>&1; do sleep 1; done
```

### 2. Install Docker and Create Oracle Container

Start here if you already have a running Vault server with `plugin_directory` configured.

```bash
sudo dnf install -y docker
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker $(whoami)
```

**Note**: Log out and back in for group changes to take effect.

```bash
sudo docker run -d --name oracle-db -p 1521:1521 -e ORACLE_PWD=admin container-registry.oracle.com/database/express:21.3.0-xe

# Monitor container startup (wait until "DATABASE IS READY TO USE" appears)
docker logs -f oracle-db

# Check status of the container
docker ps --filter "name=oracle-db"
```

### 3. Configure Oracle Database User

```bash
docker exec -it oracle-db sqlplus sys as sysdba
```

Enter password: `admin`

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

## Oracle Plugin Installation

### 1. Install Oracle Instant Client Dependencies

```bash
# Download Oracle Instant Client Basic (provides libclntsh.so.19.1 runtime library)
wget https://download.oracle.com/otn_software/linux/instantclient/1928000/instantclient-basic-linux.x64-19.28.0.0.0dbru.zip
unzip instantclient-basic-linux.x64-19.28.0.0.0dbru.zip
sudo mkdir -p /opt/oracle
sudo mv instantclient_19_28 /opt/oracle/

# Download Oracle SDK (provides header files; extract into the same directory)
wget https://download.oracle.com/otn_software/linux/instantclient/1928000/instantclient-sdk-linux.x64-19.28.0.0.0dbru.zip
sudo unzip instantclient-sdk-linux.x64-19.28.0.0.0dbru.zip -d /opt/oracle/

# Configure library path
echo /opt/oracle/instantclient_19_28 | sudo tee /etc/ld.so.conf.d/oracle-instantclient.conf
sudo ldconfig
sudo dnf install -y libaio libnsl
```

The Oracle Instant Client is still required even when Vault downloads the plugin binary for you with `-download=true`.

### 2. Prepare the Vault Plugin Directory

In the Vault config, there is a `plugin_directory` option that specifies where Vault looks for plugin binaries. Please view this [before you start](https://developer.hashicorp.com/vault/docs/plugins/register#before-you-start) section of the external plugin documentation for more details on how to get started.

This reproduction uses the plugin directory `/etc/vault.d/plugins`, which was already configured when the Vault dev server was started above.

```bash
sudo mkdir -p /etc/vault.d/plugins
sudo chmod 755 /etc/vault.d/plugins
```

## Vault Configuration

### 1. Enable the Database Secrets Engine and Register the Plugin

For Vault 1.20.x and newer, the easier path is to let Vault download the plugin from `releases.hashicorp.com`. The user that runs the Vault service must have permission to write to the plugin directory because Vault downloads and extracts the binary there.

```bash
vault secrets enable database

vault plugin register \
  -version="0.12.3+ent" \
  -download=true \
  database \
  vault-plugin-database-oracle
```

To verify plugin registration details:

```bash
vault plugin info -version="0.12.3+ent" database vault-plugin-database-oracle
```

Example output:

```text
Key                   Value
---                   -----
args                  []
builtin               false
command               .runtime/vault-plugin-database-oracle_0.12.3+ent_linux_amd64/vault-plugin-database-oracle
deprecation_status    n/a
name                  vault-plugin-database-oracle
oci_image             n/a
runtime               n/a
sha256                eef0864b88e6bf99044fb44b15905604d6f04a6289029bb4d2ed91de8da5f776
version               v0.12.3+ent
```

To verify the plugin binary and its Oracle client dependencies after the download step:

```bash
sudo ldd /etc/vault.d/plugins/.runtime/vault-plugin-database-oracle_0.12.3+ent_linux_amd64/vault-plugin-database-oracle
```

To deregister the plugin:

```bash
vault plugin deregister \
  -version="0.12.3+ent" \
  database \
  vault-plugin-database-oracle
```

When you use `-download=true` flag, the plugin is replicated to a DR secondary and will be present after a DR promotion or failover. This does not replace host-level prerequisites on the DR node, so make sure the Oracle Instant Client libraries and any required OS packages are installed there as well.


### 2. Create Password Policies

```bash
mkdir -p vault
cd vault

cat > oracle-8char-nospecial.hcl <<EOF
length = 8
rule "charset" {
  charset = "abcdefghijklmnopqrstuvwxyz"
  min-chars = 1
}
rule "charset" {
  charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  min-chars = 1
}
rule "charset" {
  charset = "0123456789"
  min-chars = 1
}
EOF

cat > oracle-10char-nospecial.hcl <<EOF
length = 10
rule "charset" {
  charset = "abcdefghijklmnopqrstuvwxyz"
  min-chars = 1
}
rule "charset" {
  charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  min-chars = 1
}
rule "charset" {
  charset = "0123456789"
  min-chars = 1
}
EOF

vault write sys/policies/password/oracle-8char-nospecial policy=@oracle-8char-nospecial.hcl
vault write sys/policies/password/oracle-10char-nospecial policy=@oracle-10char-nospecial.hcl
vault list sys/policies/password
```

### 3. Configure Database Connections

```bash
vault write database/config/oracle-8 \
  plugin_name=vault-plugin-database-oracle \
  allowed_roles="*" \
  password_policy=oracle-8char-nospecial \
  connection_url="vaultuser/vault@localhost:1521/XEPDB1"

vault write database/config/oracle-10 \
  plugin_name=vault-plugin-database-oracle \
  allowed_roles="*" \
  password_policy=oracle-10char-nospecial \
  connection_url="vaultuser/vault@localhost:1521/XEPDB1"
```

## Testing Dynamic Credentials

### Create Dynamic Roles

```bash
vault write database/roles/8 \
  db_name=oracle-8 \
  password_policy="oracle-8char-nospecial" \
  creation_statements='CREATE USER {{username}} IDENTIFIED BY "{{password}}"; GRANT CONNECT TO {{username}}; GRANT CREATE SESSION TO {{username}};' \
  default_ttl="1h" \
  max_ttl="24h"

vault write database/roles/10 \
  db_name=oracle-10 \
  password_policy="oracle-10char-nospecial" \
  creation_statements='CREATE USER {{username}} IDENTIFIED BY "{{password}}"; GRANT CONNECT TO {{username}}; GRANT CREATE SESSION TO {{username}};' \
  default_ttl="1h" \
  max_ttl="24h"
```

### Generate Credentials

```bash
vault read database/creds/8
vault read database/creds/10
```

## Testing Static Credentials

### Create Static Users in Oracle

```bash
docker exec -it oracle-db sqlplus sys as sysdba
```

Enter password: `admin`

```sql
ALTER SESSION SET CONTAINER = XEPDB1;
CREATE USER user8 IDENTIFIED BY "TempPassword8";
GRANT CONNECT TO user8;
GRANT CREATE SESSION TO user8;

CREATE USER user10 IDENTIFIED BY "TempPassword10";
GRANT CONNECT TO user10;
GRANT CREATE SESSION TO user10;
exit;
```

### Create Static Roles

```bash
vault write database/static-roles/8-static \
  db_name=oracle-8 \
  username=user8 \
  password_policy="oracle-8char-nospecial" \
  rotation_statements='ALTER USER {{name}} IDENTIFIED BY "{{password}}" ACCOUNT UNLOCK' \
  rotation_period="24h"

vault write database/static-roles/10-static \
  db_name=oracle-10 \
  username=user10 \
  password_policy="oracle-10char-nospecial" \
  rotation_statements='ALTER USER {{name}} IDENTIFIED BY "{{password}}" ACCOUNT UNLOCK' \
  rotation_period="24h"
```

### Retrieve Static Credentials

```bash
vault read database/static-creds/8-static
vault read database/static-creds/10-static
```

## Verification

You can verify the credentials work by connecting to Oracle:

```bash
docker exec -it oracle-db sqlplus <username>/<password>@XEPDB1
```

## Cleanup

```bash
# Stop and remove Oracle container
docker stop oracle-db
docker rm oracle-db

# Stop Vault server (Ctrl+C in the server terminal)
```

## Notes

- This setup uses Oracle Express Edition 21c in a Docker container for quick testing
- The vaultuser has DBA privileges for demonstration purposes
- Password policies are configured without special characters to comply with Oracle password requirements
- Two configurations are provided to test different password lengths (8 and 10 characters)
- Static roles require pre-existing users in the Oracle database

## Appendix: Manual Plugin Installation Details

If you are using a Vault version older than 1.20.x, or if you want to manage the plugin binary yourself instead of using `-download=true`, use the manual flow below.

The published plugin name on `releases.hashicorp.com` is `vault-plugin-database-oracle`. In the manual example below, the extracted binary is renamed to `oracle-database-plugin` for simplicity, and the same name is then used in the `vault plugin register -command=...` step.

### 1. Download and Install the Plugin Manually

```bash
PLUGIN_VERSION="0.14.1+ent"
PLUGIN_ARCHIVE="vault-plugin-database-oracle_${PLUGIN_VERSION}_linux_amd64"
PLUGIN_DIR="/etc/vault.d/plugins"

# Create plugin directory and download
sudo mkdir -p "${PLUGIN_DIR}"
wget "https://releases.hashicorp.com/vault-plugin-database-oracle/${PLUGIN_VERSION}/${PLUGIN_ARCHIVE}.zip"

# Extract directly to plugins directory
sudo unzip "${PLUGIN_ARCHIVE}.zip" -d "${PLUGIN_DIR}/${PLUGIN_ARCHIVE}"

# Set permissions
sudo chmod +x "${PLUGIN_DIR}/${PLUGIN_ARCHIVE}/vault-plugin-database-oracle"
sudo chown -R vault:vault "${PLUGIN_DIR}"
```

To verify the plugin binary and its dependencies are correctly installed:

```bash
ldd "${PLUGIN_DIR}/${PLUGIN_ARCHIVE}/vault-plugin-database-oracle"
```

### 2. Register the Manually Installed Plugin

```bash
vault plugin register \
  -command="vault-plugin-database-oracle" \
  -version="0.12.3+ent" \
  database \
  vault-plugin-database-oracle
```

If you use the manual registration path above, update the database connection configuration to use `plugin_name=oracle-database-plugin` instead of `plugin_name=vault-plugin-database-oracle`.

For non-Enterprise plugins, you can register the plugin with the SHA256 checksum. This is the typical flow when the plugin binary is managed locally in the plugin directory.

```bash
SHA=$(sha256sum /path/to/plugin | awk '{print $1}')

vault plugin register \
  -sha256="$SHA" \
  database \
  oracle-database-plugin
```

## References

- [AWS EC2 user data](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html)
- [Vault external plugin registration](https://developer.hashicorp.com/vault/docs/plugins/register)
- [Vault external plugin registration prerequisites](https://developer.hashicorp.com/vault/docs/plugins/register#before-you-start)
- [Vault database secrets engine](https://developer.hashicorp.com/vault/docs/secrets/databases)
- [Vault Oracle database secrets engine](https://developer.hashicorp.com/vault/docs/secrets/databases/oracle)
- [Vault database secrets engine API](https://developer.hashicorp.com/vault/api-docs/secret/databases)
- [Vault Oracle database API](https://developer.hashicorp.com/vault/api-docs/secret/databases/oracle)
- [Vault plugin management for enterprise plugins](https://developer.hashicorp.com/vault/docs/plugins/plugin-management#enterprise-plugins)
- [Oracle database plugin releases](https://releases.hashicorp.com/vault-plugin-database-oracle)
- [Oracle database plugin source repository](https://github.com/hashicorp/vault-plugin-database-oracle)
- [Vault plugins register/read/update API docs](https://developer.hashicorp.com/vault/api-docs/system/plugins-catalog)