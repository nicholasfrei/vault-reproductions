# Oracle root rotation requiring `REPLACE`

Oracle requires `REPLACE <old-password>` when an account with a password verification function changes its own password without `ALTER USER` permissions. The official released enterprise Oracle plugin does not pass in the "old-password" variable, so the default root rotation fails with `ORA-28221`. This lab provisions a restricted Oracle account and Vault connection so an engineer can reproduce the failure, then try a locally built plugin with `{{current_password}}`.

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
ssh -i $SSH_PRIVATE_KEY ec2-user@"$LAB_IP"
sudo -i
```

On the VM, wait for the bootstrap. `READY` means Oracle is open, the restricted user exists, a separate least-privilege control changed its password using `REPLACE`, and Vault verified its stock-plugin connection:

```bash
sudo cloud-init status --wait
sudo systemctl show oracle-lab-setup.service -p Result -p ExecMainStatus
sudo test -s /root/oracle-lab/READY
```

If setup failed, inspect `journalctl -u oracle-lab-setup.service` and `/var/log/cloud-init-output.log` privately; SQL and plugin errors may contain credentials. The test Oracle accounts have `CREATE SESSION` but not `ALTER USER` or DBA. Their verification profile is `LAB_PROFILE` in PDB `XEPDB1`. Changing user data in a later `terraform apply` can replace the VM; review the plan first.

## 2. Reproduce with the released plugin

Run these on the VM as root. `vault.env` loads the local Vault address and a generated dev token without displaying it:

```bash
source /root/oracle-lab/vault.env
```

Run the required oracle commands: 

```bash
docker exec --user oracle -i oracle-lab sqlplus -s / as sysdba <<'SQL'
ALTER SESSION SET CONTAINER = XEPDB1;
SELECT username, profile FROM dba_users WHERE username = 'VAULT_LAB';
SELECT privilege FROM dba_sys_privs WHERE grantee = 'VAULT_LAB';
EXIT
SQL
```

Check the Vault plugin and configuration, then rotate the root credentials:

```bash
vault version
vault plugin info -version=0.14.1+ent database vault-plugin-database-oracle
vault read oracle-db/config/oracle
vault write -f oracle-db/rotate-root/oracle
```

Expected for default Vault `2.1.1+ent` / Oracle plugin `0.14.1+ent` on Oracle XE 21c: HTTP 500 with `ORA-28221: REPLACE not specified`.

## 3. Try a custom plugin (optional)

Build an Enterprise Oracle database plugin binary for Linux AMD64 with its required SDK and Oracle Instant Client SDK. This Terraform lab does not build or include a patched plugin. Transfer a disposable test binary privately to the VM; it must not contain a license or credentials:

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
  root_rotation_statements='ALTER USER {{username}} IDENTIFIED BY "{{password}}" REPLACE "{{current_password}}"'
vault write -f oracle-db/rotate-root/oracle
vault write -f oracle-db/reset/oracle
vault write -f oracle-db/rotate-root/oracle
```

On a plugin implementing `{{current_password}}`, both rotations should succeed without `ALTER USER`; the second exercises the refreshed connection password. An unpatched plugin cannot expand this variable. Never paste `/root/oracle-lab/root-password` back into the Vault configuration after a successful rotation: that bootstrap password is then stale. A local test of the candidate on Vault `2.1.1+ent` and Oracle Free passed consecutive rotations, account guards, redaction, and WAL recovery; the Terraform/Oracle XE environment still requires live validation.

## Cleanup

From the Terraform directory on your workstation, confirm the workspace/target and destroy only the resources created by this module:

```bash
terraform destroy
```

The pre-existing EC2 key pair is not managed or deleted by this module. Terraform state and EC2 user data contain the Enterprise license, including after `destroy` in any retained state backups; protect or dispose of them under your team's secret-handling policy. The generated root token and Oracle account password stay on the encrypted VM disk and are not Terraform inputs.

## References

- [Oracle `ALTER USER`](https://docs.oracle.com/en/database/oracle/oracle-database/19/sqlrf/ALTER-USER.html)
- [Vault Oracle plugin requirements](https://developer.hashicorp.com/vault/docs/secrets/databases/oracle)
- [Neighboring Oracle Terraform lab](../terraform/README.md)
