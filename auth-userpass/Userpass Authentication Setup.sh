#!/bin/bash
# Userpass Authentication Setup Script
# 
# This script demonstrates:
# - Enabling the userpass authentication method
# - Creating a policy for users
# - Creating multiple users with userpass auth
# - Testing user login and token management
#
# Prerequisites:
# - Vault server running and accessible
# - VAULT_ADDR and VAULT_TOKEN environment variables set
# - Appropriate permissions to enable auth methods and create policies

# Set namespace (optional - comment out if not using namespaces)
export VAULT_NAMESPACE="test"

# Enable userpass authentication method
echo "Enabling userpass authentication method..."
vault auth enable userpass

# Create an admin policy
# This policy allows users to:
# - Create/update/delete/read secrets under kv-test/*
# - Read and list authentication methods
echo "Writing admin policy..."
vault policy write admin -<<EOF
path "sys/mounts/kv-test/*" {
  capabilities = ["create", "update", "delete", "read"]
}
path "sys/auth" {
  capabilities = ["read", "list"]
}
EOF

# Create 10 test users with userpass authentication
echo ""
echo "Creating test users..."
for i in $(seq 1 10); do
  echo "Creating user-2-${i}..."
  vault write auth/userpass/users/user-2-$i \
      password="password-$i" \
      policies="admin"
done

echo ""
echo "Successfully created 10 users (user-2-1 through user-2-10)."
echo ""

# Test each user by logging in and verifying access
echo "Testing user logins..."
for i in $(seq 1 10); do
    echo "--- Testing as user-2-$i ---"
    
    # Login with userpass credentials
    echo "Logging in as user-2-$i..."
    vault login -method=userpass username="user-2-$i" password="password-$i"
    
    # Optional: Test enabling/disabling secrets engines
    # Uncomment the following lines to test secrets engine operations
    #
    # TEST_PATH="kv-test/user-2-${i}-secrets"
    # echo "Enabling secrets at ${TEST_PATH} as user-2-$i..."
    # vault secrets enable -path=$TEST_PATH kv-v2
    # 
    # echo "Disabling secrets at ${TEST_PATH} as user-2-$i..."
    # vault secrets disable $TEST_PATH

    # Verify the user can list auth methods (per policy)
    echo "Listing auth methods..."
    vault auth list
    
    # Revoke the current token (logout)
    echo "Revoking token for user-2-$i..."
    vault token revoke -self
    
    echo "✓ Test completed for user-2-$i"
    echo "--------------------------"
    echo ""
done

echo "All user tests completed successfully!"
