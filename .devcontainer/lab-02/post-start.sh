#!/usr/bin/env bash
set -euo pipefail

bash .devcontainer/run/start-vault.sh
bash .devcontainer/lab-02/start-postgres.sh
