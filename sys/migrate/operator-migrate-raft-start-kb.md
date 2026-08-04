# Vault Operator Migrate Incompatibility with Raft Destination

## Overview

`vault operator migrate -start <key>` does not work when the destination storage backend is `raft` (integrated storage). Any attempt to resume an interrupted or timed-out migration using `-start` fails immediately with:

```text
Error migrating: error mounting 'storage_destination': could not bootstrap clustered storage: error bootstrapping cluster: cluster already has state
```

This is a confirmed bug. The `-start` flag was introduced before Vault supported integrated storage, and the code path that bootstraps a Raft backend unconditionally fails if it detects an existing `vault.db` in the destination path. Resetting the migration lock first (`-reset`) does not help — the lock and the Raft bootstrap state are independent.

The workaround for large migrations (where timeouts force a multi-step approach) is to use an intermediate `file` backend: migrate from the source to a local file backend (which fully supports `-start`), then migrate from that file backend to Raft in a single pass.

## Symptoms

Interrupting a migration to Raft and trying to resume it:

```text
Error migrating: error mounting 'storage_destination': could not bootstrap clustered storage: error bootstrapping cluster: cluster already has state
```

Attempting the same after a `-reset`:

```text
Success! Migration lock reset (if it was set).
...
Error migrating: error mounting 'storage_destination': could not bootstrap clustered storage: error bootstrapping cluster: cluster already has state
```

On very large datasets (e.g. 1.4 million KVv2 secrets), migrations that time out or are cancelled by an upstream signal surface a related error:

```text
Error migrating: failed to scan for children: timeout: context canceled
```

This second error is not a timeout on the migration command itself — it is the process context being cancelled (by SIGINT, pod restart, or a connection failure from the source backend). The `-start` flag was intended to address this by allowing a resume from a known checkpoint, but it does not work when the destination is Raft.

## Root Cause

`vault operator migrate` always calls `Bootstrap()` on a Raft destination during backend initialization, regardless of whether `-start` is used to resume. The `Bootstrap()` function checks for an existing Raft state (`HasExistingState`) and refuses to proceed if any state is found. Because the first migration run writes `vault.db` to the destination directory as part of Raft cluster setup, all subsequent invocations fail at this point.

Relevant source locations:

- `command/operator_migrate.go` — `createDestinationBackend` unconditionally calls `Bootstrap` on the Raft backend on every invocation, including `-start` resume runs.
- `physical/raft/raft.go` — `Bootstrap` checks `HasExistingState` and returns `error bootstrapping cluster: cluster already has state` if any prior Raft data exists.

The `-start` key-skip logic in `migrateAll` is never reached because `createDestinationBackend` fails first.

This behavior has been reported in:

- https://github.com/hashicorp/vault/issues/11026 (filed March 2021, closed without a fix)
- https://github.com/hashicorp/vault/issues/10769 (filed January 2021, same symptom)

No fix has been released as of the time this KB was written.

## Affected Versions

All Vault versions that support integrated storage (v1.2.0 and later). The underlying code path is unchanged across the full release range through at least v1.21.x and v2.0.x.

## Lab Setup

The Terraform in [`sys/migrate/terraform/`](terraform/) provisions a self-contained lab to reproduce this scenario:

- 3 Vault Enterprise nodes configured with `postgresql` storage and `awskms` auto-unseal.
- 1 PostgreSQL node pre-configured with the Vault storage schema (`vault_kv_store`, `vault_ha_locks`).
- Both migration HCL configs pre-staged on each Vault node at `/opt/vault/migrate/`.

```bash
cd sys/migrate/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your key_name, admin_ssh_cidr, vault_license, and postgres_db_password.
# Or set the sensitive values as environment variables:
#   export TF_VAR_vault_license="$VAULT_LICENSE"
#   export TF_VAR_postgres_db_password="<password>"

terraform init
terraform apply
```

Export the node IPs for use in later steps:

```bash
terraform output -json vault_nodes > /tmp/vault-nodes.json
export PRIMARY_1_PUBLIC_IP=$(jq -r '."vault-migrate-lab-1".public_ip' /tmp/vault-nodes.json)
export PRIMARY_2_PUBLIC_IP=$(jq -r '."vault-migrate-lab-2".public_ip' /tmp/vault-nodes.json)
export PRIMARY_3_PUBLIC_IP=$(jq -r '."vault-migrate-lab-3".public_ip' /tmp/vault-nodes.json)
export PRIMARY_1_PRIVATE_IP=$(jq -r '."vault-migrate-lab-1".private_ip' /tmp/vault-nodes.json)
export PRIMARY_2_PRIVATE_IP=$(jq -r '."vault-migrate-lab-2".private_ip' /tmp/vault-nodes.json)
export PRIMARY_3_PRIVATE_IP=$(jq -r '."vault-migrate-lab-3".private_ip' /tmp/vault-nodes.json)
```

SSH to node-1 and initialize the cluster:

```bash
ssh -i "$SSH_PRIVATE_KEY" ec2-user@"$PRIMARY_1_PUBLIC_IP"
export VAULT_ADDR=http://127.0.0.1:8200
vault operator init -format=json -key-shares=1 -key-threshold=1 > /tmp/init.json
export VAULT_TOKEN=$(jq -r '.root_token' /tmp/init.json)
```

Because awskms auto-unseal is configured, the cluster unseals automatically after init. Load test data to simulate a large migration:

```bash
vault secrets enable -path=secret kv-v2

for i in $(seq 1 500); do
  vault kv put secret/test-$i value="data-$i" > /dev/null
done

vault kv list secret/ | wc -l
```

## Workaround: Two-Phase Migration via Intermediate File Backend

Because `-start` works correctly when the destination is a `file` backend, the recommended approach for large migrations is:

1. Migrate from the source (PostgreSQL) to a local `file` backend, using `-start` to resume if interrupted.
2. Once the file backend contains a complete copy of all data, migrate from that `file` backend to `raft` in a single uninterrupted pass.

This trades a single risky one-step migration for two smaller, resumable steps.

### Prerequisites

- Vault CLI matching the source cluster version.
- The source Vault cluster must be sealed and offline for the duration of the migration to ensure data consistency. Stop the Vault service on all nodes before running `vault operator migrate`.
- Sufficient local disk space for a full copy of the Vault storage data (check with `df -h /opt/vault/migrate`).
- If using the lab Terraform, both migration configs are pre-staged at `/opt/vault/migrate/` on node-1. Run `vault operator migrate` from node-1 only.

### Step 1: Seal and stop Vault on all nodes

Before migrating, seal and stop Vault on every node to prevent writes during the migration:

```bash
for HOST in \
  "$PRIMARY_1_PUBLIC_IP" "$PRIMARY_2_PUBLIC_IP" "$PRIMARY_3_PUBLIC_IP"
do
  ssh -i "$SSH_PRIVATE_KEY" ec2-user@"$HOST" "
    export VAULT_ADDR=http://127.0.0.1:8200
    vault operator seal
    sudo systemctl stop vault
  "
done
```

Confirm all nodes are stopped:

```bash
for HOST in \
  "$PRIMARY_1_PUBLIC_IP" "$PRIMARY_2_PUBLIC_IP" "$PRIMARY_3_PUBLIC_IP"
do
  ssh -i "$SSH_PRIVATE_KEY" ec2-user@"$HOST" "
    sudo systemctl is-active vault || echo stopped
  "
done
```

### Step 2: Run the first phase (PostgreSQL → file)

SSH to node-1 and run the migration as the `vault` user. The migration configs are pre-staged at `/opt/vault/migrate/`.

```bash
ssh -i "$SSH_PRIVATE_KEY" ec2-user@"$PRIMARY_1_PUBLIC_IP"

sudo -u vault VAULT_CLIENT_TIMEOUT=3600s vault operator migrate \
  -config /opt/vault/migrate/phase1-postgres-to-file.hcl \
  -log-level=info
```

If the migration is interrupted, note the last `copied key: path=<key>` line in the logs. Reset the lock and resume from that key:

```bash
sudo -u vault VAULT_CLIENT_TIMEOUT=3600s vault operator migrate \
  -config /opt/vault/migrate/phase1-postgres-to-file.hcl \
  -reset

sudo -u vault VAULT_CLIENT_TIMEOUT=3600s vault operator migrate \
  -config /opt/vault/migrate/phase1-postgres-to-file.hcl \
  -log-level=info \
  -start "<last-copied-key>"
```

Repeat as needed until you see:

```text
Success! All of the keys have been migrated.
```

### Step 3: Validate the intermediate file backend

Spot-check the destination directory to confirm data is present before proceeding:

```bash
ls -lha /opt/vault/migrate/file-intermediate/
```

The directory should contain subdirectories matching Vault's storage tree (`core/`, `logical/`, `sys/`, etc.).

### Step 4: Run the second phase (file → Raft)

Ensure the Raft destination directory is clean (no prior `vault.db` or Raft data):

```bash
ls -lha /opt/vault/migrate/raft-destination/
```

If the directory is not empty or contains a prior partial run, clear it before proceeding:

```bash
sudo rm -rf /opt/vault/migrate/raft-destination/*
```

The `phase2-file-to-raft.hcl` config requires `cluster_addr` as a top-level key (not inside the `storage_destination` block) and must use the same `node_id` as the node's `vault.hcl`. The pre-staged config on node-1 already uses `vault-migrate-lab-1` and `http://10.0.10.10:8201`. Verify before running:

```bash
cat /opt/vault/migrate/phase2-file-to-raft.hcl
```

Expected:

```hcl
cluster_addr = "http://10.0.10.10:8201"

storage_source "file" {
  path = "/opt/vault/migrate/file-intermediate"
}

storage_destination "raft" {
  path    = "/opt/vault/migrate/raft-destination"
  node_id = "vault-migrate-lab-1"
}
```

Run the second phase in a single pass. Do not interrupt this step.

```bash
sudo -u vault VAULT_CLIENT_TIMEOUT=3600s vault operator migrate \
  -config /opt/vault/migrate/phase2-file-to-raft.hcl \
  -log-level=info
```

```text
Success! All of the keys have been migrated.
```

### Step 5: Validate the Raft destination

Update `vault.hcl` on every node to replace the `postgresql` storage stanza with a `raft` storage stanza pointing at the migration destination. Run this from your workstation:

```bash
PRIVATE_IPS=("$PRIMARY_1_PRIVATE_IP" "$PRIMARY_2_PRIVATE_IP" "$PRIMARY_3_PRIVATE_IP")
NODE_IDS=("vault-migrate-lab-1" "vault-migrate-lab-2" "vault-migrate-lab-3")
HOSTS=("$PRIMARY_1_PUBLIC_IP" "$PRIMARY_2_PUBLIC_IP" "$PRIMARY_3_PUBLIC_IP")

for i in 0 1 2; do
  ssh -i "$SSH_PRIVATE_KEY" ec2-user@"${HOSTS[$i]}" "
    sudo python3 -c \"
import re

config = open('/etc/vault.d/vault.hcl').read()

new_storage = '''storage \\\"raft\\\" {
  path    = \\\"/opt/vault/migrate/raft-destination\\\"
  node_id = \\\"${NODE_IDS[$i]}\\\"

  retry_join {
    leader_api_addr = \\\"http://${PRIVATE_IPS[0]}:8200\\\"
  }
  retry_join {
    leader_api_addr = \\\"http://${PRIVATE_IPS[1]}:8200\\\"
  }
  retry_join {
    leader_api_addr = \\\"http://${PRIVATE_IPS[2]}:8200\\\"
  }
}'''

config = re.sub(r'storage \\\"postgresql\\\".*?^}', new_storage, config, flags=re.DOTALL|re.MULTILINE)
open('/etc/vault.d/vault.hcl', 'w').write(config)
print('updated vault.hcl on ${NODE_IDS[$i]}')
\"
  "
done
```

Verify the config looks correct on each node before starting Vault:

```bash
for HOST in "$PRIMARY_1_PUBLIC_IP" "$PRIMARY_2_PUBLIC_IP" "$PRIMARY_3_PUBLIC_IP"; do
  ssh -i "$SSH_PRIVATE_KEY" ec2-user@"$HOST" "sudo cat /etc/vault.d/vault.hcl"
done
```

Nodes 2 and 3 do not have a `raft-destination` directory — the migration only ran on node-1. Create it on the followers before starting Vault:

```bash
for HOST in "$PRIMARY_2_PUBLIC_IP" "$PRIMARY_3_PUBLIC_IP"; do
  ssh -i "$SSH_PRIVATE_KEY" ec2-user@"$HOST" "
    sudo mkdir -p /opt/vault/migrate/raft-destination
    sudo chown vault:vault /opt/vault/migrate/raft-destination
  "
done
```

Start Vault on node-1 first and wait for it to become active:

```bash
ssh -i "$SSH_PRIVATE_KEY" ec2-user@"$PRIMARY_1_PUBLIC_IP" "
  sudo systemctl start vault
  sleep 5
  export VAULT_ADDR=http://127.0.0.1:8200
  vault status
"
```

Then start nodes 2 and 3 and join them to the cluster:

```bash
for HOST in "$PRIMARY_2_PUBLIC_IP" "$PRIMARY_3_PUBLIC_IP"; do
  ssh -i "$SSH_PRIVATE_KEY" ec2-user@"$HOST" "
    sudo systemctl start vault
    sleep 3
    export VAULT_ADDR=http://127.0.0.1:8200
    vault operator raft join http://$PRIMARY_1_PRIVATE_IP:8200
  "
done
```

Confirm all three peers are present and the cluster is healthy:

```bash
ssh -i "$SSH_PRIVATE_KEY" ec2-user@"$PRIMARY_1_PUBLIC_IP" "
  export VAULT_ADDR=http://127.0.0.1:8200
  export VAULT_TOKEN=\$(jq -r '.root_token' /tmp/init.json)
  vault operator raft list-peers
  vault kv list secret/
"
```

Expected output:

```text
Node                  Address            State       Voter
----                  -------            -----       -----
vault-migrate-lab-1   10.0.10.10:8201    leader      true
vault-migrate-lab-2   10.0.20.10:8201    follower    true
vault-migrate-lab-3   10.0.30.10:8201    follower    true
```

## Identifying the Resume Key After a Timeout

When a migration is interrupted, the last logged `copied key: path=<key>` line is the last key that was successfully written. Use the key path from that line (or a prefix of it) as the value for `-start`.

Example: if the last logged line was:

```text
copied key: path=logical/3e1cf438-15db-9cb1-01b0-9a94aded53d8/oidc_tokens/public_keys/d9f7bfa8
```

You can resume from the beginning of that `logical/3e...` prefix:

```bash
-start "logical/3e1cf438-15db-9cb1-01b0-9a94aded53d8"
```

Keys are walked in lexicographic depth-first order, so any prefix of the last key path is a safe starting point. Starting slightly earlier is safer than starting later and risking a gap.

## Cleanup

After the Raft migration is confirmed complete and the new cluster is running, remove the intermediate file backend data:

```bash
ssh -i "$SSH_PRIVATE_KEY" ec2-user@"$PRIMARY_1_PUBLIC_IP" "
  sudo rm -rf /opt/vault/migrate/file-intermediate
"
```

To tear down the entire lab, run `terraform destroy` from `sys/migrate/terraform/`.

## References

- `vault operator migrate` command reference: https://developer.hashicorp.com/vault/docs/commands/operator/migrate
- Integrated storage migration guide: https://developer.hashicorp.com/vault/docs/concepts/integrated-storage/raft-migrate
- GitHub issue #11026 (resume with `-start` to Raft fails): https://github.com/hashicorp/vault/issues/11026
- GitHub issue #10769 (consul to raft migration fails on resume): https://github.com/hashicorp/vault/issues/10769
- Source: `command/operator_migrate.go` — `createDestinationBackend`, `migrateAll`, `dfsScan`
- Source: `physical/raft/raft.go` — `Bootstrap`, `HasExistingState`
