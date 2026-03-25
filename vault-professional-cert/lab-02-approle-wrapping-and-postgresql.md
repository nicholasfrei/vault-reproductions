## Lab 2: AppRole, Response Wrapping, and PostgreSQL Database Secrets

This lab contains **two distinct scenarios**:

- **Part 1**: Configure **AppRole auth** and use **response wrapping** to generate and safely deliver a `secret_id`, saving the wrapped output to JSON.
- **Part 2**: Configure the **PostgreSQL database secrets engine** for dynamic credentials, including root rotation and role-based credential generation.

---

### How to Use This Hands-On Lab

1. **Create a Codespace** from this repo using the Lab 02 devcontainer link below.
2. Once the Codespace is running, open the integrated terminal.
3. Confirm Vault is up before starting the lab steps.
4. Follow the instructions first, and only expand the command spoilers when you need a hint or want to verify exact syntax.

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://github.com/codespaces/new?hide_repo_select=true&ref=main&repo=1161798724&skip_quickstart=true&devcontainer_path=.devcontainer%2Flab-02%2Fdevcontainer.json)

Quick checks:

```bash
echo "$VAULT_ADDR"
vault status
vault token lookup
docker ps --filter "name=postgres-vault"
```

Expected:
- `VAULT_ADDR` is `http://127.0.0.1:8200`.
- Vault is unsealed in dev mode.
- `VAULT_TOKEN` is privileged enough for lab setup.
- `postgres-vault` is running on port `5432`.

If PostgreSQL is not running, bootstrap it:

```bash
bash .devcontainer/lab-02/start-postgres.sh
docker ps --filter "name=postgres-vault"
```

---

### 0. Assumptions and Lab Setup

- **Vault** is already running and unsealed.
- You have a privileged token exported as `VAULT_TOKEN` with permissions to:
  - Enable auth methods
  - Write policies
  - Configure the database secrets engine
- PostgreSQL is available in the same Codespace as Docker container `postgres-vault` on `127.0.0.1:5432`.
- `vault` CLI is installed and `VAULT_ADDR` is set.
- `jq` is available for JSON parsing.

> Adjust hostnames, ports, and credentials as needed for your environment, but keep the **shape** of commands and JSON output consistent with this lab for grading.

IMPORTANT: You can expand each step to reveal the command blocks if you get stuck.

---

### 1. Part 1: AppRole and Response Wrapping

Goal: Enable AppRole and create a role that can be used with **response wrapping** to safely deliver a `secret_id` and save the wrapped output to a JSON file.

1. **Enable the AppRole auth method**:

   Required outcome:
   - `approle/` exists in `vault auth list`.

   <details>
   <summary>Enable AppRole and verify mount</summary>

   ```bash
   vault auth enable approle
   vault auth list
   ```

   </details>

2. **Create a simple AppRole policy** (e.g., `approle-demo`) It exists just to demonstrate that the role can have policies attached:

   Required inputs:
   - policy file name: `approle-demo.hcl`
   - policy name in Vault: `approle-demo`
   - path: `secret/data/approle-demo`
   - capabilities: `read`, `list`

   <details>
   <summary>Create and apply policy approle-demo</summary>

   ```bash
   cat > approle-demo.hcl <<EOF
   path "secret/data/approle-demo" {
     capabilities = ["read", "list"]
   }
   EOF

   vault policy write approle-demo approle-demo.hcl
   vault policy read approle-demo
   ```

   </details>

3. **Create the AppRole** bound to this policy:

   Required values:
   - role name: `app-db-role`
   - attached policy: `approle-demo`
   - `token_ttl`: `1h`
   - `token_max_ttl`: `4h`
   - `secret_id_num_uses`: `1`
   - `secret_id_ttl`: `1h`

   <details>
   <summary>Create AppRole app-db-role with required TTLs</summary>

   ```bash
   vault write auth/approle/role/app-db-role \
     token_policies="approle-demo" \
     token_ttl="1h" \
     token_max_ttl="4h" \
     secret_id_num_uses=1 \
     secret_id_ttl="1h"
   ```

   </details>

4. **Fetch and persist the `role_id` to JSON**:

   Required output file:
   - save JSON to `approle-role-id.json`

   Validation target:
   - extract `.data.role_id` from that JSON file.

   <details>
   <summary>Read role_id and save to approle-role-id.json</summary>

   ```bash
   vault read -format=json auth/approle/role/app-db-role/role-id \
     > approle-role-id.json

   cat approle-role-id.json | jq -r '.data.role_id'
   ```

   </details>

   Keep `approle-role-id.json` for grading.

---

### 2. Generate a Wrapped `secret_id` and Persist JSON

Goal: Use **response wrapping** with `-wrap-ttl` and persist the **wrapped** result to JSON. You will later unwrap it as part of the AppRole login flow.

1. **Generate a wrapped `secret_id`**:

   Required values:
   - wrap TTL: `4h`
   - output format: `json`
   - output file: `approle-secret-id-wrapped.json`

   <details>
   <summary>Generate wrapped secret_id and save JSON</summary>

   ```bash
   vault write -f -wrap-ttl=4h -format=json \
     auth/approle/role/app-db-role/secret-id \
     > approle-secret-id-wrapped.json
   ```

   </details>

2. **Inspect the wrapped response**:

   Inspect `approle-secret-id-wrapped.json` and verify it contains `wrap_info` (not plaintext `secret_id`).

   <details>
   <summary>Inspect wrapped JSON</summary>

   ```bash
   cat approle-secret-id-wrapped.json | jq
   ```

   </details>

   Confirm that:
   - The **actual `secret_id` is not visible**.
   - A `wrap_info` block exists with fields like `token`, `ttl`, and `creation_time`.

3. **(Optional but recommended) Validate wrapped token one-time use**:

   Optional validation flow:
   - read `wrap_info.token` into `WRAP_TOKEN`
   - unwrap once and save to `approle-secret-id-unwrapped.json`
   - attempt a second unwrap with same wrapping token and confirm failure

   <details>
   <summary>Validate one-time unwrap behavior</summary>

   ```bash
   WRAP_TOKEN=$(jq -r '.wrap_info.token' approle-secret-id-wrapped.json)

   # First unwrap: should succeed and reveal the secret_id
   VAULT_TOKEN="$WRAP_TOKEN" vault unwrap -format=json \
     > approle-secret-id-unwrapped.json

   cat approle-secret-id-unwrapped.json | jq

   # Second unwrap: should fail
   VAULT_TOKEN="$WRAP_TOKEN" vault unwrap
   ```

   </details>

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

   Required outcome:
   - `database/` appears in `vault secrets list`.

   <details>
   <summary>Enable database secrets engine</summary>

   ```bash
   vault secrets enable database
   vault secrets list
   ```

   </details>

2. **(Optional) Create a password policy** for generated DB users:

   Optional policy requirements:
   - local policy file: `pg-password-policy.hcl`
   - Vault password policy name: `pg-alphanumeric`
   - length: `20`
   - include lowercase, uppercase, and numeric character rules

   <details>
   <summary>Create password policy pg-alphanumeric</summary>

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

   </details>

3. **Configure the database connection** (adjust host as needed):

   Required values:
   - config name: `postgres` (path: `database/config/postgres`)
   - plugin: `postgresql-database-plugin`
   - allowed roles: `*`
   - db host/port/dbname: `127.0.0.1:5432/vaultdb`
   - admin user/password: `vaultuser` / `vaultpass`

   Note: keep `password_policy="pg-alphanumeric"` only if you created that optional policy.

   <details>
   <summary>Configure database/config/postgres</summary>

   ```bash
   vault write database/config/postgres \
     plugin_name=postgresql-database-plugin \
     allowed_roles="*" \
     password_policy="pg-alphanumeric" \
     connection_url="postgresql://{{username}}:{{password}}@127.0.0.1:5432/vaultdb?sslmode=disable" \
     username="vaultuser" \
     password="vaultpass"
   ```

   </details>

4. **Verify the database config**:

   Read and verify `database/config/postgres` returns successfully.

   <details>
   <summary>Read database config as JSON</summary>

   ```bash
   vault read -format=json database/config/postgres
   ```

   </details>

   Confirm that the read succeeds and shows the expected connection parameters.

---

### 4. Rotate Root Credentials (If Required for the Scenario)

Some exam scenarios explicitly require rotating the database root credentials used by the connection.

1. **Rotate the root credentials for `database/config/postgres`**:

   Execute root rotation for config name `postgres`.

   <details>
   <summary>Rotate root credentials</summary>

   ```bash
   vault write -f database/rotate-root/postgres
   ```

   </details>

2. **Re-read the database config**:

   Re-read config and confirm it still succeeds.

   <details>
   <summary>Re-read database config after rotation</summary>

   ```bash
   vault read -format=json database/config/postgres
   ```

   </details>

   Confirm the config still reads successfully, indicating the rotated credentials are valid.

---

### 5. Create a Dynamic Role for PostgreSQL

Goal: Configure Vault to issue **dynamic, short-lived PostgreSQL users**.

1. **Create a dynamic role** (e.g., `pg-readonly`):

   Required values:
   - role name: `pg-readonly`
   - db config name in role: `db_name=postgres`
   - `default_ttl`: `1h`
   - `max_ttl`: `24h`

   <details>
   <summary>Create dynamic role pg-readonly</summary>

   ```bash
   vault write database/roles/pg-readonly \
     db_name=postgres \
     creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT CONNECT ON DATABASE vaultdb TO \"{{name}}\";" \
     revocation_statements="DROP ROLE IF EXISTS \"{{name}}\";" \
     default_ttl="1h" \
     max_ttl="24h"
   ```

   </details>

2. **(Optional) Admin-side sanity check for dynamic credentials**:

   Optional validation target:
   - read from `database/creds/pg-readonly`
   - save JSON to `db-creds-admin-test.json`

   <details>
   <summary>Read dynamic DB creds and save JSON</summary>

   ```bash
   vault read -format=json database/creds/pg-readonly \
     > db-creds-admin-test.json

   cat db-creds-admin-test.json | jq
   ```

   </details>

   You should see:
   - `lease_id` under `database/creds/pg-readonly/...`
   - `username` and `password` fields.

3. **(Optional) Verify credentials against PostgreSQL**:

   Optional verification inputs:
   - extract `.data.username` and `.data.password` from `db-creds-admin-test.json`
   - connect to `postgres-vault` and run `SELECT current_user;`

   <details>
   <summary>Test issued credentials against PostgreSQL</summary>

   ```bash
   DB_USER=$(jq -r '.data.username' db-creds-admin-test.json)
   DB_PASS=$(jq -r '.data.password' db-creds-admin-test.json)

   docker exec -it postgres-vault psql \
     "postgresql://$DB_USER:$DB_PASS@localhost:5432/vaultdb?sslmode=disable" \
     -c "SELECT current_user;"
   ```

   </details>

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

