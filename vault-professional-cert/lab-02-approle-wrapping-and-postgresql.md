## Lab 2: AppRole, Response Wrapping, and PostgreSQL Database Secrets

This lab contains **two distinct scenarios**:

- **Part 1**: Configure **AppRole auth** and use **response wrapping** to generate and safely deliver a `secret_id`, saving the wrapped output to JSON.
- **Part 2**: Configure the **PostgreSQL database secrets engine** for dynamic credentials, including root rotation and role-based credential generation.

---

### 0. Assumptions and Lab Setup

- **Vault** is already running and unsealed.
- You have a privileged token exported as `VAULT_TOKEN` with permissions to:
  - Enable auth methods
  - Write policies
  - Configure the database secrets engine
- You have access to a **PostgreSQL instance** compatible with the baseline in `secrets-postgresql-db/postgresql-database-secrets-engine-repro.md`, for example:
  - PostgreSQL in Docker (`postgres-vault`) listening on `0.0.0.0:5432`
  - Vault can reach it via `host.minikube.internal:5432` (or equivalent)
- `vault` CLI is installed and `VAULT_ADDR` is set.
- `jq` is available for JSON parsing.

> Adjust hostnames, ports, and credentials as needed for your environment, but keep the **shape** of commands and JSON output consistent with this lab for grading.

---

### 1. Part 1: AppRole and Response Wrapping

Goal: Enable AppRole and create a role that can be used with **response wrapping** to safely deliver a `secret_id` and save the wrapped output to a JSON file.

1. **Enable the AppRole auth method**:

   ```bash
   vault auth enable approle
   vault auth list
   ```

2. **Create a simple AppRole policy** (e.g., `approle-demo`) It exists just to demonstrate that the role can have policies attached:

   ```bash
    cat > approle-demo.hcl <<EOF
    path "secret/data/approle-demo" {
      capabilities = ["read", "list"]
    }
    EOF

    vault policy write approle-demo approle-demo.hcl
    vault policy read approle-demo
   ```

3. **Create the AppRole** bound to this policy:

   ```bash
   vault write auth/approle/role/app-db-role \
     token_policies="approle-demo" \
     token_ttl="1h" \
     token_max_ttl="4h" \
     secret_id_num_uses=1 \
     secret_id_ttl="1h"
   ```

4. **Fetch and persist the `role_id` to JSON**:

   ```bash
   vault read -format=json auth/approle/role/app-db-role/role-id \
     > approle-role-id.json

   cat approle-role-id.json | jq -r '.data.role_id'
   ```

   Keep `approle-role-id.json` for grading.

---

### 2. Generate a Wrapped `secret_id` and Persist JSON

Goal: Use **response wrapping** with `-wrap-ttl` and persist the **wrapped** result to JSON. You will later unwrap it as part of the AppRole login flow.

1. **Generate a wrapped `secret_id`**:

   ```bash
   vault write -f -wrap-ttl=5m -format=json \
     auth/approle/role/app-db-role/secret-id \
     > approle-secret-id-wrapped.json
   ```

2. **Inspect the wrapped response**:

   ```bash
   cat approle-secret-id-wrapped.json | jq
   ```

   Confirm that:
   - The **actual `secret_id` is not visible**.
   - A `wrap_info` block exists with fields like `token`, `ttl`, and `creation_time`.

3. **(Optional but recommended) Validate wrapped token one-time use**:

   ```bash
   WRAP_TOKEN=$(jq -r '.wrap_info.token' approle-secret-id-wrapped.json)

   # First unwrap: should succeed and reveal the secret_id
   VAULT_TOKEN="$WRAP_TOKEN" vault unwrap -format=json \
     > approle-secret-id-unwrapped.json

   cat approle-secret-id-unwrapped.json | jq

   # Second unwrap: should fail
   VAULT_TOKEN="$WRAP_TOKEN" vault unwrap
   ```

   Expected:
   - First unwrap produces `.data.secret_id`.
   - Second unwrap returns an error: wrapping token is invalid or already used.

4. **Files for grading so far**:

   - `approle-role-id.json`
   - `approle-secret-id-wrapped.json`
   - (Optional) `approle-secret-id-unwrapped.json`

---

### 3. Part 2: Configure the PostgreSQL Database Secrets Engine

Goal: Configure Vault to talk to PostgreSQL and prepare for dynamic credential issuance. This scenario is **separate from Part 1** and does **not** require or use the AppRole created earlier.

1. **Enable the database secrets engine**:

   ```bash
   vault secrets enable database
   vault secrets list
   ```

2. **(Optional) Create a password policy** for generated DB users:

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

3. **Configure the database connection** (adjust host as needed):

   ```bash
   vault write database/config/postgres \
     plugin_name=postgresql-database-plugin \
     allowed_roles="*" \
     password_policy="pg-alphanumeric" \
     connection_url="postgresql://{{username}}:{{password}}@host.minikube.internal:5432/vaultdb?sslmode=disable" \
     username="vaultuser" \
     password="vaultpass"
   ```

4. **Verify the database config**:

   ```bash
   vault read -format=json database/config/postgres
   ```

   Confirm that the read succeeds and shows the expected connection parameters.

---

### 4. Rotate Root Credentials (If Required for the Scenario)

Some exam scenarios explicitly require rotating the database root credentials used by the connection.

1. **Rotate the root credentials for `database/config/postgres`**:

   ```bash
   vault write -f database/rotate-root/postgres
   ```

2. **Re-read the database config**:

   ```bash
   vault read -format=json database/config/postgres
   ```

   Confirm the config still reads successfully, indicating the rotated credentials are valid.

---

### 5. Create a Dynamic Role for PostgreSQL

Goal: Configure Vault to issue **dynamic, short-lived PostgreSQL users**.

1. **Create a dynamic role** (e.g., `pg-readonly`):

   ```bash
   vault write database/roles/pg-readonly \
     db_name=postgres \
     creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT CONNECT ON DATABASE vaultdb TO \"{{name}}\";" \
     revocation_statements="DROP ROLE IF EXISTS \"{{name}}\";" \
     default_ttl="1h" \
     max_ttl="24h"
   ```

2. **(Optional) Admin-side sanity check for dynamic credentials**:

   ```bash
   vault read -format=json database/creds/pg-readonly \
     > db-creds-admin-test.json

   cat db-creds-admin-test.json | jq
   ```

   You should see:
   - `lease_id` under `database/creds/pg-readonly/...`
   - `username` and `password` fields.

3. **(Optional) Verify credentials against PostgreSQL**:

   ```bash
   DB_USER=$(jq -r '.data.username' db-creds-admin-test.json)
   DB_PASS=$(jq -r '.data.password' db-creds-admin-test.json)

   docker exec -it postgres-vault psql \
     "postgresql://$DB_USER:$DB_PASS@localhost:5432/vaultdb?sslmode=disable" \
     -c "SELECT current_user;"
   ```

---

### 7. Artifacts to Save for Grading

At minimum, keep these JSON files:

- `approle-role-id.json` – proves AppRole was created and `role_id` retrieved (Part 1).
- `approle-secret-id-wrapped.json` – proves correct use of `-wrap-ttl` and response wrapping (Part 1).
- `approle-secret-id-unwrapped.json` – shows the actual `secret_id` (typically from controlled unwrap, Part 1).
- `db-creds-admin-test.json` – admin-side validation of DB role configuration in Part 2.

---

### 8. Verification Checklist (Exam-Oriented)

Use this as a final self-check:

- **AppRole**
  - `vault auth list` shows `approle/` enabled.
  - `auth/approle/role/app-db-role` exists and is bound to `approle-demo`.
  - `approle-demo` policy is created and attached to the role (content is not used elsewhere in this lab).
- **Response wrapping**
  - `approle-secret-id-wrapped.json` contains `wrap_info.token` but not the `secret_id`.
  - Unwrap works once and fails on subsequent attempts.
- **Database secrets**
  - `database/config/postgres` can be read without error.
  - `database/roles/pg-readonly` exists and issues credentials.

If all of the above are true and your JSON artifacts are saved, you have successfully completed both Part 1 (AppRole + response wrapping) and Part 2 (PostgreSQL database secrets engine) for Lab 2.

