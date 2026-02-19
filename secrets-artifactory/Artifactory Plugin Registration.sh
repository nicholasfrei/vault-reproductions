#!/bin/bash

# ==============================================================================
# Artifactory Secrets Plugin Reproduction Script
# 
# Purpose: Reproduces the Artifactory plugin setup on Amazon Linux, fixing the 
# "cannot execute files outside of configured plugin directory" error.
# ==============================================================================

# 1. Configuration - UPDATE THESE
export VAULT_LICENSE="<your-license-key>"
export PLUGIN_VER="1.8.8"
export PLUGIN_SHA="c31db283746dff036a808f548e790291412e24cd20aa17969c57aaf1ab3022a0"

# 2. Install Vault Enterprise
wget https://releases.hashicorp.com/vault/1.20.2+ent/vault_1.20.2+ent_linux_amd64.zip
unzip vault_1.20.2+ent_linux_amd64.zip
sudo mv vault /usr/local/bin/
vault --version

# 3. Setup Plugin Directory
sudo mkdir -p /etc/vault.d/plugins

# 4. Download and Install Artifactory Plugin
# Note: Downloading the binary directly from GitHub
wget https://github.com/jfrog/vault-plugin-secrets-artifactory/releases/download/v${PLUGIN_VER}/artifactory-secrets-plugin_${PLUGIN_VER}_linux_amd64

# Move binary to the root of the plugin directory (FLATTENED STRUCTURE)
# This fixes the "cannot execute files outside of directory" error.
sudo mv artifactory-secrets-plugin_${PLUGIN_VER}_linux_amd64 /etc/vault.d/plugins/artifactory-plugin-v${PLUGIN_VER}

# Set permissions
sudo chmod +x /etc/vault.d/plugins/artifactory-plugin-v${PLUGIN_VER}
sudo chown ec2-user:ec2-user -R /etc/vault.d/plugins/

# 5. Start Vault Server in Background
# Using sudo -E to pass VAULT_LICENSE and -dev-no-store-config for Enterprise dev mode
sudo touch /var/log/vault.log
sudo -E nohup vault server -dev \
    -dev-plugin-dir=/etc/vault.d/plugins \
    -dev-no-store-config > /var/log/vault.log 2>&1 &

sleep 5 # Wait for startup

# 6. Extract Root Token and Setup Environment
ROOT_TOKEN=$(grep "Root Token" /var/log/vault.log | cut -d' ' -f3)
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN=$ROOT_TOKEN

echo "Vault Started. Root Token: $ROOT_TOKEN"

# 7. Register Plugin in Catalog
# The 'command' field now points to the flattened binary name.
vault write sys/plugins/catalog/secret/artifactory \
    command="artifactory-plugin-v${PLUGIN_VER}" \
    version="${PLUGIN_VER}" \
    sha256="${PLUGIN_SHA}"

# 8. Enable the Secrets Engine
vault secrets enable -path="artifactory" -plugin-name="artifactory" plugin

# 9. Verify
vault plugin list --detailed | grep artifactory
vault secrets list