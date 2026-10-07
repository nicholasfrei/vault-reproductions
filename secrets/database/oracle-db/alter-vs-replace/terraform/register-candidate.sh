#!/usr/bin/env bash
set -euo pipefail
set +x
umask 077

if [[ $(id -u) -ne 0 || $# -ne 2 ]]; then
  echo 'Usage (on disposable Oracle lab VM as root): register-candidate.sh <linux-amd64-plugin-binary> <version+ent.local>' >&2
  exit 1
fi

binary=$1
version=$2
name=vault-plugin-database-oracle
if [[ ! -f $binary || ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+\+ent\.[a-zA-Z0-9.-]+$ ]]; then
  echo 'Supply a readable Linux AMD64 binary and a distinct version such as 0.14.1+ent.local.' >&2
  exit 1
fi
if ! python3 - "$binary" <<'PY'
from pathlib import Path
import sys

header = Path(sys.argv[1]).read_bytes()[:20]
sys.exit(not (len(header) == 20 and header[:5] == b'\x7fELF\x02' and
              int.from_bytes(header[18:20], 'little') == 62))
PY
then
  echo 'The candidate must be a Linux AMD64 ELF binary.' >&2
  exit 1
fi

export VAULT_ADDR=http://127.0.0.1:8200
export VAULT_TOKEN
VAULT_TOKEN=$(cat /root/oracle-lab/token)
trap 'unset VAULT_TOKEN' EXIT

if vault plugin info -version="$version" database "$name" >/dev/null 2>&1; then
  echo 'That version is already registered; choose another local version.' >&2
  exit 1
fi

destination="/opt/vault/plugins/${name}_${version}_linux_amd64"
if [[ -e $destination ]]; then
  echo 'That plugin artifact directory already exists; choose another version.' >&2
  exit 1
fi

mkdir -m 0750 "$destination"
install -m 0755 "$binary" "$destination/$name"
gpg --homedir /root/oracle-lab/gnupg --batch --yes --armor --detach-sign \
  --output "$destination/plugin.sig" "$destination/$name"

python3 - "$destination" "$name" "$version" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

directory, name, version = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
binary = (directory / name).read_bytes()
signature = (directory / 'plugin.sig').read_text()
metadata = {
    'version': 'v0',
    'plugin': {
        'name': name,
        'type': 'database',
        'tier': 'official',
        'by': 'local-development-only',
        'version': version,
        'platform': 'linux',
        'arch': 'amd64',
        'pgp_sig': signature,
        'sha256': hashlib.sha256(binary).hexdigest(),
    },
}
(directory / 'metadata.json').write_text(json.dumps(metadata))
PY

gpg --homedir /root/oracle-lab/gnupg --batch --yes --armor --detach-sign \
  --output "$destination/metadata.json.sig" "$destination/metadata.json"
chown -R vault:vault "$destination"
find "$destination" -type f -exec chmod 0644 {} +
chmod 0755 "$destination/$name" "$destination"

vault plugin register -version="$version" database "$name"
echo "Candidate registered locally as $version; update oracle-db/config/oracle to select it."
