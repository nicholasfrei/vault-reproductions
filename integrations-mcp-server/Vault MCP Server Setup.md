# Vault MCP Server Setup

This guide connects `vault-mcp-server` to your existing Kubernetes Vault cluster for use with GitHub Copilot in VS Code.

The MCP server runs as a local binary in stdio mode. It needs a reachable `VAULT_ADDR` and a valid `VAULT_TOKEN`. The port-forward handles the first, and the steps below handle the second.

> Security note: The MCP server passes secrets to the LLM in context. Only use it with trusted MCP clients and models.

## Prerequisites

- `kubectl` access to your Kubernetes Vault cluster
- `vault` CLI available locally
- VS Code with GitHub Copilot

## Step 1: Install vault-mcp-server

```bash
curl -O https://releases.hashicorp.com/vault-mcp-server/0.2.0/vault-mcp-server_0.2.0_darwin_arm64.zip
unzip vault-mcp-server_0.2.0_darwin_arm64.zip
chmod +x vault-mcp-server
sudo mv vault-mcp-server /usr/local/bin/
vault-mcp-server --version
```

## Step 2: Expose Vault Locally via Port-Forward

Keep this running in a dedicated terminal for the duration of your session:

```bash
kubectl port-forward svc/vault -n vault 8200:8200
```

Confirm Vault is reachable:

```bash
export VAULT_ADDR='http://127.0.0.1:8200'
vault status
```

## Step 3: Create a Vault Policy and Token

Apply the included policy, then create a scoped token:

```bash
vault policy write vault-mcp vault-mcp-policy.hcl

vault token create \
  -policy=vault-mcp \
  -ttl=8h \
  -display-name="vault-mcp-server"
```

Copy the `token` value from the output.

If using Vault Enterprise with namespaces, set this before running the above:

```bash
export VAULT_NAMESPACE=admin
```

## Step 4: Configure VS Code

In your workspace root, create `.vscode/mcp.json`. VS Code will prompt you for the token on first use and store it securely — nothing needs to be hardcoded.

```json
{
  "inputs": [
    {
      "type": "promptString",
      "id": "vault_token",
      "description": "Vault Token",
      "password": true
    },
    {
      "type": "promptString",
      "id": "vault_namespace",
      "description": "Vault Namespace (leave blank if not using namespaces)",
      "password": false
    }
  ],
  "servers": {
    "vault-mcp-server": {
      "command": "vault-mcp-server",
      "args": ["stdio"],
      "env": {
        "VAULT_ADDR": "http://127.0.0.1:8200",
        "VAULT_TOKEN": "${input:vault_token}",
        "VAULT_NAMESPACE": "${input:vault_namespace}"
      }
    }
  }
}
```

Reload the window or open the Command Palette and run `MCP: List Servers` to pick up the new config. Copilot Chat will now have access to Vault tools.

## Step 5: Verify

In Copilot Chat, try:

```
List all secret mounts in Vault.
```

Copilot should call the `list_mounts` tool and return the results from your cluster.

## Troubleshooting

### Binary not found

```bash
which vault-mcp-server
```

If nothing is returned, confirm `/usr/local/bin` is in your `PATH` or move the binary somewhere that is.

### Connection refused at 127.0.0.1:8200

The port-forward dropped. Re-run:

```bash
kubectl port-forward svc/vault -n vault 8200:8200
```

### Token expired or permission denied

Re-create a token from Step 3, then reload the MCP server in VS Code via `MCP: List Servers` so VS Code prompts for the new token.

To check the current token before re-creating:

```bash
vault token lookup
```

### Tools not appearing in Copilot Chat

Open the Command Palette, run `MCP: List Servers`, and restart the `vault-mcp-server` entry. Confirm `.vscode/mcp.json` is valid JSON and saved.

## Notes

- The port-forward must stay active while the MCP server is in use.
- The `vault-mcp-policy.hcl` in this directory defines what the token can access. Adjust the mount paths (`secret/`, `pki/`) if your cluster uses different ones.
- Tokens created with the `vault-mcp` policy cannot manage auth methods, write policies, or perform admin operations.
