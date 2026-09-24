# Oracle Automatic Static-Role Rotation Resource-Growth Runbook

## Overview

This runbook reproduces the resource-growth pattern behind `VAULT-50722` using the Oracle database plugin in Vault `1.21.9+ent`. It also demonstrates an interim mitigation for this resource growth.

The pattern traces back to `VAULT-43596`, where a hanging MySQL handshake stalled an entire static-role rotation queue. The fix for that ticket (`vault-enterprise` [PR #13697](https://github.com/hashicorp/vault-enterprise/pull/13697)) added a goroutine-plus-timeout race around the plugin's `UpdateUser` and `Initialize` calls so one hung connection could not block rotation for every other role in the mount.

In this runbook, the goal is to provision an AWS lab for investigating `VAULT-50722`: automatic static-role rotation against an unreachable Oracle database after restarting Vault. Terraform installs a persistent, single-node Raft server, Oracle in Docker, and ten roles with `rotation_period=10s`. 

The bootstrap script leaves Oracle reachable and verifies that every role rotates automatically. The outage is an explicit later step: stop Vault, block Oracle, then restart Vault with an empty connection cache and the existing roles intact.

### Versions and architecture

| Component | Configuration |
| --- | --- |
| AWS host | Amazon Linux 2023, x86-64, `t3.large`, 8 GiB RAM, encrypted 80-GiB root disk |
| Vault | Enterprise `1.21.9+ent`, systemd, single-node Raft, AWS KMS auto-unseal |
| Oracle | XE `21.3.0-xe`, Docker volume, restart enabled |
| Oracle Instant Client | Basic `19.32` |
| Oracle plugin | `vault-plugin-database-oracle` `0.11.0+ent`, downloaded through Vault |
| Static roles | `leak-repro-01` through `leak-repro-10`, ten distinct Oracle users, 10-second periods |
| Network | Dedicated VPC/subnet; SSH from `0.0.0.0/0`; Vault API and published Oracle port on loopback |

Vault connects directly to Oracle's fixed private Docker bridge address, `172.30.250.10:1521`, to make fault injection independent of published-port NAT. Oracle is not exposed by the EC2 security group. Vault's API is `http://127.0.0.1:8200`; use SSH or a tunnel to access it.

### Investigation

Source inspection identified these candidate mechanisms:

- PR [#13697](https://github.com/hashicorp/vault-enterprise/pull/13697), backported in [#14352](https://github.com/hashicorp/vault-enterprise/pull/14352), added a ten-second cache-miss initialization timeout. Failed initialization is not cached, allowing another due role to create another plugin client.
- The automatic queue advances synchronously through due roles, requeuing failures for ten seconds after failure.

## Prerequisites

- Terraform 1.5 or later and AWS credentials authorized to create VPC/network resources, EC2/EBS, IAM role/profile/policy, and a KMS key/alias; permission to pass the instance role and read the public AMI SSM parameter.
- AWS region/profile selected for this disposable lab; defaults are configurable in `terraform.tfvars`.
- An existing shell variable `VAULT_LICENSE` containing your Enterprise license. Do not paste it into this runbook or a tracked file.
- Oracle registry/download access.

The `lab` user has passwordless sudo. Share its generated SSH password through your team's credential-sharing channel. Terraform state and EC2 user data contain credentials; protect state and do not commit licenses or `terraform.tfvars`.

## Step 1: Create the VM with Terraform

For an existing ready VM, skip to the root-shell setup in Step 2.

On your workstation, prepare variables from this runbook's directory:

```bash
cd terraform
umask 077
cp terraform.tfvars.example terraform.tfvars
```

Edit the region/profile in `terraform.tfvars`, then create the lab. On an existing lab, changed user data replaces the VM and its local data; export evidence before applying such changes.

```bash
: "${VAULT_LICENSE:?Set VAULT_LICENSE in this shell first}"
export TF_VAR_vault_license="$VAULT_LICENSE"
terraform init
terraform plan
terraform apply
```

Terraform creates the infrastructure and starts bootstrap. Wait for the readiness check in Step 2 before testing.

Retrieve the handoff details locally:

```bash
terraform output -raw ssh_command
terraform output -raw ssh_password
terraform output -raw instance_id
```

Use the printed SSH command and enter the password at its prompt. No personal private key is required.

## Step 2: Confirm provisioning and healthy automatic rotations

On the VM, wait for bootstrap and follow configuration logs:

```bash
sudo cloud-init status --wait
sudo journalctl -fu oracle-lab-configure.service
```

Oracle may take 10–30 minutes on first startup. Bootstrap verifies that all ten roles rotate automatically.

Confirm the lab is ready:

```bash
sudo cat /root/oracle-lab/READY
sudo systemctl --no-pager status vault oracle-db oracle-lab-monitor
sudo docker inspect --format '{{.State.Health.Status}}' oracle-db
sudo systemctl is-active oracle-lab-fault.service || true
```

Expected: a readiness timestamp, active Vault/Oracle/monitor services, Oracle `healthy`, and fault `inactive`.

If setup fails, inspect `/var/log/cloud-init-output.log`, `journalctl -u oracle-lab-configure`, and `/root/oracle-lab/sql-setup.log`. Repair the error before restarting configuration; do not reinitialize Vault.

Open a root shell and load the lab credentials. Use this shell for subsequent VM commands unless another terminal is specified:

```bash
sudo -i
source /root/oracle-lab/admin.env
vault status
```

Expected: Vault `1.21.9+ent`, unsealed, with Raft storage and `awskms` seal type.

Inspect the database connection and the ten static roles:

```bash
vault read database/config/oracle
vault list database/static-roles
vault read database/static-roles/leak-repro-01
```

## Step 3: Record a healthy baseline

The monitor runs independently of the fault service. Ensure it is running:

```bash
systemctl start oracle-lab-monitor.service
```

After the healthy lab has run for at least two minutes, inspect metrics and rotation logs:

```bash
date -u +%FT%TZ | tee /root/oracle-lab/healthy-observation-start
tail -n 25 /var/log/oracle-lab/current/metrics.csv
journalctl -u vault --since '-2 minutes' --no-pager |
  grep 'successfully rotated static role'
```

The CSV records each process's PID, threads, FDs, RSS, and Vault goroutines. Plugin goroutines are `NA`. Stack/socket snapshots are under `/var/log/oracle-lab/current/snapshot-*`.

The monitor continues after logout and across Vault restarts. Connection errors to `127.0.0.1:8200` are expected while Vault is stopped; they do not mean the monitor failed.

## Step 4: Stop Vault and enable the Oracle fault

Stop Vault before enabling the fault so the next start uses an empty connection cache. Leave Oracle running:

```bash
test -s /root/oracle-lab/READY
systemctl stop vault.service
systemctl enable --now oracle-lab-fault.service
iptables -vnL ORACLE_LAB_FAULT
```

The fault blocks Oracle at `172.30.250.10:1521`; it does not block Vault's API or start metrics collection. If testing a replacement binary, install it at `/usr/local/bin/vault` while Vault is stopped.

Confirm silent packet loss, not connection refusal:

```bash
rc=0
timeout 15 bash -c 'echo > /dev/tcp/172.30.250.10/1521' || rc=$?
printf 'probe_exit=%s\n' "$rc"
test "$rc" -eq 124
iptables -vnL ORACLE_LAB_FAULT
```

Expected after approximately fifteen seconds:

```text
probe_exit=124
```

DROP counters should increase. If the probe succeeds or returns `Connection refused`, correct the fault before continuing.

The enabled fault persists across reboot. Vault's startup check requires its rules to be present while the fault is enabled.

## Step 5: Restart Vault and observe the automatic queue

Start Vault and confirm it auto-unseals:

```bash
vault version
date -u +%FT%TZ | tee /root/oracle-lab/outage-start
systemctl start vault.service
vault status
```

Rerun `vault status` until unsealed. The ten roles rotate automatically; do not use `rotate-role` or rewrite the database config during the test.

In a second SSH terminal, follow Vault logs:

```bash
sudo journalctl -u vault -f
```

In a third SSH terminal, follow metrics:

```bash
sudo tail -f /var/log/oracle-lab/current/metrics.csv
```

Rotation failures are expected while Oracle is unreachable. Look for initialization errors such as:

```text
unable to rotate credentials in periodic function
timeout exceeded during Initialize: context deadline exceeded
unable to initialize: rpc error: code = DeadlineExceeded desc = context deadline exceeded
```

Initialization attempts may recur roughly every ten seconds. Compare against the healthy baseline:

- Look for sustained FD, goroutine, or RSS growth. With a fixed binary, these should plateau rather than grow continuously.
- Compare within the same PID. A restart resetting counts does not prove the leak is fixed.
- Distinguish Vault from plugin rows; a new socket does not necessarily mean a new plugin process.
- Record what actually happens, including a plateau. `UpdateUser` timeouts instead of initialization errors may indicate a cached connection.

## Step 6: Finish the test

Back in the VM's root shell, capture any needed live observations, then stop Vault, remove the fault, and pause monitoring:

```bash
systemctl stop vault.service
systemctl disable --now oracle-lab-fault.service
systemctl stop oracle-lab-monitor.service
```

To return to healthy automatic rotations, confirm Oracle connectivity and restart Vault and the monitor:

```bash
timeout 5 bash -c 'echo > /dev/tcp/172.30.250.10/1521'
systemctl start vault.service oracle-lab-monitor.service
```

Confirm auto-unseal and successful automatic rotations in the Vault logs.

## Step 7: Optional client-timeout comparison

This optional comparison tests whether Oracle connect timeouts change the growth trend. It is not a verified fix for callback cleanup.

From a healthy lab, configure the timeouts in the VM's root shell:

```bash
install -d -m 0755 /etc/vault.d/oracle-network-admin /etc/systemd/system/vault.service.d
cat > /etc/vault.d/oracle-network-admin/sqlnet.ora <<'EOF'
SQLNET.OUTBOUND_CONNECT_TIMEOUT=3
TCP.CONNECT_TIMEOUT=5
EOF
chmod 0644 /etc/vault.d/oracle-network-admin/sqlnet.ora
cat > /etc/systemd/system/vault.service.d/oracle-timeouts.conf <<'EOF'
[Service]
Environment=TNS_ADMIN=/etc/vault.d/oracle-network-admin
EOF
systemctl daemon-reload
```

Repeat Steps 4–5 with the same roles. Verify the plugin inherited `TNS_ADMIN`, using its PID from the CSV:

```bash
plugin_pid="<plugin_pid>"
tr '\0' '\n' < "/proc/$plugin_pid/environ" | grep '^TNS_ADMIN='
```

Compare attempt duration, Oracle `ORA-` errors versus Vault timeouts, and per-PID resource growth. Record the result rather than assuming growth is bounded.

To return to the original no-client-timeout experiment, stop Vault, remove only `/etc/systemd/system/vault.service.d/oracle-timeouts.conf`, run `systemctl daemon-reload`, and start Vault. Preserve the fault if comparing unreachable-database runs.

## Step 8: Export evidence and destroy the lab

On the VM, as root, stop monitoring and archive the collected evidence:

```bash
systemctl stop oracle-lab-monitor.service
journalctl -u vault -u oracle-lab-configure -u oracle-lab-fault --no-pager > /var/log/oracle-lab/services.log
journalctl -k --no-pager > /var/log/oracle-lab/kernel.log
iptables -vnL OUTPUT > /var/log/oracle-lab/output-rules.txt
tar -C /var/log -czf /home/lab/oracle-lab-evidence.tar.gz oracle-lab
chown lab:lab /home/lab/oracle-lab-evidence.tar.gz
chmod 0600 /home/lab/oracle-lab-evidence.tar.gz
```

From your workstation, copy the archive and review it before sharing. It excludes the lab credentials, license, and Terraform state:

```bash
scp -o PreferredAuthentications=password -o PubkeyAuthentication=no \
  lab@<ip_addr>:oracle-lab-evidence.tar.gz ./
```

When the team is done, destroy the lab from its local `terraform/` directory using the same profile/state and license environment variable. This deletes the VM, its disk, and any unexported evidence; there is no automatic 24-hour teardown.

```bash
terraform destroy
unset TF_VAR_vault_license
```

The KMS key is scheduled for deletion after seven days. Dispose of local Terraform state copies when no longer needed.

## References

- [Vault PR #13697](https://github.com/hashicorp/vault-enterprise/pull/13697)
- [Vault 1.21 backport #14352](https://github.com/hashicorp/vault-enterprise/pull/14352)
- [Automatic rotation queue at v1.21.9+ent](https://github.com/hashicorp/vault-enterprise/blob/v1.21.9%2Bent/builtin/logical/database/rotation.go)
- [Connection initialization at v1.21.9+ent](https://github.com/hashicorp/vault-enterprise/blob/v1.21.9%2Bent/builtin/logical/database/backend.go)
- [Oracle plugin v0.11.0+ent](https://github.com/hashicorp/vault-plugin-database-oracle-enterprise/tree/v0.11.0%2Bent)
- [Oracle Net timeout parameters](https://docs.oracle.com/en/database/oracle/oracle-database/21/netrf/parameters-for-the-sqlnet.ora.html)
- [go-oci8 cancellation discussion](https://github.com/mattn/go-oci8/issues/419)
- [Oracle ORA-00972 and the password-identifier limit](https://docs.oracle.com/error-help/db/ora-00972/)
