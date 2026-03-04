# RabbitMQ Secrets Engine Reproduction

This reproduction configures the Vault RabbitMQ secrets engine to generate dynamic RabbitMQ users on demand.

It assumes your Kubernetes Vault cluster is already running and unsealed.

## Prerequisites

- Docker
- `kubectl` configured to your cluster
- Vault CLI available in the Vault pod
- `curl` on your host

## Goal

- Run RabbitMQ locally with management API enabled
- Configure Vault RabbitMQ secrets engine from inside `vault-0`
- Generate short-lived RabbitMQ credentials
- Verify generated credentials can authenticate to RabbitMQ

## Step 1: Start RabbitMQ on the Host

Run RabbitMQ with the management plugin exposed:

```bash
docker run -d \
  --name rabbitmq-vault \
  -p 5672:5672 \
  -p 15672:15672 \
  rabbitmq:3-management
```

Verify the container is running:

```bash
docker ps | grep rabbitmq-vault
```

Wait for startup to complete:

```bash
docker exec -it rabbitmq-vault rabbitmq-diagnostics -q ping
```

## Step 2: Create a RabbitMQ Admin User for Vault

The default `guest` account is usually restricted to localhost access, so create a dedicated admin user for Vault:

```bash
docker exec -it rabbitmq-vault rabbitmqctl add_user vaultadmin vaultpass
docker exec -it rabbitmq-vault rabbitmqctl set_user_tags vaultadmin administrator
docker exec -it rabbitmq-vault rabbitmqctl set_permissions -p / vaultadmin ".*" ".*" ".*"
```

Confirm management API access from your host:

```bash
curl -s -u vaultadmin:vaultpass http://localhost:15672/api/whoami
```

Expected result includes:
```text
{"name":"vaultadmin","tags":["administrator"],"is_internal_user":true}
```
- `"name":"vaultadmin"`
- `"tags":"administrator"`

## Step 3: Enter Vault Pod

```bash
kubectl exec -n vault -ti vault-0 -- sh
```

## Step 4: Enable and Configure RabbitMQ Secrets Engine

Enable the engine:

```bash
vault secrets enable rabbitmq
```

Configure the RabbitMQ connection (`host.minikube.internal` allows Vault-in-Kubernetes to reach host Docker):

```bash
vault write rabbitmq/config/connection \
  connection_uri="http://host.minikube.internal:15672" \
  username="vaultadmin" \
  password="vaultpass"
```

## Step 5: Create a Dynamic Role

Create a role that grants full permissions on vhost `/`:

```bash
vault write rabbitmq/roles/dev-full \
  vhosts='{"/":{"configure":".*","write":".*","read":".*"}}' \
  tags='management' \
  ttl="1h" \
  max_ttl="24h"
```

Verify role:

```bash
vault read rabbitmq/roles/dev-full
```

## Step 6: Generate and Validate Dynamic Credentials

Generate credentials:

```bash
vault read rabbitmq/creds/dev-full
```

Output:
```text
Key                Value
---                -----
lease_id           rabbitmq/creds/dev-full/Yn9MCBw2k5GuFpPYG0tQIjgu
lease_duration     768h
lease_renewable    true
password           vwWStpVjqOIRWNGqIfq7xb3iWR6Wdczl5D5r
username           root-f643252a-1642-2791-8888-1b94bd03f83f
```

Expected fields:
- `lease_id`
- `lease_duration`
- `username`
- `password`

From the output, export generated values:

```bash
export RMQ_USER="<generated-username>"
export RMQ_PASS="<generated-password>"
```

From your host terminal, verify authentication:

```bash
curl -s -u "$RMQ_USER:$RMQ_PASS" http://localhost:15672/api/whoami
```

Expected result:
```text
{"name":"root-f643252a-1642-2791-8888-1b94bd03f83f","tags":["management"],"is_internal_user":true}
```
- HTTP success with returned JSON identity
- `name` matches generated username

## Step 7: Revoke Lease and Confirm Access Is Removed

In the Vault pod, revoke the lease:

```bash
vault lease revoke <lease_id>
```

On the host, retry API auth with the same credentials:

```bash
curl -i -u "$RMQ_USER:$RMQ_PASS" http://localhost:15672/api/whoami
```

Expected result:
- `401 Unauthorized`

Observed result should show the generated user no longer works after revocation.

## Cleanup

```bash
# Disable the secrets engine in Vault
vault secrets disable rabbitmq

# Exit the vault pod shell first, then stop RabbitMQ
docker stop rabbitmq-vault
docker rm rabbitmq-vault
```

## Notes

- This is a local repro and intentionally uses HTTP for RabbitMQ management API.