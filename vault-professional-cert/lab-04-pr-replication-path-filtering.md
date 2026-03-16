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
vault secrets enable -path=secret kv-v2 || true

vault kv put secret/app/frontend api_key="frontend-123" env="dev"
vault kv put secret/app/backend api_key="backend-456" env="dev"
vault kv put secret/ops/internal note="should-not-be-replicated"
vault kv put secret/internal/service token="should-not-be-replicated"
```
Apply a paths filter in `deny` mode for a couple of endpoints.
For KV v2, use API paths under `secret/data/...` in the filter.

See the official API docs for reference:  
`Performance replication: create paths filter` ([docs](https://developer.hashicorp.com/vault/api-docs/system/replication/replication-performance#create-paths-filter)).

```bash
vault write sys/replication/performance/primary/paths-filter/filter \
  mode="deny" \
  paths="secret/data/ops/*,secret/data/internal/*"
```

Verify the filter configuration:

```bash
vault read -format=json sys/replication/performance/primary/paths-filter/filter \
  | tee /tmp/pr-primary-paths-filter.json
```

---

### 6. Validate replication and filtering

On the **secondary**, confirm the following behavior:

1. The secrets under `secret/app/` are replicated.
2. The secrets under denied paths are **not** replicated.

On the secondary:

```bash
vault secrets enable -path=secret kv-v2 || true

vault kv get secret/app/frontend
vault kv get secret/app/backend

# These reads should fail (for example: 404 or permission error)
vault kv get secret/ops/internal || echo "As expected: secret/ops/internal not present on secondary"
vault kv get secret/internal/service || echo "As expected: secret/internal/service not present on secondary"
```

You can also re-check the replication status endpoint, which is used in the exam guide checklist:

```bash
vault read -format=json sys/replication/performance/status
```

In the **primary** terminal:

```bash
vault read -format=json sys/replication/performance/status
```

---

### 7. Cleanup (optional)

To reset the environment after practice:

- In the **primary** terminal, delete the test secrets:

```bash
vault kv delete secret/app/frontend
vault kv delete secret/app/backend
vault kv delete secret/ops/internal
vault kv delete secret/internal/service
```

- Optionally, disable the `secret` mount and clear the paths filter:

```bash
vault secrets disable secret || true

vault delete sys/replication/performance/primary/paths-filter || true
```

- Tear down the clusters according to how you created them (Helm uninstall, namespace delete, or Minikube profile cleanup), consistent with your local lab conventions.

---

### References

- Performance replication concepts and API: [Vault docs](https://developer.hashicorp.com/vault/docs/enterprise/replication/performance)
