# Azure Key Vault Auto-Unseal Runbook (Linux VM + Vault Enterprise)

This runbook sets up `azurekeyvault` auto-unseal using an Azure Linux VM. Please follow each step carefully, and refer to the official Vault documentation for more details on the Azure Key Vault seal configuration if you run into any issues.

## Overview

Goal:
- Create an Azure Key Vault and an RSA key for Vault to use during unseal.
- Create an App Registration with a client secret scoped to that key vault.
- Configure Vault with those credentials in the `azurekeyvault` seal stanza.
- Validate that Vault auto-unseals after restart.

What this runbook uses:
- Ubuntu 22.04 LTS on Azure
- Single-node `raft` storage
- A manually created Azure Key Vault, key, App Registration, and client secret

This runbook uses Azure CLI examples. If you prefer the Azure Portal, create the same resources manually and substitute the resulting values into the seal stanza.

## Preconditions

Before starting, ensure you have:
- Azure permissions to create Resource Groups, Key Vaults, App Registrations, and role assignments.
- Azure CLI installed and authenticated on your workstation (`az login`).
- A running Ubuntu 22.04 Azure VM that you can reach over SSH.
- The VM's public IP address.
- Vault Enterprise license text (`.hclic` content).
- A chosen Vault version (`+ent` build), for example `1.21.0`.

## Step 1: Set Environment Variables

Use this step on your workstation to define the names used throughout the runbook.

```bash
export AZURE_SUBSCRIPTION_ID=<SUBSCRIPTION_ID>
export AZURE_TENANT_ID=<TENANT_ID>
export AZURE_REGION=eastus
export VAULT_VERSION=1.21.0

export RESOURCE_GROUP=vault-unseal-rg
export KEY_VAULT_NAME=vault-unseal-kv
export KEY_NAME=vault-unseal-key
export APP_REG_NAME=vault-unseal-app

export VM_PUBLIC_IP=<EXISTING_VM_PUBLIC_IP>
```

## Step 2: Create a Resource Group

Use this step to create a resource group that contains all Vault-related Azure resources.

```bash
az group create \
  --name "$RESOURCE_GROUP" \
  --location "$AZURE_REGION"
```

Success looks like:
```text
The output shows `"provisioningState": "Succeeded"`.
```

## Step 3: Create the Azure Key Vault

Use this step to create the key vault with RBAC-based authorization enabled.

```bash
az keyvault create \
  --name "$KEY_VAULT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$AZURE_REGION" \
  --sku standard \
  --enable-rbac-authorization true
```

Success looks like:
```text
The output shows `"provisioningState": "Succeeded"` and `"enableRbacAuthorization": true`.
```

## Step 4: Create the Unseal Key

Use this step to create an RSA key inside the vault that Vault will use to wrap and unwrap the root key.

```bash
az keyvault key create \
  --vault-name "$KEY_VAULT_NAME" \
  --name "$KEY_NAME" \
  --kty RSA \
  --size 2048
```

Success looks like:
```text
The output contains a `"key"` object with an `"n"` (modulus) field and `"key_ops"` listing `wrapKey` and `unwrapKey`.
```

## Step 5: Create an App Registration and Service Principal

Use this step to create the identity that Vault will authenticate as when accessing the key vault.

```bash
APP_ID=$(az ad app create \
  --display-name "$APP_REG_NAME" \
  --query appId --output tsv)

az ad sp create --id "$APP_ID"

SERVICE_PRINCIPAL_ID=$(az ad sp show \
  --id "$APP_ID" \
  --query id --output tsv)

printf 'APP_ID=%s\nSERVICE_PRINCIPAL_ID=%s\n' "$APP_ID" "$SERVICE_PRINCIPAL_ID"
```

Success looks like:
```text
APP_ID and SERVICE_PRINCIPAL_ID are both populated with non-empty UUID values.
```

## Step 6: Create a Client Secret on the App Registration

Use this step to generate the credential Vault will use to authenticate.

**Important:** The secret value is only shown once. Copy it before continuing.

```bash
CLIENT_SECRET=$(az ad app credential reset \
  --id "$APP_ID" \
  --display-name "vault-unseal-secret" \
  --years 1 \
  --append \
  --query password --output tsv)

printf 'CLIENT_SECRET=%s\n' "$CLIENT_SECRET"
```

Success looks like:
```text
CLIENT_SECRET is a non-empty string. Store this value securely; you will need it in Step 11.
```

## Step 7: Assign the Key Vault Crypto User Role to the Service Principal

Use this step to grant the App Registration the minimum permissions needed for Vault unseal operations.

```bash
KEY_VAULT_RESOURCE_ID=$(az keyvault show \
  --name "$KEY_VAULT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query id --output tsv)

az role assignment create \
  --role "Key Vault Crypto User" \
  --assignee-object-id "$SERVICE_PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --scope "$KEY_VAULT_RESOURCE_ID"
```

Success looks like:
```text
The output contains `"principalId"` matching `SERVICE_PRINCIPAL_ID` and `"roleDefinitionName": "Key Vault Crypto User"`.
```

## Step 8: Connect to the VM

Use this step to SSH into the Linux VM where Vault will be installed.

```bash
ssh azureuser@"$VM_PUBLIC_IP"
```

## Step 9: Install Host Dependencies

Use this step to prepare the host with required tooling.

```bash
sudo apt-get update -y
sudo apt-get install -y unzip jq wget
```

Success looks like:
```text
All dependency packages install without apt errors.
```

## Step 10: Download and Install Vault Enterprise Binary

Use this step to install Vault Enterprise to `/usr/local/bin`.

```bash
cd /tmp

wget "https://releases.hashicorp.com/vault/${VAULT_VERSION}+ent/vault_${VAULT_VERSION}+ent_linux_amd64.zip"
unzip "vault_${VAULT_VERSION}+ent_linux_amd64.zip"

sudo mv vault /usr/local/bin/vault
sudo chmod 0755 /usr/local/bin/vault
vault version
```

Success looks like:
```text
Vault v1.21.0+ent
```

## Step 11: Create Vault User, Directories, and Permissions

Use this step to create runtime paths used by `raft`, config, and logs.

```bash
sudo useradd --system --home /etc/vault.d --shell /bin/false vault || true

sudo mkdir -p /etc/vault.d
sudo mkdir -p /opt/vault/data
sudo mkdir -p /var/log/vault

sudo chown -R vault:vault /etc/vault.d /opt/vault /var/log/vault
sudo chmod 0750 /etc/vault.d
sudo chmod 0750 /opt/vault/data
```

Success looks like:
```text
Directories exist and are owned by user/group `vault`.
```

## Step 12: Install Vault Enterprise License on the Host

Use this step to place the license where only privileged users can read it.

```bash
sudo vi /etc/vault.d/vault.hclic
sudo chown root:vault /etc/vault.d/vault.hclic
sudo chmod 0640 /etc/vault.d/vault.hclic
```

## Step 13: Create the Vault Environment File

Use this step to expose only the values Vault needs at startup.

```bash
sudo tee /etc/vault.d/vault.env > /dev/null <<'EOF'
VAULT_LICENSE_PATH=/etc/vault.d/vault.hclic
EOF

sudo chown root:vault /etc/vault.d/vault.env
sudo chmod 0640 /etc/vault.d/vault.env
```

## Step 14: Create the Vault Server Configuration

Use this step to configure the listener, storage, and the `azurekeyvault` seal stanza.

Replace the placeholder values with the outputs from Steps 1, 5, and 6. The config file is owned by `root:vault` and mode `0640` to protect the client secret at rest.

```bash
sudo tee /etc/vault.d/vault.hcl > /dev/null <<'EOF'
ui = true
disable_mlock = true

api_addr = "http://127.0.0.1:8200"
cluster_addr = "http://127.0.0.1:8201"

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 1
}

storage "raft" {
  path    = "/opt/vault/data"
  node_id = "vault-azure-1"
}

seal "azurekeyvault" {
  tenant_id     = "<AZURE_TENANT_ID>"
  client_id     = "<APP_ID>"
  client_secret = "<CLIENT_SECRET>"
  vault_name    = "<KEY_VAULT_NAME>"
  key_name      = "<KEY_NAME>"
}
EOF

sudo chown root:vault /etc/vault.d/vault.hcl
sudo chmod 0640 /etc/vault.d/vault.hcl
```

Success looks like:
```text
Vault is configured to authenticate to Azure Key Vault using the App Registration client secret.
```

## Step 15: Create and Start the Vault systemd Service

Use this step to run Vault as a managed service.

```bash
sudo tee /etc/systemd/system/vault.service > /dev/null <<'EOF'
[Unit]
Description=HashiCorp Vault
Documentation=https://developer.hashicorp.com/vault/docs
After=network-online.target
Wants=network-online.target

[Service]
User=vault
Group=vault
ExecStart=/usr/local/bin/vault server -config=/etc/vault.d/vault.hcl
ExecReload=/bin/kill --signal HUP $MAINPID
KillMode=process
KillSignal=SIGINT
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
EnvironmentFile=/etc/vault.d/vault.env

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable vault
sudo systemctl start vault
sudo systemctl status vault --no-pager
```

If startup fails, check logs:

```bash
sudo journalctl -u vault -n 100 --no-pager
```

Success looks like:
```text
The Vault service starts and the status shows `active (running)`.
```

## Step 16: Initialize Vault Once and Validate Health

Use this step to initialize the new cluster and confirm it is serving requests.

```bash
export VAULT_ADDR=http://127.0.0.1:8200
vault status

vault operator init > /tmp/vault-init.txt
cat /tmp/vault-init.txt
```

Success looks like:
```text
`vault status` shows `Initialized: false` before init and `Initialized: true` after init.
`vault status` shows `Sealed: false` after init completes.
```

## Step 17: Restart Vault and Confirm Auto-Unseal

Use this step to verify Azure Key Vault-based unseal after process restart.

```bash
sudo systemctl restart vault
sleep 2
vault status
```

Success looks like:
```text
`Sealed: false` without running `vault operator unseal`.
```

## Cleanup

Warning: The following commands are destructive and remove Azure resources and local Vault data.

On the VM (stop the Vault service):

```bash
sudo systemctl stop vault
```

On your workstation:

```bash
az role assignment delete \
  --role "Key Vault Crypto User" \
  --assignee-object-id "$SERVICE_PRINCIPAL_ID" \
  --scope "$KEY_VAULT_RESOURCE_ID"

az ad app delete --id "$APP_ID"

az group delete \
  --name "$RESOURCE_GROUP" \
  --yes --no-wait
```

Note: `az group delete` removes the Key Vault and all keys inside it. Soft-delete is enabled by default on Azure Key Vaults; to fully purge the vault after deletion, run:

```bash
az keyvault purge --name "$KEY_VAULT_NAME" --location "$AZURE_REGION"
```

## Conclusion

This runbook creates an Azure Key Vault and RSA key, creates an App Registration with a client secret, assigns the Key Vault Crypto User role to the service principal, then installs Vault Enterprise on Ubuntu 22.04 and validates Azure Key Vault-based auto-unseal after restart.

## References

- https://developer.hashicorp.com/vault/docs/configuration/seal/azurekeyvault
- https://developer.hashicorp.com/vault/tutorials/auto-unseal/autounseal-azure-keyvault
