# PostgreSQL Database Secrets Engine Reproduction

This reproduction covers the Vault database secrets engine with PostgreSQL, including dynamic credential generation, static role rotation, and custom password policy configuration.

## Prerequisites

- Docker
- Vault CLI
- `psql` client (optional, for manual credential verification)
- `kubectl` configured to your existing cluster

## Environment Setup

### 1. Hostname Expectations

For this setup, PostgreSQL runs in Docker on your host (`0.0.0.0:5432`):

- Vault (running in Kubernetes) connects to `host.minikube.internal`
- Host-side `psql` commands connect to `localhost`

### 2. Start a PostgreSQL Container

```bash
docker run -d \
  --name postgres-vault \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=vaultdb \
  -p 5432:5432 \
  postgres:16
```

Verify it's running:

```bash
docker ps | grep postgres
2d818025a41d   postgres:16                           "docker-entrypoint.s…"   About a minute ago   Up About a minute   0.0.0.0:5432->5432/tcp                                                                                                                 postgres-vault
```

Verify the container is healthy:

```bash
docker exec -it postgres-vault psql -U postgres -c "SELECT version();"
```

Example output:
```
                                                          version
----------------------------------------------------------------------------------------------------------------------------
 PostgreSQL 16.13 (Debian 16.13-1.pgdg13+1) on aarch64-unknown-linux-gnu, compiled by gcc (Debian 14.2.0-19) 14.2.0, 64-bit
```

### 3. Create the Vault Service Account

Vault needs a dedicated account with enough privileges to create and manage database users.

```bash
docker exec -it postgres-vault psql -U postgres
```

```sql
CREATE ROLE vaultuser WITH LOGIN PASSWORD 'vaultpass';
GRANT CONNECT ON DATABASE vaultdb TO vaultuser;

-- Grants needed for dynamic credential creation
GRANT pg_monitor TO vaultuser;

-- Allow vaultuser to create and drop roles
ALTER ROLE vaultuser CREATEROLE;
\q
```

### 4. Connect to Vault Pod

```bash
k exec -n vault vault-0 -ti -- sh
```

## Configure the Database Secrets Engine

### 1. Enable the Secrets Engine

```bash
vault secrets enable database
```

### 2. Create a Password Policy (Optional)

This policy generates a 20-character alphanumeric password, which avoids special characters that can cause issues in some PostgreSQL connection string parsers.

```bash
cat > pg-password-policy.hcl <<EOF
length = 20
rule "charset" {
  charset = "abcdefghijklmnopqrstuvwxyz"
  min-chars = 2
}
rule "charset" {
  charset = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  min-chars = 2
}
rule "charset" {
  charset = "0123456789"
  min-chars = 2
}
EOF

vault write sys/policies/password/pg-alphanumeric policy=@pg-password-policy.hcl
vault list sys/policies/password
```

### 3. Configure the Database Connection

```bash
vault write database/config/postgres \
  plugin_name=postgresql-database-plugin \
  allowed_roles="*" \
  password_policy="pg-alphanumeric" \
  connection_url="postgresql://{{username}}:{{password}}@host.minikube.internal:5432/vaultdb?sslmode=disable" \
  username="vaultuser" \
  password="vaultpass"
```

Verify the connection is healthy:

```bash
vault read database/config/postgres
```

## Testing Dynamic Credentials

Dynamic credentials are short-lived users created on demand. Vault creates the user when a credential is requested and drops it after the TTL expires.

### 1. Create a Dynamic Role

```bash
vault write database/roles/pg-readonly \
  db_name=postgres \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT CONNECT ON DATABASE vaultdb TO \"{{name}}\";" \
  revocation_statements="DROP ROLE IF EXISTS \"{{name}}\";" \
  default_ttl="1h" \
  max_ttl="24h"
```

### 2. Generate Credentials

```bash
vault read database/creds/pg-readonly
```

Example output:

```
Key                Value
---                -----
lease_id           database/creds/pg-readonly/z4rLoKKMwgpUtz7lIp3chfsd
lease_duration     1h
lease_renewable    true
password           Z1BePFGAuVX3Porrwhjl
username           v-root-pg-reado-ZSheepki1oN5Q11C14r6-1772550263
```

### 3. Verify the Credentials Work
Make sure to replace `<username>` and `<password>` with the values from the Vault output.

```bash
docker exec -it postgres-vault psql "postgresql://<username>:<password>@localhost:5432/vaultdb?sslmode=disable" -c "SELECT current_user;"
```

Exmaple output:
```
                  current_user
-------------------------------------------------
 v-root-pg-reado-ZSheepki1oN5Q11C14r6-1772550263
```

### 4. Revoke the Lease Early

```bash
vault lease revoke database/creds/pg-readonly/<lease-id>
```

Attempting to connect with those credentials after revocation should fail.

Example output:
```
FATAL:  role "v-root-pg-reado-ZSheepki1oN5Q11C14r6-1772550263" does not exist
```

## Testing Static Credentials

Static roles map Vault to a pre-existing PostgreSQL user and rotate its password on a schedule.

### 1. Create a Static User in PostgreSQL

```bash
docker exec -it postgres-vault psql -U postgres
```

```sql
CREATE ROLE staticuser WITH LOGIN PASSWORD 'initialpassword';
GRANT CONNECT ON DATABASE vaultdb TO staticuser;
\q
```

### 2. Create the Static Role in Vault

```bash
vault write database/static-roles/pg-static \
  db_name=postgres \
  username=staticuser \
  password_policy="pg-alphanumeric" \
  rotation_statements="ALTER ROLE \"{{name}}\" WITH PASSWORD '{{password}}';" \
  rotation_period="1h"
```

### 3. Retrieve Static Credentials

```bash
vault read database/static-creds/pg-static
```

Look for:
- `ttl` — time remaining before the next automatic rotation
- `last_vault_rotation` — when Vault last rotated the password
- `rotation_period` — the configured interval

### 4. Trigger Manual Rotation

```bash
vault write -f database/rotate-role/pg-static
vault read database/static-creds/pg-static
```

The `last_vault_rotation` timestamp should update and the password should change.

## Verification Checklist

- Dynamic credentials are created successfully and expire after the TTL
- Static credentials persist across reads and rotate on schedule
- Manual rotation updates `last_vault_rotation`
- Revoking a dynamic lease drops the PostgreSQL role

### Confirm PostgreSQL Users Exist During Credential Lifetime

```bash
docker exec -it postgres-vault psql -U postgres -c "\du"
```

Dynamic users created by Vault will appear here while the lease is active and disappear after revocation or TTL expiry.

## Troubleshooting

### Connection Refused

Make sure the PostgreSQL container is running and port `5432` is exposed:

```bash
docker ps | grep postgres-vault
```

### Permission Denied During User Creation

The `vaultuser` role must have `CREATEROLE` and appropriate privileges. Reconnect and re-run:

```bash
docker exec -it postgres-vault psql -U postgres -c "ALTER ROLE vaultuser CREATEROLE;"
```

### Vault Cannot Reach PostgreSQL

With PostgreSQL published as `0.0.0.0:5432`, use `host.minikube.internal` for Vault's `connection_url` and `localhost` for host-side `psql` checks:

```bash
docker ps | grep postgres-vault
kubectl -n vault exec vault-0 -- sh -c 'getent hosts host.minikube.internal || nslookup host.minikube.internal || ping -c 1 host.minikube.internal'
```

### Dynamic User Still Exists After TTL Expiry

Vault revokes leases lazily. Force a revocation check:

```bash
vault lease revoke -force -prefix database/creds/pg-readonly/
```

## Cleanup

```bash
# Stop and remove PostgreSQL container
docker stop postgres-vault
docker rm postgres-vault

# Disable the secrets engine (will delete all roles and credentials)
vault secrets disable database
```

## Notes

- This setup uses `sslmode=disable` for local cluster testing. Production environments should use `sslmode=require` or `verify-full`.
- The `vaultuser` account should follow least-privilege principles in production. Avoid `CREATEROLE` if not needed.
- The password policy is configured without special characters to prevent connection string parsing issues. Adjust as needed.
- Static roles require that the user already exists in PostgreSQL before the role is created in Vault.
