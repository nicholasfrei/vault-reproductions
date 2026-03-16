## Lab 4: Performance replication with path filtering

### Overview / Objective

This lab walks through configuring performance replication (PR) between two single-node Vault clusters and applying a paths filter so only selected data is replicated.

This is designed to be close to the Vault Professional exam experience: you will write commands and configuration from scratch, validate behavior with status endpoints, and persist JSON output where appropriate.

---

### Preconditions

- Two single-node Vault Enterprise clusters running in Kubernetes:
  - Primary: namespace `vault-pr-primary`, pod `vault-pr-primary-0`
  - Secondary: namespace `vault-pr-secondary`, pod `vault-pr-secondary-0`
- `kubectl` and `vault` CLI installed on your workstation.
- Vault Enterprise license already applied to both clusters.
- You have run:
  - `vault-professional-cert/lab-04-pr-setup.sh`
    - This script:
      - Initializes each cluster
      - Unseals the nodes
      - Saves init output:
        - Inside the pod: `/tmp/init.json`

For the rest of the lab, you will:

- Use the **primary root token** for all primary-side configuration.
- Use the **secondary root token** for all secondary-side configuration.

---

### 2. Open two terminals and log in inside each pod

Use two terminal windows/tabs so you can keep a shell open in both clusters.

- **Terminal 1 (secondary):**

```bash
kubectl exec -ti -n vault-pr-secondary vault-pr-secondary-0 -- sh
```

- **Terminal 2 (primary):**

```bash
kubectl exec -ti -n vault-pr-primary vault-pr-primary-0 -- sh
```

Inside **each** pod shell, log in with the root token from `/tmp/init.json` and validate status:

```bash
vault login <vault_token_from_init_json>
```

Validate status:

```bash
vault status
```
---

### 3. Enable performance replication on the primary
On the **primary** cluster, enable performance replication in primary mode and generate a secondary activation token.

```bash
# Enable PR primary
vault write -f sys/replication/performance/primary/enable

# Create and save a secondary activation token response
vault write -format=json sys/replication/performance/primary/secondary-token id="pr-secondary" \
  | tee /tmp/pr-secondary-token.json
```

The secondary token value in `/tmp/pr-secondary-token.json` is needed on the secondary.
Extract and copy it from the **primary** terminal.

# If you need to delete this token (for example, if it didn't work), run:
```bash
vault write sys/replication/performance/primary/revoke-secondary id="pr-secondary"
```
---

### 4. Enable performance replication on the secondary and join

On the **secondary** cluster, enable performance replication in secondary mode and join it to the primary using the activation token.

```bash
# Enable PR secondary
vault write -f sys/replication/performance/secondary/enable token="<paste-token-from-primary>"
```

Verify status from both sides:

```bash
vault read -format=json sys/replication/performance/status \
  | tee /tmp/pr-secondary-status.json
```

In the **primary** terminal:

```bash
vault read -format=json sys/replication/performance/status \
  | tee /tmp/pr-primary-status.json
```

Confirm:

- Primary shows mode: `primary`
- Secondary shows mode: `secondary`
- Both show `state` as `running` (or equivalent healthy state)

---

### 5. Configure a paths filter on the primary

In this lab you will:

- Deny replication for selected KV v2 endpoints
- Show that non-denied app paths continue to replicate

First, we will create some test data on the **primary**:

```bash
vault secrets enable -path=denied kv-v2 || true
vault secrets enable -path=secret kv-v2 || true
```
Apply a paths filter in `deny` mode for a couple of endpoints.
For KV v2, use API paths under `secret/data/...` in the filter.

See the official API docs for reference:  
`Performance replication: create paths filter` ([docs](https://developer.hashicorp.com/vault/api-docs/system/replication/replication-performance#create-paths-filter)).

```bash
vault write sys/replication/performance/primary/paths-filter/pr-secondary \
  mode="deny" \
  paths="denied/"
```

Verify the filter configuration:

```bash
vault read -format=json sys/replication/performance/primary/paths-filter/pr-secondary \
  | tee /tmp/pr-primary-paths-filter.json
```

Now write fresh test data **after** the filter is active:

```bash
# Allowed path (should replicate)
vault kv put secret/app api_key="allowed-789" env="dev"

# Denied paths (should NOT replicate)
vault kv put denied/ops note="blocked-by-filter"
vault kv put denied/internal token="blocked-by-filter"
```

Important:
- Data written before filter creation may already exist on the secondary.
- Validate filter behavior using the `postfilter` keys written after the filter is configured.

---

### 6. Validate replication and filtering

On the **secondary**, confirm the following behavior:

1. The secrets under `secret/app/` are replicated.
2. Fresh secrets written under denied paths after filter activation are **not** replicated.

If you do not have a secondary auth method enabled, you will need to generate a root token for the PR secondary.

Optional recovery flow on the **secondary**:

```bash
# Start a new attempt and record Nonce
vault operator generate-root -init

# Submit the key share using the nonce from the init output
vault operator generate-root -nonce="<nonce-from-init>" "<unseal_key_from_primary_cluster>"

# Decode the encoded token using OTP from the init output
vault operator generate-root \
  -decode="<encoded-token-from-previous-step>" \
  -otp="<otp-from-init>"

# Login with the decoded root token
vault login <new-root-token>
vault token lookup
```

On the secondary:

```bash
# These reads should succeed and show the replicated secrets
vault kv get secret/app

# These reads should fail (for example: 404 or permission error)
vault kv get denied/ops
vault kv get denied/internal 
```

---

### 7. Cleanup (optional)

To reset the environment after practice:

- In the **primary** terminal, delete the test secrets:

```bash
vault kv delete secret/app

vault kv delete denied/ops
vault kv delete denied/internal
```

- Optionally, disable the `secret` mount and clear the paths filter:

```bash
vault secrets disable secret || true
vault secrets disable denied || true

vault delete sys/replication/performance/primary/paths-filter/pr-secondary || true
```

- Tear down the clusters according to how you created them (Helm uninstall, namespace delete, or Minikube profile cleanup), consistent with your local lab conventions.

---

### References

- Performance replication concepts and API: [Vault docs](https://developer.hashicorp.com/vault/docs/enterprise/replication/performance)
