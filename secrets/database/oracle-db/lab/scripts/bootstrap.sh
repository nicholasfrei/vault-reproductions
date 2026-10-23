#!/usr/bin/env bash
# Install the healthy baseline on a fresh Terraform-created AL2023 x86_64 VM.
# Runs as root from cloud-init; config/license are staged in /root/oracle-baseline.
set -euo pipefail
set +x
umask 077
trap 'echo "Bootstrap failed at line $LINENO; inspect cloud-init output privately." >&2' ERR
[[ $EUID -eq 0 && $(uname -m) == x86_64 ]] || { echo 'Requires root on an x86_64 AL2023 VM.' >&2; exit 1; }
cd /root/oracle-baseline
[[ ! -e BOOTSTRAPPED ]] || { echo 'Bootstrap already completed; use oracle-baseline-verify or rebuild with Terraform.' >&2; exit 1; }
test -s config.json
test -s vault.hclic

dnf install -y docker unzip libaio libnsl jq openssl
for tool in curl sha256sum unzip jq openssl docker systemctl; do
  command -v "$tool" >/dev/null || { echo "Missing prerequisite: $tool" >&2; exit 1; }
done
vault_version=$(jq -er '.vault_version' config.json)
plugin_version=$(jq -er '.oracle_plugin_version' config.json)
node_index=$(jq -er '.node_index' config.json)
node_id=$(jq -er '.node_id' config.json)
private_ip=$(jq -er '.private_ip' config.json)
region=$(jq -er '.aws_region' config.json)
kms_key=$(jq -er '.kms_key_id' config.json)
systemctl enable --now docker

if ! id vault >/dev/null 2>&1; then
  useradd --system --home-dir /etc/vault.d --shell /sbin/nologin vault
fi
install -d -m 0750 -o vault -g vault /etc/vault.d /opt/vault /opt/vault/data /opt/vault/plugins
install -m 0640 -o root -g vault vault.hclic /etc/vault.d/vault.hclic

archive="vault_${vault_version}_linux_amd64.zip"
curl --retry 3 -fsSL "https://releases.hashicorp.com/vault/$vault_version/$archive" -o "$archive"
curl --retry 3 -fsSL "https://releases.hashicorp.com/vault/$vault_version/vault_${vault_version}_SHA256SUMS" -o vault-SHA256SUMS
awk -v archive="$archive" '$2 == archive { print; found=1 } END { exit !found }' vault-SHA256SUMS > vault-checksum
sha256sum -c vault-checksum
unzip -oq "$archive" vault -d /usr/local/bin
chmod 0755 /usr/local/bin/vault

# Basic provides runtime libraries; an SDK is only needed when compiling a plugin.
curl --retry 3 -fsSL 'https://download.oracle.com/otn_software/linux/instantclient/1932000/instantclient-basic-linux.x64-19.32.0.0.0dbru.zip' -o instantclient.zip
unzip -oq instantclient.zip -d /opt/vault
chown -R root:vault /opt/vault/instantclient_19_32
find /opt/vault/instantclient_19_32 -type d -exec chmod 0750 {} +
find /opt/vault/instantclient_19_32 -type f -exec chmod g+r {} +
printf '%s\n' /opt/vault/instantclient_19_32 > /etc/ld.so.conf.d/oracle-baseline.conf
ldconfig

# Preserve the complete official archive layout (binary, metadata and signatures)
# on EVERY voter so whichever node becomes active can launch this plugin.
plugin_archive="vault-plugin-database-oracle_${plugin_version}_linux_amd64"
plugin_url="https://releases.hashicorp.com/vault-plugin-database-oracle/$plugin_version"
curl --retry 3 -fsSL "$plugin_url/$plugin_archive.zip" -o "$plugin_archive.zip"
curl --retry 3 -fsSL "$plugin_url/vault-plugin-database-oracle_${plugin_version}_SHA256SUMS" -o plugin-SHA256SUMS
awk -v archive="$plugin_archive.zip" '$2 == archive { print; found=1 } END { exit !found }' plugin-SHA256SUMS > plugin-checksum
sha256sum -c plugin-checksum
install -d -m 0750 -o root -g vault "/opt/vault/plugins/$plugin_archive"
unzip -oq "$plugin_archive.zip" -d "/opt/vault/plugins/$plugin_archive"
chown -R root:vault "/opt/vault/plugins/$plugin_archive"
chmod -R g+rX "/opt/vault/plugins/$plugin_archive"
chmod 0750 "/opt/vault/plugins/$plugin_archive/vault-plugin-database-oracle"
runuser -u vault -- ldd "/opt/vault/plugins/$plugin_archive/vault-plugin-database-oracle" > plugin-libraries.txt
if grep -q 'not found' plugin-libraries.txt; then
  echo 'Oracle plugin libraries are missing; inspect plugin-libraries.txt.' >&2; exit 1
fi

cat > /etc/vault.d/vault.hcl <<EOF
ui = true
disable_mlock = true
api_addr = "http://$private_ip:8200"
cluster_addr = "https://$private_ip:8201"
plugin_directory = "/opt/vault/plugins"
license_path = "/etc/vault.d/vault.hclic"
listener "tcp" {
  address = "0.0.0.0:8200"
  cluster_address = "$private_ip:8201"
  tls_disable = true
}
storage "raft" {
  path = "/opt/vault/data"
  node_id = "$node_id"
EOF
# Only node 1 is initialized. Followers retry joining peers and auto-unseal with
# the same KMS key; they must never create their own independent clusters.
if (( node_index > 0 )); then
  jq -r --arg self "$node_id" '.nodes[] | select(.node_id != $self) |
    "  retry_join {\n    leader_api_addr = \"http://\(.private_ip):8200\"\n  }"' config.json >> /etc/vault.d/vault.hcl
fi
cat >> /etc/vault.d/vault.hcl <<EOF
}
seal "awskms" {
  region = "$region"
  kms_key_id = "$kms_key"
}
EOF
chown root:vault /etc/vault.d/vault.hcl
chmod 0640 /etc/vault.d/vault.hcl
cat > /etc/systemd/system/vault.service <<'UNIT'
[Unit]
Description=Vault Oracle integration baseline
Wants=network-online.target
After=network-online.target

[Service]
User=vault
Group=vault
ExecStart=/usr/local/bin/vault server -config=/etc/vault.d/vault.hcl
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
UMask=0077

[Install]
WantedBy=multi-user.target
UNIT

if (( node_index == 0 )); then
  if [[ ! -s oracle.env ]]; then
    printf 'ORACLE_PWD=A1%s\n' "$(openssl rand -hex 12)" > oracle.env
  fi
  docker volume create oracle-baseline-data >/dev/null
  if ! docker container inspect oracle-db >/dev/null 2>&1; then
    docker run -d --name oracle-db --restart unless-stopped \
      --publish 127.0.0.1:1521:1521 --publish "$private_ip:1521:1521" \
      --shm-size=1g --memory=4g \
      --env-file oracle.env --volume oracle-baseline-data:/opt/oracle/oradata \
      container-registry.oracle.com/database/express:21.3.0-xe >/dev/null
  fi
fi

cat > /etc/systemd/system/oracle-baseline-configure.service <<'UNIT'
[Unit]
Description=Configure and verify the Oracle integration baseline
Requires=docker.service vault.service
After=docker.service vault.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/oracle-baseline-configure
TimeoutStartSec=7200
UMask=0077
UNIT
systemctl daemon-reload
systemctl enable --now vault.service
# Run once, not on every boot: a scenario may intentionally change this baseline.
systemctl start --no-block oracle-baseline-configure.service
date -u +%FT%TZ > BOOTSTRAPPED
echo 'Services installed; follow oracle-baseline-configure.service for integration readiness.'
