# AppRole + Snowflake Database Secrets Engine Reproduction

This reproduction demonstrates how to configure the Vault database secrets engine with Snowflake, using a static role for RSA key-pair credential rotation and AppRole authentication for application access. Snowflake deprecated password-based authentication for service accounts in November 2025, making key-pair auth the standard approach.

This runbook is based on a real support case, of my colleague Harley, where a customer was experiencing issues integrating their workflow to include approle auth with snowflake secrets engine. The customer had several questions about the integration and how to use snowflake RSA key-pair authentication with Vault. This runbook will cover the setup of the snowflake secrets engine, the static role, and the approle auth. It will also cover the testing and verification of the integration.

## Prerequisites

- Running Vault cluster
- Snowflake account (trial at [signup.snowflake.com](https://signup.snowflake.com/) works)
- OpenSSL
- Vault CLI
- SnowSQL CLI (optional, for end-to-end connection verification)

## Snowflake Setup

### 1. Create a Snowflake Trial Account

Go to [signup.snowflake.com](https://signup.snowflake.com/), choose Standard Edition (free 30-day trial), and complete registration. Note your account URL:

```
https://<snowflake_account>.snowflakecomputing.com/
```

### 2. Generate RSA Key Pair for Vault

```bash
mkdir -p ~/VaultDemo
cd ~/VaultDemo

# Generate private key (.pem format required by Snowflake)
openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out vault_demo_key.pem -nocrypt

# Generate public key
openssl rsa -in vault_demo_key.pem -pubout -out vault_demo_key.pub

# Extract the public key content (strip header/footer lines)
grep -v "BEGIN PUBLIC KEY" vault_demo_key.pub | \
  grep -v "END PUBLIC KEY" | \
  tr -d '\n' && echo
```

Copy the single-line public key output — you will paste it into Snowflake in the next step.

### 3. Configure Snowflake Resources

Log into the Snowflake web UI and run the following SQL. Replace `PASTE_YOUR_PUBLIC_KEY_HERE` with the output from Step 2.

```sql
USE ROLE ACCOUNTADMIN;

-- Create Vault's service account
CREATE USER vault_demo_svc
  DEFAULT_ROLE = ACCOUNTADMIN
  MUST_CHANGE_PASSWORD = FALSE
  COMMENT = 'Vault service account with key-pair auth';

-- Add public key
ALTER USER vault_demo_svc SET RSA_PUBLIC_KEY = 'PASTE_YOUR_PUBLIC_KEY_HERE';

-- Grant admin role so Vault can manage credentials
GRANT ROLE ACCOUNTADMIN TO USER vault_demo_svc;

-- Create application role
CREATE ROLE IF NOT EXISTS demo_app_role
  COMMENT = 'Role for Vault-managed application users';

-- Create database and schema
CREATE DATABASE IF NOT EXISTS demo_vault_db;
CREATE SCHEMA IF NOT EXISTS demo_vault_db.demo_schema;

-- Create demo table
CREATE OR REPLACE TABLE demo_vault_db.demo_schema.customers (
    customer_id   INTEGER,
    customer_name VARCHAR(100),
    email         VARCHAR(100),
    created_at    TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Insert sample data
INSERT INTO demo_vault_db.demo_schema.customers (customer_id, customer_name, email) VALUES
    (1, 'Acme Corp',        'contact@acme.com'),
    (2, 'TechStart Inc',    'info@techstart.com'),
    (3, 'Global Solutions', 'hello@globalsolutions.com');

-- Grant database permissions to the application role
GRANT USAGE ON DATABASE demo_vault_db TO ROLE demo_app_role;
GRANT USAGE ON SCHEMA demo_vault_db.demo_schema TO ROLE demo_app_role;
GRANT SELECT ON ALL TABLES IN SCHEMA demo_vault_db.demo_schema TO ROLE demo_app_role;
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE demo_app_role;
GRANT ROLE demo_app_role TO ROLE ACCOUNTADMIN;

-- Create the static user Vault will manage
CREATE USER demo_app_user
  DEFAULT_ROLE = demo_app_role
  MUST_CHANGE_PASSWORD = FALSE
  COMMENT = 'Static user whose RSA key Vault will rotate';

GRANT ROLE demo_app_role TO USER demo_app_user;
```

### 4. Verify Snowflake Setup

```sql
-- Verify users were created
SHOW USERS LIKE '%demo%';

-- Verify roles
SHOW ROLES LIKE '%demo%';

-- Verify sample data
SELECT * FROM demo_vault_db.demo_schema.customers;

-- Verify grants
SHOW GRANTS TO ROLE demo_app_role;
SHOW GRANTS TO USER demo_app_user;

-- Verify vault_demo_svc has the RSA public key set
DESC USER vault_demo_svc;
```

## Vault Setup

## Configure the Database Secrets Engine

### 1. Enable the Secrets Engine

Open a terminal to Vault:

```bash
vault secrets enable database
```

### 2. Configure the Snowflake Connection

Replace `<snowflake_account>` with your Snowflake account identifier from Step 1 of the Snowflake setup.

```bash
vault write database/config/snowflake-demo \
    plugin_name=snowflake-database-plugin \
    connection_url="<snowflake_account>.snowflakecomputing.com/demo_vault_db" \
    username="vault_demo_svc" \
    password="$(cat vault_demo_key.pem)" \
    allowed_roles="demo-static-role"
```

Verify the configuration:

```bash
vault read database/config/snowflake-demo
```

### 3. Create a Static Role with RSA Key-Pair Rotation

```bash
vault write database/static-roles/demo-static-role \
    db_name=snowflake-demo \
    username="demo_app_user" \
    rotation_period="24h" \
    rotation_statements="ALTER USER {{name}} SET RSA_PUBLIC_KEY='{{public_key}}'" \
    credential_type="rsa_private_key" \
    credential_config=key_bits=2048
```

Verify the static role:

```bash
vault read database/static-roles/demo-static-role
```

### 4. Force Initial Rotation

```bash
vault write -f database/rotate-role/demo-static-role

vault read database/static-creds/demo-static-role
```

Example output:

```
Key                    Value
---                    -----
last_vault_rotation    2025-11-01T10:00:00.000000000Z
rotation_period        24h
ttl                    23h59m59s
username               demo_app_user
rsa_private_key        -----BEGIN PRIVATE KEY-----
                       ...
                       -----END PRIVATE KEY-----
```

## Configure AppRole Authentication

### 1. Create a Policy for Database Access

```bash
vault policy write demo-snowflake-policy - <<EOF
path "database/static-creds/demo-static-role" {
  capabilities = ["read"]
}
EOF
```

Verify the policy:

```bash
vault policy read demo-snowflake-policy
```

### 2. Enable AppRole Auth

```bash
vault auth enable approle
```

### 3. Create the AppRole

```bash
vault write auth/approle/role/demo-snowflake-app \
    token_policies="demo-snowflake-policy" \
    token_ttl=1h \
    token_max_ttl=4h \
    secret_id_ttl=24h \
    secret_id_num_uses=0 \
    bind_secret_id=true
```

Verify the role configuration:

```bash
vault read auth/approle/role/demo-snowflake-app
```

### 4. Retrieve Role ID and Secret ID

```bash
# Role ID is not sensitive and can be distributed broadly
vault read -field=role_id auth/approle/role/demo-snowflake-app/role-id > role_id.txt
cat role_id.txt

# Secret ID is sensitive — treat like a password
vault write -field=secret_id -f auth/approle/role/demo-snowflake-app/secret-id > secret_id.txt
cat secret_id.txt
```

## Testing and Verification

### 1. Verify Credential Rotation

```bash
echo "=== Before Rotation ==="
vault read database/static-creds/demo-static-role | grep last_vault_rotation

vault write -f database/rotate-role/demo-static-role

echo "=== After Rotation ==="
vault read database/static-creds/demo-static-role | grep last_vault_rotation
```

The `last_vault_rotation` timestamp should change between the two reads, confirming Vault can rotate Snowflake RSA credentials.

### 2. Test AppRole Authentication

```bash
ROLE_ID=$(cat role_id.txt)
SECRET_ID=$(cat secret_id.txt)

APP_TOKEN=$(vault write -field=token auth/approle/login \
    role_id="$ROLE_ID" \
    secret_id="$SECRET_ID")

echo "Token: ${APP_TOKEN:0:20}..."
```

### 3. Retrieve Snowflake Credentials via AppRole Token

```bash
ROLE_ID=$(cat role_id.txt)
SECRET_ID=$(cat secret_id.txt)

APP_TOKEN=$(vault write -field=token auth/approle/login \
    role_id="$ROLE_ID" \
    secret_id="$SECRET_ID")

VAULT_TOKEN=$APP_TOKEN vault read database/static-creds/demo-static-role
```

Expected output returns `username` and `rsa_private_key`.

### 4. Test Snowflake Connection with SnowSQL (Optional)

```bash
ROLE_ID=$(cat role_id.txt)
SECRET_ID=$(cat secret_id.txt)

APP_TOKEN=$(vault write -field=token auth/approle/login \
    role_id="$ROLE_ID" \
    secret_id="$SECRET_ID")

# Save private key from Vault to a temp file
VAULT_TOKEN=$APP_TOKEN vault read -field=rsa_private_key \
    database/static-creds/demo-static-role > temp_key.pem

# Convert to PKCS#8 format required by SnowSQL
openssl pkcs8 -topk8 -inform PEM -outform PEM \
    -in temp_key.pem \
    -out demo_app_private_key.pem \
    -nocrypt

chmod 600 demo_app_private_key.pem
rm temp_key.pem

# Get username from the same static cred path
USERNAME=$(VAULT_TOKEN=$APP_TOKEN vault read -field=username \
    database/static-creds/demo-static-role)

# Connect and query — replace <snowflake_account> with your account identifier
snowsql -a <snowflake_account> \
  -u "$USERNAME" \
  --private-key-path demo_app_private_key.pem \
  -d demo_vault_db \
  -s demo_schema \
  -w COMPUTE_WH \
  -q "SELECT * FROM customers;"
```

Expected output:

```
+-------------+-------------------+---------------------------+
| CUSTOMER_ID | CUSTOMER_NAME     | EMAIL                     |
+-------------+-------------------+---------------------------+
|           1 | Acme Corp         | contact@acme.com          |
|           2 | TechStart Inc     | info@techstart.com        |
|           3 | Global Solutions  | hello@globalsolutions.com |
+-------------+-------------------+---------------------------+
3 Row(s) produced.
```

## Cleanup

```bash
# Disable secrets engine and auth method
vault secrets disable database
vault auth disable approle

# Remove policy
vault policy delete demo-snowflake-policy

# Remove local key files
rm -f ~/VaultDemo/vault_demo_key.pem \
      ~/VaultDemo/vault_demo_key.pub \
      ~/VaultDemo/role_id.txt \
      ~/VaultDemo/secret_id.txt \
      ~/VaultDemo/demo_app_private_key.pem
```

In Snowflake, drop the demo resources if no longer needed:

```sql
USE ROLE ACCOUNTADMIN;
DROP USER IF EXISTS demo_app_user;
DROP USER IF EXISTS vault_demo_svc;
DROP ROLE IF EXISTS demo_app_role;
DROP DATABASE IF EXISTS demo_vault_db;
```

## Notes

- Snowflake deprecated username/password authentication for programmatic access in November 2025. RSA key-pair authentication (`credential_type=rsa_private_key`) is the supported approach for Vault-managed service accounts.
- The `rotation_statements` template uses `{{public_key}}` which Vault substitutes with the newly generated RSA public key at rotation time. The corresponding private key is returned via `database/static-creds/<role>`.
- The dev server (`vault server -dev`) is not suitable for production. Use it only for local testing.
- `secret_id_num_uses=0` means the Secret ID has unlimited uses within its TTL. Tighten this for production AppRole configurations.

## References

- [Snowflake Database Secrets Engine](https://developer.hashicorp.com/vault/docs/secrets/databases/snowflake)
- [Snowflake Database Plugin](https://github.com/hashicorp/vault-plugin-database-snowflake)
- [Snowflake Database API](https://developer.hashicorp.com/vault/api-docs/secret/databases/snowflake)
- [Snowflake CLI](https://docs.snowflake.com/en/developer-guide/snowflake-cli/index)