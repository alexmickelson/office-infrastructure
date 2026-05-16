#!/bin/sh
set -e

ENV_FILE="/opt/data/.env"

if ! grep -q '^API_SERVER_KEY=' "$ENV_FILE" 2>/dev/null; then
  KEY=$(openssl rand -hex 32)
  echo "API_SERVER_KEY=$KEY" >> "$ENV_FILE"
  echo "[entrypoint] Generated new API_SERVER_KEY and appended to $ENV_FILE"
else
  echo "[entrypoint] API_SERVER_KEY already set, skipping"
fi

exec /opt/hermes/docker/entrypoint.sh "$@"
