# PostgreSQL Static Role Denial-of-Service Repro

## Overview

Vault's static roles feature can trigger a resource exhaustion event (DoS) when external databases are decommissioned without removing the corresponding roles in Vault.

### Scope

- Symptoms: High IOPS, high CPU, massive error logs, degraded API responsiveness on primary; potential spillover impact on standbys and performance secondaries.
- Root Cause Pattern: Stale static roles with rotation schedules tied to database connections that no longer exist (or are not reachable).
- Components: Vault database secrets engine plugins (e.g., `postgresql-database-plugin`, `mongodb-database-plugin`).

### Resource Exhaustion

- Disk I/O: Logging writes can exceed 250MB/s, saturating disk throughput.
- CPU: Thousands of requests/commands to write to log file can saturate CPU.
- DoS: The Vault cluster can become unresponsive due to IOPS saturation.

During an incident for a large enterprise customer, two database secrets engines (PostgreSQL and MongoDB) contained thousands of stale static roles tied to decommissioned databases. With rotation schedules still active, Vault produced about 32,000 errors per hour, including:

### DNS-related errors

- `FATAL: no pg_hba.conf entry for host "...", user "...", database "..."`
- `hostname resolving error (lookup ...postgres.database.azure.com on 127.0.0.1 no such host)`
- `ERROR: permission denied (SQLSTATE 42501)`
- `failed to find entry for connection with name: "...postgres.database.azure.com-..."`

### Static role-related errors

- `expected role to have WAL, but WAL not found in storage` [1]
- `unable to rotate credentials in periodic function`

## Reproduction

Use this procedure to demonstrate the failure in a sandbox environment (e.g., AWS t2.micro instance). Before running the script, make sure you are running as `sudo`.

```bash
#!/bin/bash
set -e
# CONFIGURATION
VAULT_VERSION="1.19.6+ent"
# Export your actual license key before running, or replace below
export VAULT_LICENSE="your-license-here"

# 1. INSTALL VAULT & DOCKER
yum install -y docker unzip wget
wget -q https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip
unzip -o vault_${VAULT_VERSION}_linux_amd64.zip
mv vault /usr/bin/vault; chmod +x /usr/bin/vault
service docker start

# 2. START POSTGRES
docker rm -f postgres-db || true
docker run -d --name postgres-db -p 5432:5432 \
  -e POSTGRES_USER=root -e POSTGRES_PASSWORD=rootpassword -e POSTGRES_DB=vault_tests \
  postgres:15-alpine
sleep 10

# 3. START VAULT
pkill vault || true
nohup vault server -dev -dev-root-token-id="root" -dev-listen-address="0.0.0.0:8200" > /var/log/vault.log 2>&1 &
sleep 5
export VAULT_ADDR="http://127.0.0.1:8200"

# 4. CONFIGURE 1000 ROLES (Aggressive 5s Rotation)
vault secrets enable database
vault write database/config/postgres-target \
    plugin_name=postgresql-database-plugin \
    allowed_roles="*" \
    connection_url="postgresql://{{username}}:{{password}}@127.0.0.1:5432/vault_tests?sslmode=disable" \
    username="root" password="rootpassword"

# Create users in Postgres
for i in {1..1000}; do echo "CREATE USER user_$i WITH PASSWORD 'init';" >> users.sql; done
cat users.sql | docker exec -i postgres-db psql -U root -d vault_tests
rm -f users.sql

# Create roles in Vault
echo "Creating 1,000 roles with 5s rotation..."
for i in {1..1000}; do
   vault write database/static-roles/static-role-$i \
       db_name=postgres-target username=user_$i rotation_period=5s > /dev/null
done

# 5. Stop the Docker Container
docker stop postgres-db

echo "Lab Ready."
```

This script creates 1,000 users on a PostgreSQL database and the corresponding static roles in Vault. After these users are created, the PostgreSQL Docker container is stopped.

You can monitor node metrics and observe spikes in CPU, memory, and disk usage with `top` or `htop`:

```bash
# Install htop if missing
yum install -y htop
htop
```

Observe the immediate spike in CPU and the flood of logs in `/var/log/vault.log`.

## Recovery

When on a call with a customer facing this, prioritize cleaning up some database roles to free up disk IOPS so the cluster can recover. Without addressing high IOPS, the customer's cluster will continue to be unhealthy and will likely impact standby nodes in the primary cluster and performance secondary clusters.

1. Disable entire database mounts (if possible).
2. Clean up the static roles manually.

## Summary and Learnings

Static roles in Vault are designed to be a 1:1 association with a database user. If a rotation fails several times in a row (e.g., 7 days in a row), Vault does not account for this and will continue to attempt to rotate the password for this account indefinitely. This can be common in large enterprise environments where the database team and Vault team are disjointed and do not work in tandem when decommissioning databases.

### Key Takeaways for Customers

- Lifecycle Management: Vault configuration is not automatically coupled to the database lifecycle. Decommissioning a database must include removing the Vault role in the customer's IaC/Terraform pipelines.
- Monitoring: Alert on `WAL not found` and high occurrences of `context deadline exceeded` in Vault logs.

## References

1. [Expected role to have WAL but WAL not found in storage](https://support.hashicorp.com/hc/en-us/articles/40972195128339-ERROR-Expected-role-to-have-WAL-but-WAL-not-found-in-storage)