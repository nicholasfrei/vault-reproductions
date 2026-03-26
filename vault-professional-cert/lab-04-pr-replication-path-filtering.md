## Lab 4: Performance replication with path filtering

### Overview / Objective

This lab walks through configuring performance replication (PR) between two single-node Vault clusters and applying a paths filter so only selected data is replicated.

This is designed to be close to the Vault Professional exam experience: you will write commands and configuration from scratch, validate behavior with status endpoints, and persist JSON output where appropriate.

---

### Lab Setup

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

Use two terminal windows/tabs so you can keep a shell open in both clusters. Exec into the shell of both pods:

<details>
<summary>Open shell in primary and secondary pods</summary>

```bash
# Open shell in primary pod
kubectl exec -ti -n vault-pr-primary vault-pr-primary-0 -- sh
# Open shell in secondary pod (different terminal)
kubectl exec -ti -n vault-pr-secondary vault-pr-secondary-0 -- sh
```

</details>

Inside **each** pod shell, log in with the root token from `/tmp/init.json` and validate status:

Required login input:
- root token from `/tmp/init.json` in that same pod.

Validation target:
- `vault status` succeeds in both pods.

<details>
<summary>Login in each pod shell & check Vault status</summary>

```bash
vault login <vault_token_from_init_json>
vault status
```

</details>

---

### 3. Enable performance replication on the primary 
On the **primary** cluster, enable performance replication & generate a secondary activation token.

Required values:
- secondary ID: `pr-secondary`
- save token response to `/tmp/pr-secondary-token.json`

Required outcomes:
- primary performance replication mode enabled
- secondary activation token generated and persisted for later join

<details>
<summary>Enable PR primary and create activation token</summary>

```bash
# Enable PR primary
vault write -f sys/replication/performance/primary/enable

# Create and save a secondary activation token response
vault write -format=json sys/replication/performance/primary/secondary-token id="pr-secondary" \
  | tee /tmp/pr-secondary-token.json
```

</details>

The secondary token value in `/tmp/pr-secondary-token.json` is needed on the secondary.
Extract and copy it from the **primary** terminal.

If you need to delete this token (for example, if it didn't work), check the hint below:

<details>
<summary>Optional: Revoke secondary activation token</summary>

```bash
vault write sys/replication/performance/primary/revoke-secondary id="pr-secondary"
```

</details>
---

### 4. Enable performance replication on the secondary and join

On the **secondary** cluster, enable performance replication as a secondary & join it to the primary using the activation token.

Required input:
- token value from `/tmp/pr-secondary-token.json` on the primary.

Required outcome:
- secondary enters replication mode and joins primary.

<details>
<summary>Enable PR secondary and join with activation token</summary>

```bash
# Enable PR secondary
vault write -f sys/replication/performance/secondary/enable token="<paste-token-from-primary>"
```

</details>

Verify status from both sides and output the results to JSON files:

Required artifact files:
- primary status: `/tmp/pr-primary-status.json`
- secondary status: `/tmp/pr-secondary-status.json`

In the **primary** terminal:

<details>
<summary>Read PR status from primary</summary>

```bash
vault read -format=json sys/replication/performance/status \
  | tee /tmp/pr-primary-status.json
```

</details>

In the **secondary** terminal:

<details>
<summary>Read PR status from secondary</summary>

```bash
vault read -format=json sys/replication/performance/status \
  | tee /tmp/pr-secondary-status.json
```

</details>

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

Required mounts:
- KV v2 at `denied/`
- KV v2 at `secret/`

```bash
vault secrets enable -path=denied kv-v2 || true
vault secrets enable -path=secret kv-v2 || true
```

Apply a paths filter with the following settings:
- filter name/ID: `pr-secondary`
- mode: `deny`
- paths: `denied/`

<details>
<summary>Create deny-mode paths filter on primary</summary>

```bash
vault write sys/replication/performance/primary/paths-filter/pr-secondary \
  mode="deny" \
  paths="denied/"
```

</details>

Verify the filter configuration and output the results to a JSON file:

Required artifact:
- save filter read output to `/tmp/pr-primary-paths-filter.json`

<details>
<summary>Read paths filter configuration</summary>

```bash
vault read -format=json sys/replication/performance/primary/paths-filter/pr-secondary \
  | tee /tmp/pr-primary-paths-filter.json
```

</details>

Now write fresh test data **after** the filter is active:

Required writes:
- allowed path: `secret/app`
- denied test paths: `denied/ops` and `denied/internal`

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

Generate a new secondary root token:

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

On the secondary, validate the replicated and filtered paths:

Required validation behavior:
- `secret/app` read succeeds.
- `denied/ops` and `denied/internal` fail (for example `404` or permission error).

<details>
<summary>Validate replicated and filtered paths on secondary</summary>

```bash
# These reads should succeed and show the replicated secrets
vault kv get secret/app

# These reads should fail (for example: 404 or permission error)
vault kv get denied/ops
vault kv get denied/internal 
```

</details>

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

- [Performance replication concepts and API](https://developer.hashicorp.com/vault/docs/enterprise/replication/performance)
- [Performance replication: create paths filter](https://developer.hashicorp.com/vault/api-docs/system/replication/replication-performance#create-paths-filter)
