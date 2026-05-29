#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="pantheon"

# ──────────────────────────────────────────────────────────────────────────────
# Helper: extract a key from an existing secret (base64-decoded), or return ""
# ──────────────────────────────────────────────────────────────────────────────
secret_get() {
    local name="$1" key="$2"
    kubectl get secret --namespace "${NAMESPACE}" "${name}" \
        -o "jsonpath={.data['${key}']}" 2>/dev/null | base64 -d 2>/dev/null || true
}

echo "=== Create pantheon secrets in namespace ${NAMESPACE} ==="
echo ""

# ──────────────────────────────────────────────────────────────────────────────
# postgres-credentials  (POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB, url)
# ──────────────────────────────────────────────────────────────────────────────
EXISTING_PG_USER="$(secret_get postgres-credentials POSTGRES_USER)"
PG_USER_DEFAULT="${EXISTING_PG_USER:-postgres}"

EXISTING_PG_DB="$(secret_get postgres-credentials POSTGRES_DB)"
PG_DB_DEFAULT="${EXISTING_PG_DB:-pantheon_db}"

EXISTING_PG_PASS="$(secret_get postgres-credentials POSTGRES_PASSWORD)"

read -r -p "Postgres user [${PG_USER_DEFAULT}]: " PG_USER
PG_USER="${PG_USER:-$PG_USER_DEFAULT}"

read -r -p "Postgres database [${PG_DB_DEFAULT}]: " PG_DB
PG_DB="${PG_DB:-$PG_DB_DEFAULT}"

read -r -p "Postgres password [****************]: " PG_PASS
PG_PASS="${PG_PASS:-$EXISTING_PG_PASS}"
[[ -z "$PG_PASS" ]] && { echo "Postgres password is required."; exit 1; }

# Build DATABASE_URL — the headless svc is "postgres.pantheon.svc.cluster.local".
DATABASE_URL="postgresql://${PG_USER}:${PG_PASS}@postgres.${NAMESPACE}.svc.cluster.local:5432/${PG_DB}"

echo ""
echo "--- postgres-credentials ---"
echo "  PG_USER      = ${PG_USER}"
echo "  PG_DB        = ${PG_DB}"
echo "  DATABASE_URL = ${DATABASE_URL}"
echo ""

kubectl create secret generic postgres-credentials \
    --namespace "${NAMESPACE}" \
    --from-literal=POSTGRES_USER="${PG_USER}" \
    --from-literal=POSTGRES_PASSWORD="${PG_PASS}" \
    --from-literal=POSTGRES_DB="${PG_DB}" \
    --from-literal=url="${DATABASE_URL}" \
    --dry-run=client -o yaml | kubectl apply -f -

# ──────────────────────────────────────────────────────────────────────────────
# app-secret  (SECRET_KEY_BASE, OIDC_ISSUER, OIDC_CLIENT_ID)
# ──────────────────────────────────────────────────────────────────────────────
EXISTING_SECRET_KEY_BASE="$(secret_get app-secret SECRET_KEY_BASE)"
DEFAULT_SECRET_KEY_BASE="${EXISTING_SECRET_KEY_BASE:-$(openssl rand -hex 32)}"

EXISTING_OIDC_ISSUER="$(secret_get app-secret OIDC_ISSUER)"

EXISTING_OIDC_CLIENT_ID="$(secret_get app-secret OIDC_CLIENT_ID)"

read -r -p "SECRET_KEY_BASE [${DEFAULT_SECRET_KEY_BASE}]: " val
SECRET_KEY_BASE="${val:-$DEFAULT_SECRET_KEY_BASE}"

read -r -p "OIDC_ISSUER [${EXISTING_OIDC_ISSUER}]: " OIDC_ISSUER
OIDC_ISSUER="${OIDC_ISSUER:-$EXISTING_OIDC_ISSUER}"
[[ -z "$OIDC_ISSUER" ]] && { echo "OIDC_ISSUER is required."; exit 1; }

read -r -p "OIDC_CLIENT_ID [${EXISTING_OIDC_CLIENT_ID}]: " OIDC_CLIENT_ID
OIDC_CLIENT_ID="${OIDC_CLIENT_ID:-$EXISTING_OIDC_CLIENT_ID}"
[[ -z "$OIDC_CLIENT_ID" ]] && { echo "OIDC_CLIENT_ID is required."; exit 1; }

echo ""
echo "--- app-secret ---"
echo "  SECRET_KEY_BASE = (hidden)"
echo "  OIDC_ISSUER     = ${OIDC_ISSUER}"
echo "  OIDC_CLIENT_ID  = ${OIDC_CLIENT_ID}"
echo ""

kubectl create secret generic app-secret \
    --namespace "${NAMESPACE}" \
    --from-literal=SECRET_KEY_BASE="${SECRET_KEY_BASE}" \
    --from-literal=OIDC_ISSUER="${OIDC_ISSUER}" \
    --from-literal=OIDC_CLIENT_ID="${OIDC_CLIENT_ID}" \
    --dry-run=client -o yaml | kubectl apply -f -

echo "Done. Both secrets are ready in namespace '${NAMESPACE}'."
