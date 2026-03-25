## Lab 3: Vault Agent with AppRole Auto-Auth and Templating

Objective:
- Configure Vault Agent from scratch with a correct `auto_auth` block.
- Configure AppRole auth for agent login.
- Render a template using Vault Agent templating.
- Validate token and lease-related behavior from the agent-issued token.
- Save rendered output to a file for grading.

This lab is a runbook walking you through the steps to configure Vault Agent with AppRole auto-auth and templating. In the exam, you will be directed to complete these steps and will not have explicit instructions on how to complete certain tasks. You will be required to create the vault agent config from scratch, and you will be expected to understand the underlying concepts/linux commands/etc. 

---

### How to Use This Hands-On Lab

1. **Create a Codespace** from this repo (click the button below).  
2. Once the Codespace is running, open the integrated terminal.
3. Follow the instructions in each **lab** to complete the exercises.

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](https://github.com/codespaces/new?hide_repo_select=true&ref=main&repo=1161798724&skip_quickstart=true&devcontainer_path=.devcontainer%2Fdevcontainer.json)

Quick checks:

```bash
echo "$VAULT_ADDR"
vault status
vault token lookup
```

Expected:
- `VAULT_ADDR` is `http://127.0.0.1:8200`.
- Vault is reachable and unsealed.
- Your token has enough privileges for auth, policy, and secret setup.

---

### 0. Lab Workspace Setup

Create working directories.

```bash
mkdir -p /tmp/lab-03/{auth,sink,templates,output}
```

Single-node reminder:
- This entire lab runs on one Linux node in one terminal context.
- Keep `VAULT_ADDR=http://127.0.0.1:8200` for all `vault` commands unless explicitly told otherwise.

---

### 1. Configure AppRole Auth First

Create a least-privilege policy for Vault Agent reads and token self-inspection.

```bash
cat > /tmp/lab-03/vault-agent-policy.hcl <<'EOF'
path "secret/data/agent-demo" {
  capabilities = ["read"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}
EOF

vault policy write vault-agent-policy /tmp/lab-03/vault-agent-policy.hcl
```

Enable AppRole auth and create the role.
- use the policy created above
- set `token_ttl` to 30m and `token_max_ttl` to 2h

```bash
vault auth enable approle

vault write auth/approle/role/lab3-agent-role \
  token_policies="vault-agent-policy" \
  token_ttl="30m" \
  token_max_ttl="2h" \
  secret_id_ttl="1h" \
  secret_id_num_uses=0
```

Capture `role_id` and `secret_id` to local files.

```bash
vault read -format=json auth/approle/role/lab3-agent-role/role-id \
  | jq -r '.data.role_id' > /tmp/lab-03/auth/role_id

vault write -f -format=json auth/approle/role/lab3-agent-role/secret-id \
  | jq -r '.data.secret_id' > /tmp/lab-03/auth/secret_id

chmod 600 /tmp/lab-03/auth/role_id /tmp/lab-03/auth/secret_id
```

Expected:
- AppRole role exists at `auth/approle/role/lab3-agent-role`.
- `/tmp/lab-03/auth/role_id` and `/tmp/lab-03/auth/secret_id` exist.

---

### 2. Seed KV Data for Agent Validation

Create a starter secret that you will later fetch using the token issued by Vault Agent.

```bash
vault kv put secret/agent-demo username="app-user" password="initial-pass"
```

Expected:
- Secret exists at `secret/data/agent-demo`.

---

### 3. Build the Initial Vault Agent Config (Auto-Auth + Sink)

Create `vault-agent.hcl` from scratch.

```bash
cat > /tmp/lab-03/vault-agent.hcl <<'EOF'
pid_file = "/tmp/lab-03/vault-agent.pid"

vault {
  address = "http://127.0.0.1:8200"
}

auto_auth {
  method "approle" {
    mount_path = "auth/approle"
    config = {
      role_id_file_path                   = "/tmp/lab-03/auth/role_id"
      secret_id_file_path                 = "/tmp/lab-03/auth/secret_id"
      remove_secret_id_file_after_reading = false
    }
  }

  sink "file" {
    config = {
      path = "/tmp/lab-03/sink/agent-token"
      mode = 0600
    }
  }
}
EOF
```

Important grading note:
- `remove_secret_id_file_after_reading = false` must be present.

Run grading command 1 now to see if you've configured everything correctly:

```bash
grep -q 'method "approle"' /tmp/lab-03/vault-agent.hcl && grep -Eq 'remove_secret_id_file_after_reading\s*=\s*false' /tmp/lab-03/vault-agent.hcl && echo && echo "PASS: configuration is setup correctly" || echo "FAIL: missing approle auto_auth or remove_secret_id_file_after_reading parameter"
```

---

### 4. Start Vault Agent and Run Required Validation Checks

Start the agent in the background and capture logs.

```bash
# Kill the agent is it's already running from a previous attempt
pgrep -f 'vault agent -config=/tmp/lab-03/vault-agent.hcl' | xargs -r kill

vault agent -config=/tmp/lab-03/vault-agent.hcl \
  > /tmp/lab-03/agent.log 2>&1 &
```

Run grading command 2 now (after starting Vault Agent) to confirm `secret_id` file still exists and auto-auth worked:

```bash
grep -Eqi 'authentication successful' /tmp/lab-03/agent.log && \
test -s /tmp/lab-03/sink/agent-token && \
vault token lookup "$(cat /tmp/lab-03/sink/agent-token)" >/dev/null 2>&1 && \
test -s /tmp/lab-03/auth/secret_id && \
echo && echo "PASS: auto_auth succeeded, sink token is valid, and secret_id still present" || \
echo "FAIL: auto_auth not confirmed, sink token invalid/missing, or secret_id missing"
```

Run all required checks:

```bash
# Check 1: secret_id still exists on filesystem
ls -l /tmp/lab-03/auth/secret_id

# Check 2: auto_auth worked (sink token exists + lookup succeeds)
vault token lookup -format=json "$(cat /tmp/lab-03/sink/agent-token)" | jq '.data | {policies, ttl, renewable, expire_time}'

# Check 3: read KV secret using agent token and store on local machine
VAULT_TOKEN="$(cat /tmp/lab-03/sink/agent-token)" \
  vault kv get -format=json secret/agent-demo \
  > /tmp/lab-03/output/kv-from-agent.json

cat /tmp/lab-03/output/kv-from-agent.json | jq '.data.data'
```

Expected:
- `secret_id` file is still present.
- Agent sink token exists and token lookup succeeds.
- `/tmp/lab-03/output/kv-from-agent.json` exists and contains KV values.

---

### 5. Add Templating for 3 Secrets at One Path

Update the same KV path to include three values:

```bash
vault kv put secret/agent-demo \
  username="app-user" \
  password="initial-pass" \
  api_key="abc123-initial"
```

Create the template file:

```bash
cat > /tmp/lab-03/templates/agent-demo.ctmpl <<'EOF'
{{- with secret "secret/data/agent-demo" -}}
username={{ .Data.data.username }}
password={{ .Data.data.password }}
api_key={{ .Data.data.api_key }}
version={{ .Data.metadata.version }}
{{- end }}
EOF
```

Update `vault-agent.hcl` using `vi` (add the template section to your existing config):

```bash
vi /tmp/lab-03/vault-agent.hcl
```

```hcl
template {
  source      = "/tmp/lab-03/templates/agent-demo.ctmpl"
  destination = "/tmp/lab-03/output/rendered-secret.txt"
  perms       = 0640
}
```

Restart the existing Vault Agent process:

```bash
# Kill the existing agent process
pgrep -f 'vault agent -config=/tmp/lab-03/vault-agent.hcl' | xargs -r kill

vault agent -config=/tmp/lab-03/vault-agent.hcl \
  > /tmp/lab-03/agent.log 2>&1 &
```

Validate rendered output file exists and contains all three keys:

```bash
cat /tmp/lab-03/output/rendered-secret.txt
```

Run grading command 3 now (after templating config + restart):

```bash
grep -q 'template {' /tmp/lab-03/vault-agent.hcl && grep -q '^username=' /tmp/lab-03/output/rendered-secret.txt && grep -q '^password=' /tmp/lab-03/output/rendered-secret.txt && grep -q '^api_key=' /tmp/lab-03/output/rendered-secret.txt && echo && echo "PASS: template configured and 3 secret keys rendered" || echo "FAIL: missing template stanza or rendered keys"
```

---

### 6. Rubric Checklist

Use this checklist directly against the Lab 3 grading rubric:

- Configure AppRole auth first:
  - Role exists and local `role_id`/`secret_id` files are created.
- Configure Vault Agent from scratch with correct auto-auth:
  - `vault-agent.hcl` includes `auto_auth` with AppRole.
- Do not delete secret-id upon agent authentication:
  - `remove_secret_id_file_after_reading = false` is set.
  - `/tmp/lab-03/auth/secret_id` still exists after agent startup.
- Validate auto-auth behavior:
  - Sink token is written and token lookup succeeds.
- Validate secret retrieval to local machine:
  - `/tmp/lab-03/output/kv-from-agent.json` exists.
- Add templating for 3 secrets at one path:
  - Template renders `username`, `password`, and `api_key` from one KV path.
  - Agent is restarted and template output is rendered locally.
- Use the 3 grading commands in-place:
  - End of Step 3 validates AppRole auto-auth and secret-id retention setting.
  - Step 4 validates secret-id still exists after agent start.
  - End of Step 5 validates template config and rendered 3-key output.

---

### 7. Cleanup

Stop the github codespace via the bottom left Codespaces panel.