# Oracle on EC2: reusable integration setup

Provision a healthy Oracle/Vault baseline with Terraform, then use it for role browsing, credential generation, rotation, or a separately configured issue investigation.

- Purpose: reusable setup.
- Starts from: an AWS account, existing EC2 SSH key pair, Vault Enterprise license, and workstation Terraform/SSH tools.
- Runs on: one Amazon Linux 2023 x86-64 EC2 VM by default, or three when explicitly selected; Terraform and SSH run on the workstation.
- Creates by default: one Oracle XE database, one Vault management user, 100 static Oracle users with 100 Vault static roles, and 100 Vault dynamic-role definitions.
- Leaves ready: a persistent one- or three-voter Vault Raft cluster with AWS KMS auto-unseal, one Oracle container/volume on node 1, and Instant Client Basic `19.32` plus the selected Enterprise Oracle plugin on every Vault node.
- Verification status: static checks only; this new EC2 workflow has not been run end-to-end.

“Golden baseline” here means a repeatable provisioned environment. Terraform creates the VM and configures it on first boot; it does not bake an AMI. Dynamic users are created when credentials are requested. Bootstrap issues and revokes one credential per dynamic role for verification, leaving no verification leases behind.

## Prerequisites

- Terraform `>= 1.7`, AWS CLI, SSH, and an existing key pair in the chosen AWS region.
- AWS permissions for EC2, VPC/networking, IAM instance profiles/role policies, `iam:PassRole`, and KMS. Use a unique `name_prefix` for each concurrent lab.
- A trusted SSH source CIDR, accepted from `/24` through `/32`; normally use your workstation's current egress address with `/32`.
- `VAULT_LICENSE` in the workstation shell. The license enters Terraform state and EC2 user data; keep state, backups, and variables private.
- Download access from the VM to Amazon Linux repositories, Oracle's container registry and Instant Client downloads, and HashiCorp release services. Confirm the Oracle image terms/access for your account before provisioning.

Defaults are one `t3.large` (8 GiB RAM), an encrypted 80-GiB disk per node, Vault `2.1.1+ent`, Oracle plugin `0.14.1+ent`, and Oracle XE `21.3.0-xe`. The root validates an x86-64 instance with at least 8 GiB RAM. Three-node mode creates three such instances in one subnet/AZ. Larger populations may need more capacity and time; this is not a throughput benchmark.

This baseline targets Vault `1.20+`; choose the plugin using the [Oracle compatibility guidance](https://developer.hashicorp.com/vault/docs/secrets/databases/oracle#oracle-plugin-compatibility). Every host receives the complete official plugin archive; registration is performed once in the shared catalog. Version inputs do not imply that every combination works. Custom candidate plugins and older Vault installation paths require their own setup.

## 1. Configure the baseline

From the repository root, on your workstation:

```bash
cd secrets/database/oracle-db/lab/terraform
umask 077
cp terraform.tfvars.example terraform.tfvars
```

Edit the ignored `terraform.tfvars`: set `aws_region`, optional `aws_profile`, `name_prefix`, `key_name`, and `admin_ssh_cidr`. Confirm the versions and population:

```hcl
vault_version                  = "2.1.1+ent"
oracle_plugin_version          = "0.14.1+ent"
static_role_count              = 100
dynamic_role_count             = 100
static_rotation_period_seconds = 86400
```

Leave `vault_node_count` unset for one Vault node. To create three Raft voters, add this before provisioning:

```hcl
vault_node_count = 3
```

Only `1` and `3` are accepted. Node 1 initializes Vault and hosts Oracle; the other nodes join that cluster with `retry_join` and the shared KMS seal. The 100 static and 100 dynamic-role counts are cluster-wide, not per node. Three-node mode adds Vault quorum/leadership testing; Oracle remains a single database on node 1.

Role counts are independent integers from 1 to 1000. For a small setup check, use two of each. Static roles rotate every 24 hours by default; the configurable minimum is 60 seconds. Changing versions, role counts, or other rendered bootstrap inputs replaces the affected VMs on the next apply rather than reconfiguring a running experiment.

`lab/terraform/` is the canonical golden-baseline root for both topologies. Changing the topology replaces the baseline data; it is not an online Raft scaling procedure. Export evidence and rebuild the whole lab when switching between one and three nodes.

Supply the license and inspect your intended AWS identity. If using `aws_profile` in Terraform, select the same profile for the AWS CLI:

```bash
# When using a named profile:
export AWS_PROFILE='<aws-profile>'
aws sts get-caller-identity

: "${VAULT_LICENSE:?Set VAULT_LICENSE in this shell}"
export TF_VAR_vault_license="$VAULT_LICENSE"
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan
terraform apply
```

Omit the profile export when using the default credential chain. Terraform creates a dedicated VPC/subnet, the requested VMs, and a shared KMS key/instance identity. The security group permits administrator SSH and private lab-member access to Vault API `8200`, cluster/forwarding `8201`, and Oracle `1521`. Application ports have no public ingress rule. Oracle is published on node 1's loopback/private addresses; all Vault nodes use its private address. The public AMI lookup uses Amazon-owned AL2023 images; set `ami_id` to pin an image for version comparisons.

## 2. Wait for the healthy integration

On your workstation, set the private-key path for the existing EC2 key pair and connect:

```bash
export SSH_PRIVATE_KEY='<private-key-file>'
LAB_IP=$(terraform output -raw instance_public_ip)
terraform output ami_id
terraform output vault_nodes
ssh -i "$SSH_PRIVATE_KEY" ec2-user@"$LAB_IP"
```

`instance_public_ip` always identifies node 1. On that VM:

```bash
sudo cloud-init status --wait
sudo journalctl -fu oracle-baseline-configure.service
```

Oracle initialization can take tens of minutes. Terraform apply and cloud-init completion establish infrastructure/installation, not completed role provisioning. The configure service separately waits for `XEPDB1`, creates the users/roles, and checks their behavior. Exit the log follower with `Ctrl+C`, then inspect:

```bash
sudo systemctl show oracle-baseline-configure.service -p Result -p ExecMainStatus
sudo test -s /root/oracle-baseline/READY
sudo jq . /root/oracle-baseline/verification.json
```

Success requires service result `success`, exit status `0`, a `READY` file, and a verification report matching your requested versions/counts. The report records:

- The requested one or three unsealed voters, with matching node IDs in one Raft cluster.
- Successful Oracle authentication for every static role.
- A changed password/rotation timestamp and successful login after manually rotating `static-0001`.
- Issuance, Oracle authentication, revocation, and database-user removal for every dynamic role.

Scheduled rotation is configured; the bootstrap check proves import/manual rotation, not a completed 24-hour scheduled cycle. It checks membership and current credential behavior; it does not force leadership changes. Generated credentials and recovery material remain root-only on node 1's encrypted disk. Followers wait for join/auto-unseal and write `/root/oracle-baseline/NODE_READY`; they never initialize a separate cluster or create a separate population.

## 3. Use the baseline

On node 1, enter the root shell and load its private Vault credentials:

```bash
sudo -i
source /root/oracle-baseline/admin.env
vault status
vault read oracle-db/config/oracle
vault list oracle-db/static-roles
vault list oracle-db/roles
vault operator raft list-peers
```

The stable handoff is:

| Component | Location or name |
| --- | --- |
| Vault | Local CLI at `http://127.0.0.1:8200` on each node, systemd unit `vault`; private API/cluster addresses for peer traffic |
| Oracle | On node 1: Docker container `oracle-db`, service `XEPDB1`, port `1521` on loopback/private address |
| Database management user | `VAULT_MANAGER`; user-management/session-disconnection grants, no DBA role |
| Vault mount / connection | `oracle-db/` / `oracle` |
| Static roles | `static-0001` through `static-0100` at defaults |
| Static Oracle users | `LAB_STATIC_0001` through `LAB_STATIC_0100`; `CREATE SESSION` |
| Dynamic roles | `dynamic-0001` through `dynamic-0100` at defaults |
| Dynamic credentials | One new Oracle user per read; TTL `1h`, max TTL `24h` |
| Generated files | `/root/oracle-baseline/` on each node; admin credentials and cluster verification report on node 1 only |
| Persisted data | `/opt/vault/data/` on each node; Docker volume `oracle-baseline-data` on node 1 |

Generate credentials without displaying them, then revoke just that dynamic lease:

```bash
umask 077
work=$(mktemp -d /root/oracle-baseline/credentials.XXXXXX)
vault read -format=json oracle-db/static-creds/static-0001 > "$work/static.json"
vault read -format=json oracle-db/creds/dynamic-0001 > "$work/dynamic.json"
# Use these private files for your test; do not commit their contents.
vault lease revoke "$(jq -er '.lease_id' "$work/dynamic.json")"
rm -rf "$work"
```

For the Vault UI, open a second workstation terminal:

```bash
ssh -i "$SSH_PRIVATE_KEY" -N -L 18200:127.0.0.1:8200 ec2-user@"$LAB_IP"
```

Open `http://127.0.0.1:18200` in your browser. Use the lab's private authentication material only in this disposable environment. Close the SSH tunnel when finished.

For an issue investigation, add its specific accounts, profile, connection, and trigger after this healthy checkpoint. In particular, a self-managed REPLACE test needs restricted accounts and a separate `self_managed=true` connection; reusing `VAULT_MANAGER` would test a different privilege path. See the [Oracle index's reuse boundary](README.md#reuse-boundary) before following an existing issue fixture.

### Optional leadership-change check for three-node labs

Keep node 1 and its Oracle container running. From the authenticated node-1 shell, first confirm three voters, then request a leader change:

```bash
vault operator raft list-peers
LEADER_IP=$(vault operator raft list-peers -format=json | \
  jq -er '.data.config.servers[] | select(.leader) | .address | split(":")[0]')
VAULT_ADDR="http://$LEADER_IP:8200" vault operator step-down
vault operator raft list-peers
```

Leadership changes briefly interrupt requests. Wait for the election and confirm a different node is leader, then run `sudo /usr/local/sbin/oracle-baseline-verify` on node 1. Its requests can forward to the new active node; successful credential/rotation checks now exercise that node's Oracle plugin installation. Record the leader identity with the result. This is an optional experiment, not a failover result observed during authoring.

## Reruns and troubleshooting

- A repeated Terraform apply with unchanged inputs does not repopulate the database or undo scenario changes. Reboot preserves Vault/Oracle data and uses KMS auto-unseal; the configure service does not run automatically on reboot. In three-node mode, preserve quorum during restarts. Stopping the entire node-1 VM also stops the only Oracle database, so it is a database outage as well as a Vault-node outage.
- For a failed initial configuration, inspect `journalctl -u oracle-baseline-configure`, `journalctl -u vault`, and `/root/oracle-baseline/sql-setup.log` privately. After repairing the cause, run `sudo systemctl restart oracle-baseline-configure`. It retains saved initialization material and existing account passwords/roles. It is a partial-setup resume, not a reconciliation tool for a modified scenario.
- For an installation failure, inspect `/var/log/cloud-init-output.log`. Repair the failed prerequisite before rerunning `sudo /usr/local/sbin/oracle-baseline-bootstrap`; it refuses a completed bootstrap.
- To recheck the original baseline, run `sudo /usr/local/sbin/oracle-baseline-verify`. This rotates `static-0001` and issues/revokes one credential per dynamic role. Run it before fault injection or after restoring the baseline. The check invalidates `READY` until it passes. Failed/interrupted lease-cleanup details are retained privately under `/root/oracle-baseline/verify.*/`; revoke the lease recorded in `unrevoked-lease` and remove that marker before retrying.
- Oracle registry or release-download failures need working VM download access. An unavailable/incompatible Vault/plugin pair stops bootstrap; it does not silently fall back to another version.

For a clean rebuild or topology change, export evidence, follow Cleanup for the entire lab, update the inputs, and run `terraform apply` again. Do not replace just node 1 in a populated three-node lab: its bootstrap initializes a new cluster and a new Oracle database. Rebuilding permanently removes the old disks, Vault/Oracle state, and local evidence; recovery is provisioning a new baseline. Refresh `LAB_IP` afterward. Test another version using fresh state/data rather than downgrading an existing Vault data directory.

## Cleanup

From `secrets/database/oracle-db/lab/terraform/` on the workstation, verify the selected workspace/account and destroy this lab:

```bash
terraform workspace show
terraform state list
terraform plan -destroy
terraform destroy
terraform state list
```

Destroy removes all selected Vault VMs and the Oracle data, network, and instance identity; it schedules KMS key deletion after seven days. Export evidence first. The pre-existing SSH key pair remains available. The final state list should be empty; protect retained state backups because they contain the license.

## Verification record

No AWS resources were created for authoring; live validation was deferred by request. Static checks cannot establish Oracle startup, compatibility of the chosen release pair, 100/100 credential behavior, three-node joining/failover, reboot persistence, or successful teardown. Run the healthy-integration checkpoint above before using this as experimental evidence.

Authoring checks on 2026-10-23 passed Terraform formatting/validation and 12 mock-provider tests, including one- and three-node mock applies. All four generated node payloads (one for the default topology and three for the optional topology) passed Bash syntax, HCL parsing, peer-address, and compressed-size checks. Changed local links and whitespace checks passed. ShellCheck was unavailable. These are static/offline results, not an Oracle execution result.

Repeat the local checks from `lab/terraform/`:

```bash
# From lab/terraform/; mock tests do not contact AWS.
terraform fmt -check -recursive
terraform validate
terraform test
bash -n ../scripts/bootstrap.sh ../scripts/configure.sh ../scripts/verify.sh
```

## References

- [Vault Oracle setup, client requirements, and compatibility](https://developer.hashicorp.com/vault/docs/secrets/databases/oracle)
- [Oracle connection and SQL statement parameters](https://developer.hashicorp.com/vault/api-docs/secret/databases/oracle)
- [Database connection, dynamic-role, and static-role APIs](https://developer.hashicorp.com/vault/api-docs/secret/databases)
- [Enterprise plugin registration/download prerequisites](https://developer.hashicorp.com/vault/docs/plugins/register)
- [AWS KMS seal configuration](https://developer.hashicorp.com/vault/docs/configuration/seal/awskms)
- [Raft storage and retry-join configuration](https://developer.hashicorp.com/vault/docs/configuration/storage/raft)
- [EC2 user-data execution](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html)
