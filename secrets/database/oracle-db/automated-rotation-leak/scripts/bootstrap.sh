#!/usr/bin/env bash

set -euo pipefail
umask 077
trap 'echo "Bootstrap failed at line $LINENO; inspect cloud-init-output.log" >&2' ERR
[[ $EUID -eq 0 ]] || { echo 'Run as root.' >&2; exit 1; }

dnf install -y docker jq unzip lsof procps-ng util-linux openssl tar gzip libaio libnsl iptables-nft

# Set up the handoff login before lengthy Oracle downloads and initialization.
id lab >/dev/null 2>&1 || useradd --create-home --shell /bin/bash lab
printf 'lab:%s\n' "$(cat /root/oracle-lab/ssh-password)" | chpasswd
rm /root/oracle-lab/ssh-password
printf 'lab ALL=(ALL) NOPASSWD: ALL\n' > /etc/sudoers.d/oracle-lab
chmod 0440 /etc/sudoers.d/oracle-lab
visudo -cf /etc/sudoers.d/oracle-lab
cat > /etc/ssh/sshd_config.d/00-oracle-lab.conf <<'EOF'
PasswordAuthentication yes
KbdInteractiveAuthentication no
PermitRootLogin no
EOF
chmod 0644 /etc/ssh/sshd_config.d/00-oracle-lab.conf
sshd -t
# Consume all output so an early grep exit cannot give sshd SIGPIPE under pipefail.
sshd -T -C user=lab,host=localhost,addr=127.0.0.1 | grep -x 'passwordauthentication yes' >/dev/null
systemctl reload sshd

install -d -m 0755 /etc/systemd/journald.conf.d /var/log/journal
cat > /etc/systemd/journald.conf.d/oracle-lab.conf <<'EOF'
[Journal]
Storage=persistent
SystemMaxUse=1G
EOF
systemctl restart systemd-journald

id vault >/dev/null 2>&1 || useradd --system --home-dir /opt/vault --shell /sbin/nologin vault
install -d -o vault -g vault -m 0750 /opt/vault/data /opt/vault/plugins /etc/vault.d
install -d -m 0700 /var/log/oracle-lab
install -d -m 0755 /opt/oracle
install -o vault -g vault -m 0600 /root/oracle-lab/license /etc/vault.d/vault.hclic
rm /root/oracle-lab/license

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
vault_version='1.21.9+ent'
archive="vault_${vault_version}_linux_amd64.zip"
curl --fail --silent --show-error --location --retry 5 \
  "https://releases.hashicorp.com/vault/${vault_version}/${archive}" -o "$work/$archive"
curl --fail --silent --show-error --location --retry 5 \
  "https://releases.hashicorp.com/vault/${vault_version}/vault_${vault_version}_SHA256SUMS" -o "$work/SHA256SUMS"
awk -v name="$archive" '$2 == name' "$work/SHA256SUMS" > "$work/checksums"
(cd "$work" && sha256sum --check checksums)
unzip -q "$work/$archive" -d "$work/vault"
install -m 0755 "$work/vault/vault" /usr/local/bin/vault
vault version

curl --fail --silent --show-error --location --retry 5 \
  'https://download.oracle.com/otn_software/linux/instantclient/1932000/instantclient-basic-linux.x64-19.32.0.0.0dbru.zip' \
  -o "$work/instantclient.zip"
unzip -q "$work/instantclient.zip" -d /opt/oracle
chmod -R a+rX /opt/oracle/instantclient_19_32
printf '/opt/oracle/instantclient_19_32\n' > /etc/ld.so.conf.d/oracle-instantclient.conf
chmod 0644 /etc/ld.so.conf.d/oracle-instantclient.conf
ldconfig
ldconfig -p | grep 'libclntsh.so.19.1'

region=$(cat /root/oracle-lab/region)
kms_key=$(cat /root/oracle-lab/kms-key)
cat > /etc/vault.d/vault.hcl <<EOF
ui = true
disable_mlock = true
log_level = "debug"
api_addr = "http://127.0.0.1:8200"
cluster_addr = "https://127.0.0.1:8201"
plugin_directory = "/opt/vault/plugins"
license_path = "/etc/vault.d/vault.hclic"
storage "raft" {
  path = "/opt/vault/data"
  node_id = "oracle-lab-1"
}
listener "tcp" {
  address = "127.0.0.1:8200"
  cluster_address = "127.0.0.1:8201"
  tls_disable = true
}
seal "awskms" {
  region = "$region"
  kms_key_id = "$kms_key"
}
EOF
chown vault:vault /etc/vault.d/vault.hcl
chmod 0640 /etc/vault.d/vault.hcl
cat > /etc/systemd/system/vault.service <<'EOF'
[Unit]
Description=Vault Enterprise Oracle rotation lab
Wants=network-online.target
After=network-online.target oracle-lab-fault.service
StartLimitIntervalSec=0

[Service]
User=vault
Group=vault
ExecStartPre=+/opt/oracle-lab/fault.sh verify-if-enabled
ExecStart=/usr/local/bin/vault server -config=/etc/vault.d/vault.hcl
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
KillMode=control-group
LimitNOFILE=65536
UMask=0077

[Install]
WantedBy=multi-user.target
EOF

systemctl enable --now docker
docker network create --subnet 172.30.250.0/24 oracle-lab
docker volume create oracle-lab-data
# Oracle password identifiers are limited to 30 bytes; 12 random bytes yield 24 hex characters.
printf 'ORACLE_PWD=%s\n' "$(openssl rand -hex 12)" > /root/oracle-lab/oracle.env
docker pull container-registry.oracle.com/database/express:21.3.0-xe
docker create --name oracle-db --restart unless-stopped \
  --network oracle-lab --ip 172.30.250.10 \
  -p 127.0.0.1:1521:1521 --shm-size=1g \
  --env-file /root/oracle-lab/oracle.env \
  -v oracle-lab-data:/opt/oracle/oradata \
  container-registry.oracle.com/database/express:21.3.0-xe
cat > /etc/systemd/system/oracle-db.service <<'EOF'
[Unit]
Description=Oracle XE lab container
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/docker start oracle-db
ExecStop=/usr/bin/docker stop --time 60 oracle-db
TimeoutStopSec=90

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/oracle-lab-fault.service <<'EOF'
[Unit]
Description=Drop host connections to the Oracle lab bridge address
Requires=docker.service
After=docker.service
Before=vault.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/opt/oracle-lab/fault.sh start
ExecStop=/opt/oracle-lab/fault.sh stop

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/oracle-lab-monitor.service <<'EOF'
[Unit]
Description=Oracle rotation lab process and goroutine evidence
After=vault.service

[Service]
ExecStart=/opt/oracle-lab/monitor.sh
Restart=on-failure
RestartSec=5
UMask=0077

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/oracle-lab-configure.service <<'EOF'
[Unit]
Description=Initialize Vault and configure ten Oracle static roles
Wants=vault.service oracle-db.service
After=vault.service oracle-db.service
ConditionPathExists=!/root/oracle-lab/READY

[Service]
Type=oneshot
ExecStart=/opt/oracle-lab/configure.sh
TimeoutStartSec=45min
UMask=0077

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now oracle-db.service vault.service
systemctl enable oracle-lab-configure.service
systemctl start --no-block oracle-lab-configure.service
echo 'Installation complete; follow journalctl -fu oracle-lab-configure for lab readiness.'
