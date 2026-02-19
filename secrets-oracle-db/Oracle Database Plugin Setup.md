# Oracle Database Plugin Reproduction

This reproduction provides a complete setup for testing Vault's Oracle Database secrets engine on an AWS EC2 instance running Amazon Linux.

## Prerequisites

- AWS EC2 instance (Amazon Linux 2 or later recommended)
- Vault Enterprise license
- Internet connectivity for downloading dependencies

## Environment Setup

### 1. Download and Install Vault

```bash
wget https://releases.hashicorp.com/vault/1.20.2+ent/vault_1.20.2+ent_linux_amd64.zip
unzip vault_1.20.2+ent_linux_amd64.zip
sudo mv vault /usr/local/bin/
vault --version
```

### 2. Install Docker and Create Oracle Container

```bash
sudo yum install -y docker
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker $(whoami)
```

**Note**: Log out and back in for group changes to take effect.

```bash
docker run -d --name oracle-db -p 1521:1521 -e ORACLE_PWD=admin container-registry.oracle.com/database/express:21.3.0-xe

# Monitor container startup (wait until "DATABASE IS READY TO USE" appears)
docker logs -f oracle-db
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
# Download Oracle SDK
wget https://download.oracle.com/otn_software/linux/instantclient/1928000/instantclient-sdk-linux.x64-19.28.0.0.0dbru.zip
unzip instantclient-sdk-linux.x64-19.28.0.0.0dbru.zip
sudo mkdir -p /opt/oracle
sudo mv instantclient_19_28 /opt/oracle/

# Configure library path
echo /opt/oracle/instantclient_19_28 | sudo tee /etc/ld.so.conf.d/oracle-instantclient.conf
sudo ldconfig
sudo dnf install -y libnsl
```

### 2. Download and Install Oracle Database Plugin

```bash
# Create plugin directory
sudo mkdir -p /etc/vault.d/plugins

# Download plugin
wget https://releases.hashicorp.com/vault-plugin-database-oracle/0.12.3+ent/vault-plugin-database-oracle_0.12.3+ent_linux_amd64.zip

# Extract to versioned folder
mkdir oracle-database-plugin_0.12.3+ent_linux_amd64
sudo unzip vault-plugin-database-oracle_0.12.3+ent_linux_amd64.zip -d oracle-database-plugin_0.12.3+ent_linux_amd64

# Move to plugins directory
sudo mv oracle-database-plugin_0.12.3+ent_linux_amd64 /etc/vault.d/plugins/

# Rename binary
sudo mv /etc/vault.d/plugins/oracle-database-plugin_0.12.3+ent_linux_amd64/vault-plugin-database-oracle \
        /etc/vault.d/plugins/oracle-database-plugin_0.12.3+ent_linux_amd64/oracle-database-plugin

# Set permissions
sudo chmod +x /etc/vault.d/plugins/oracle-database-plugin_0.12.3+ent_linux_amd64/oracle-database-plugin
sudo chown ec2-user:ec2-user -R /etc/vault.d/plugins/

# Verify dependencies
ldd /etc/vault.d/plugins/oracle-database-plugin_0.12.3+ent_linux_amd64/oracle-database-plugin
```

## Vault Configuration

### 1. Start Vault Server

```bash
export VAULT_LICENSE="<your-license-key>"
vault server -dev -dev-plugin-dir=/etc/vault.d/plugins
```

In a new terminal:

```bash
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='<your-root-token>'
```

### 2. Register Plugin and Enable Database Secrets Engine

```bash
vault secrets enable database

vault plugin register \
  -command="oracle-database-plugin" \
  -version="0.12.3+ent" \
  database \
  oracle-database-plugin
```

### 3. Create Password Policies

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

### 4. Configure Database Connections

```bash
vault write database/config/oracle-8 \
    plugin_name=oracle-database-plugin \
    allowed_roles="*" \
    password_policy=oracle-8char-nospecial \
    connection_url="vaultuser/vault@localhost:1521/XEPDB1"

vault write database/config/oracle-10 \
    plugin_name=oracle-database-plugin \
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
