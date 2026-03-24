#!/usr/bin/env bash
set -euo pipefail

CONTAINER_NAME="${POSTGRES_CONTAINER_NAME:-postgres-vault}"
IMAGE="${POSTGRES_IMAGE:-postgres:16}"
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-postgres}"
POSTGRES_DB="${POSTGRES_DB:-vaultdb}"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker CLI not found. Skipping PostgreSQL container bootstrap." >&2
  exit 0
fi

if ! docker info >/dev/null 2>&1; then
  echo "docker daemon is not reachable. Skipping PostgreSQL container bootstrap." >&2
  exit 0
fi

if ! docker inspect "${CONTAINER_NAME}" >/dev/null 2>&1; then
  docker run -d \
    --name "${CONTAINER_NAME}" \
    -e POSTGRES_USER="${POSTGRES_USER}" \
    -e POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
    -e POSTGRES_DB="${POSTGRES_DB}" \
    -p 5432:5432 \
    "${IMAGE}" >/dev/null
else
  docker start "${CONTAINER_NAME}" >/dev/null || true
fi

for _ in $(seq 1 30); do
  if docker exec "${CONTAINER_NAME}" pg_isready -U "${POSTGRES_USER}" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

docker exec -i "${CONTAINER_NAME}" psql -v ON_ERROR_STOP=1 -U "${POSTGRES_USER}" <<'SQL'
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'vaultuser') THEN
    CREATE ROLE vaultuser WITH LOGIN PASSWORD 'vaultpass';
  ELSE
    ALTER ROLE vaultuser WITH LOGIN PASSWORD 'vaultpass';
  END IF;
END $$;

GRANT CONNECT ON DATABASE vaultdb TO vaultuser;
GRANT pg_monitor TO vaultuser;
ALTER ROLE vaultuser CREATEROLE;
SQL

echo "PostgreSQL lab container is ready: ${CONTAINER_NAME}"
