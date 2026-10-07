#!/usr/bin/env bash
set -euo pipefail
set +x
umask 077
source /etc/oracle-lab/lab.env

if [[ $(id -u) -ne 0 ]]; then
  echo 'Run the bootstrap as root on the disposable EC2 lab.' >&2
  exit 1
fi

dnf install -y docker unzip libaio libnsl python3 openssl
command -v curl >/dev/null || { echo 'AL2023 curl-minimal is required for HTTPS downloads.' >&2; exit 1; }
# AL2023 includes gnupg2-minimal, which cannot create the local plugin signing key.
# Use the documented swap instead of installing conflicting gnupg2 packages.
if rpm -q gnupg2-minimal >/dev/null 2>&1 && ! rpm -q gnupg2 >/dev/null 2>&1; then
  dnf swap -y gnupg2-minimal gnupg2-full
fi
command -v gpg >/dev/null || { echo 'Full GPG is required to sign the test plugin.' >&2; exit 1; }
systemctl enable --now docker
mkdir -p /root/oracle-lab/gnupg /etc/vault.d /opt/vault/plugins
chmod 0700 /root/oracle-lab /root/oracle-lab/gnupg

if ! id vault >/dev/null 2>&1; then
  useradd --system --home-dir /etc/vault.d --shell /sbin/nologin vault
fi
chown root:vault /etc/vault.d /opt/vault
chmod 0750 /etc/vault.d /opt/vault
chown vault:vault /opt/vault/plugins
chmod 0750 /opt/vault/plugins

# User data decodes the Enterprise license into a root-only file before bootstrap.
test -s /etc/vault.d/vault.hclic
chown root:vault /etc/vault.d/vault.hclic
chmod 0640 /etc/vault.d/vault.hclic

if [[ ! -s /root/oracle-lab/gnupg/pubring.kbx ]]; then
  gpg --homedir /root/oracle-lab/gnupg --batch --pinentry-mode loopback --passphrase '' \
    --quick-generate-key 'Disposable Oracle lab plugin signing' rsa2048 sign 30d >/dev/null
fi
gpg --homedir /root/oracle-lab/gnupg --armor --export > /etc/vault.d/oracle-lab-dev-pgp.asc
chown root:vault /etc/vault.d/oracle-lab-dev-pgp.asc
chmod 0640 /etc/vault.d/oracle-lab-dev-pgp.asc

curl -fsSL "https://releases.hashicorp.com/vault/$VAULT_VERSION/vault_${VAULT_VERSION}_linux_amd64.zip" -o /root/oracle-lab/vault.zip
unzip -oq /root/oracle-lab/vault.zip vault -d /usr/local/bin
chmod 0755 /usr/local/bin/vault
vault version

# Oracle Instant Client Basic is enough to RUN the plugin (SDK is only needed to BUILD one).
curl -fsSL 'https://download.oracle.com/otn_software/linux/instantclient/1932000/instantclient-basic-linux.x64-19.32.0.0.0dbru.zip' -o /root/oracle-lab/instantclient.zip
unzip -oq /root/oracle-lab/instantclient.zip -d /opt/vault
chgrp -R vault /opt/vault/instantclient_19_32
find /opt/vault/instantclient_19_32 -type d -exec chmod g+rx {} +
find /opt/vault/instantclient_19_32 -type f -exec chmod g+r {} +
printf '%s\n' /opt/vault/instantclient_19_32 > /etc/ld.so.conf.d/oracle-lab.conf
ldconfig

if [[ ! -s /root/oracle-lab/token ]]; then
  openssl rand -hex 24 > /root/oracle-lab/token
fi
cat > /root/oracle-lab/vault.env <<'ENV'
export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN
VAULT_TOKEN=$(cat /root/oracle-lab/token)
ENV
chmod 0600 /root/oracle-lab/vault.env
printf 'VAULT_DEV_ROOT_TOKEN_ID=%s\nVAULT_LICENSE_PATH=/etc/vault.d/vault.hclic\n' "$(cat /root/oracle-lab/token)" > /etc/vault.d/oracle-lab.env
chown root:vault /etc/vault.d/oracle-lab.env
chmod 0640 /etc/vault.d/oracle-lab.env

cat > /etc/systemd/system/vault.service <<'UNIT'
[Unit]
Description=Disposable Vault Enterprise dev server for Oracle lab
After=network-online.target
Wants=network-online.target

[Service]
User=vault
Group=vault
EnvironmentFile=/etc/vault.d/oracle-lab.env
ExecStart=/usr/local/bin/vault server -dev -dev-no-store-token -dev-listen-address=127.0.0.1:8200 -dev-plugin-dir=/opt/vault/plugins -dev-plugin-init=false -dev-plugin-pgp-key=/etc/vault.d/oracle-lab-dev-pgp.asc
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

cat > /etc/systemd/system/oracle-lab-setup.service <<'UNIT'
[Unit]
Description=Prepare Oracle root-rotation lab
Requires=docker.service vault.service
After=docker.service vault.service network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/oracle-lab-setup.sh
TimeoutStartSec=2400

[Install]
WantedBy=multi-user.target
UNIT

if ! docker container inspect oracle-lab >/dev/null 2>&1; then
  docker run -d --name oracle-lab --restart unless-stopped \
    --publish 127.0.0.1:1521:1521 --shm-size=1g --memory=4g \
    container-registry.oracle.com/database/express:21.3.0-xe >/dev/null
fi

systemctl daemon-reload
systemctl enable --now vault.service
systemctl enable --now oracle-lab-setup.service
