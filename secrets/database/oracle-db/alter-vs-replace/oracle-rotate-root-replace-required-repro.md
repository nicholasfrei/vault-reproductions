# Oracle self-managed static-role rotation requiring `REPLACE`

Oracle requires `REPLACE <old-password>` when an account with a password-verification function changes its own password without the `ALTER USER` system privilege. In the customer-confirmed workflow for [VAULT-51145](https://hashicorp.atlassian.net/browse/VAULT-51145), a self-managed static role fails with `ORA-28221: REPLACE not specified` during import rotation and manual `rotate-role` because the plugin's default SQL omits `REPLACE`.

This lab uses `self_managed=true` on the database configuration, with the Oracle username and password supplied on the static role. The candidate plugin takes `{{current_password}}` from that role's `SelfManagedPassword`; opt in through the role's `rotation_statements`. `root_rotation_statements` and `rotate-root` do not apply to this workflow, and other roles retain their own statements.

## Prerequisites

- AWS CLI credentials, Terraform `>= 1.6`, an existing EC2 key pair, and a trusted SSH source CIDR.
- A Vault Enterprise license in your shell as `TF_VAR_vault_license`.
- Access to Oracle's container registry for the Oracle XE image, Oracle Instant Client downloads, and HashiCorp releases.

## 1. Provision the lab

From `secrets/database/oracle-db/alter-vs-replace/terraform/`:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Set `key_name` and `admin_ssh_cidr` in the ignored `terraform.tfvars`. Supply the license from your existing shell variable, then review costs and scope before provisioning:

```bash
export TF_VAR_vault_license="$VAULT_LICENSE"
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
```

Connect using only the generated VM address and your private SSH key:

```bash
LAB_IP=$(terraform output -raw instance_public_ip)
ssh -i "$SSH_PRIVATE_KEY" ec2-user@"$LAB_IP"
sudo -i
```

On the VM, wait for the bootstrap. `READY` means Oracle is open, `VAULT_LAB` authenticated with its initial password, a separate least-privilege control changed its password using `REPLACE`, and Vault accepted the self-managed configuration. The static role is created in the next section; `verify_connection=true` does not authenticate a role on a self-managed configuration.

```bash
sudo cloud-init status --wait
sudo systemctl show oracle-lab-setup.service -p Result -p ExecMainStatus
sudo test -s /root/oracle-lab/READY
```

If setup failed, inspect `journalctl -u oracle-lab-setup.service` and `/var/log/cloud-init-output.log` privately; SQL and plugin errors may contain credentials. The test Oracle accounts have `CREATE SESSION` but not `ALTER USER` or DBA. Their verification profile is `LAB_PROFILE` in PDB `XEPDB1`. Changing user data in a later `terraform apply` can replace the VM; review the plan first. The setup script refuses to reset the test account if the Vault connection already exists.

## 2. Reproduce with the released plugin

Run these on the VM as root. `vault.env` loads the local Vault address and a generated dev token without displaying it:

```bash
source /root/oracle-lab/vault.env
source /etc/oracle-lab/lab.env
```

Confirm the Oracle account's profile and privileges:

```bash
docker exec --user oracle -i oracle-lab sqlplus -L -s / as sysdba <<'SQL'
WHENEVER SQLERROR EXIT FAILURE
ALTER SESSION SET CONTAINER = XEPDB1;
SELECT username, profile FROM dba_users WHERE username = 'VAULT_LAB';
SELECT privilege FROM dba_sys_privs WHERE grantee = 'VAULT_LAB';
SELECT granted_role FROM dba_role_privs WHERE grantee = 'VAULT_LAB';
SELECT limit FROM dba_profiles WHERE profile = 'LAB_PROFILE' AND resource_name = 'PASSWORD_VERIFY_FUNCTION';
EXIT
SQL
```

Expect `LAB_PROFILE`, only `CREATE SESSION`, no granted roles, and `LAB_VERIFY`. Check Vault's configuration, then create the static role with import rotation enabled:

```bash
vault version
vault plugin info -version="$ORACLE_PLUGIN_VERSION" database vault-plugin-database-oracle
vault read oracle-db/config/oracle
vault write oracle-db/static-roles/account-password-rotator \
  db_name=oracle username=VAULT_LAB \
  password=@/root/oracle-lab/role-password \
  rotation_period=90d skip_import_rotation=false
```

The config should show `self_managed=true` with no root username/password. Expected on the lab defaults (Vault `2.1.1+ent`, Oracle plugin `0.14.1+ent`, Oracle XE 21c): role creation fails with `ORA-28221: REPLACE not specified`. This is the customer-reported failure path; the revised Terraform lab has not yet been validated live. Stop if creation succeeds or fails for a different reason.

Skip import rotation to store the role, then reproduce the same failure explicitly:

```bash
vault write oracle-db/static-roles/account-password-rotator \
  db_name=oracle username=VAULT_LAB \
  password=@/root/oracle-lab/role-password \
  rotation_period=90d skip_import_rotation=true
vault read oracle-db/static-roles/account-password-rotator
vault write -f oracle-db/rotate-role/account-password-rotator
```

Expect `ORA-28221` again. `skip_import_rotation` only postpones rotation; it does not fix manual or scheduled rotations. The endpoint takes the Vault role name (`account-password-rotator`), not the Oracle username (`VAULT_LAB`).

## 3. Try a custom plugin (optional)

Build an Enterprise Oracle database plugin binary for Linux AMD64 with its required SDK and Oracle Instant Client SDK. The candidate must include the self-managed `{{current_password}}` changes from [PR #34](https://github.com/hashicorp/vault-plugin-database-oracle-enterprise/pull/34); the original root-only draft is insufficient. This Terraform lab does not build or include the candidate. From your workstation, transfer the test binary to the VM:

```bash
scp -i '<private-key-file>' '<candidate-plugin-binary>' ec2-user@"$LAB_IP":/home/ec2-user/candidate-oracle-plugin
```

On the VM as root, register it under a distinct local version. `register-candidate.sh` packages and signs it with the VM's disposable PGP key for this dev server; it does not change HashiCorp's production trust keys:

```bash
sudo /usr/local/sbin/register-candidate.sh \
  /home/ec2-user/candidate-oracle-plugin 0.14.1+ent.local
source /root/oracle-lab/vault.env
vault write oracle-db/config/oracle \
  plugin_name=vault-plugin-database-oracle \
  plugin_version=0.14.1+ent.local \
  connection_url='{{username}}/{{password}}@127.0.0.1:1521/XEPDB1' \
  allowed_roles=account-password-rotator \
  self_managed=true verify_connection=true
```

For this fresh-lab sequence, both stock-plugin attempts must have failed without changing the password. Delete only the lab's Vault role and recreate it with `REPLACE` to verify import rotation. Deleting a static role removes its Vault configuration, not the Oracle account; the initial password file permits recreation here.

```bash
vault delete oracle-db/static-roles/account-password-rotator
vault write oracle-db/static-roles/account-password-rotator \
  db_name=oracle username=VAULT_LAB \
  password=@/root/oracle-lab/role-password \
  rotation_period=90d skip_import_rotation=false \
  rotation_statements='ALTER USER {{username}} IDENTIFIED BY "{{password}}" REPLACE "{{current_password}}"'
vault read -field=last_vault_rotation oracle-db/static-creds/account-password-rotator
```

Expect successful creation with `last_vault_rotation` populated. After this succeeds, `/root/oracle-lab/role-password` is stale: do not reuse it for role creation or password updates. For an existing role that has already rotated, update only its `rotation_statements` instead of deleting/recreating it with the initial password.

Verify subsequent rotations, including one after clearing the cached database connection. The one-second pauses avoid Oracle's documented password-reuse errors when resetting a password multiple times within one second:

```bash
sleep 1
vault write -f oracle-db/rotate-role/account-password-rotator
vault write -f oracle-db/reset/oracle
sleep 1
vault write -f oracle-db/rotate-role/account-password-rotator
vault read -field=last_vault_rotation oracle-db/static-creds/account-password-rotator
```

Expect both rotations to succeed and `last_vault_rotation` to advance. The rotation after `reset` must authenticate as `VAULT_LAB` with its updated password.

These are expected results, not a recorded self-managed integration-test pass. Previous root-rotation tests do not validate this path. The Oracle verification function controls the `REPLACE` requirement; Vault's optional `password_policy` controls generated passwords and is a separate setting.

## Cleanup

From the Terraform directory on your workstation, confirm the workspace/target and destroy only the resources created by this module:

```bash
terraform destroy
```

The pre-existing EC2 key pair is not managed or deleted by this module. Terraform state and EC2 user data contain the Enterprise license, including after `destroy` in any retained state backups; protect or dispose of them under your team's secret-handling policy. The generated Vault root token and initial Oracle role password stay on the encrypted VM disk and are not Terraform inputs.

## References

- [Oracle `ALTER USER`](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/ALTER-USER.html)
- [Vault Oracle plugin requirements](https://developer.hashicorp.com/vault/docs/secrets/databases/oracle)
- [Vault database static-role API](https://developer.hashicorp.com/vault/api-docs/secret/databases#create-static-role)
- [VAULT-51145](https://hashicorp.atlassian.net/browse/VAULT-51145) and [Oracle plugin PR #34](https://github.com/hashicorp/vault-plugin-database-oracle-enterprise/pull/34)
- [Neighboring Oracle Terraform lab](../terraform/README.md)
