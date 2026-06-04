#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="discord-bot"

# ──────────────────────────────────────────────────────────────────────────────
# Helper: extract a key from an existing secret (base64-decoded), or return ""
# ──────────────────────────────────────────────────────────────────────────────
secret_get() {
    local name="$1" key="$2"
    kubectl get secret --namespace "${NAMESPACE}" "${name}" \
        -o "jsonpath={.data['${key}']}" 2>/dev/null | base64 -d 2>/dev/null || true
}

echo "=== Create discordadminbot secrets in namespace ${NAMESPACE} ==="
echo ""

# ──────────────────────────────────────────────────────────────────────────────
# discordadminbot-secrets (DISCORD_BOT_TOKEN, DISCORD_GUILD_ID)
# ──────────────────────────────────────────────────────────────────────────────
EXISTING_BOT_TOKEN="$(secret_get discordadminbot-secrets DISCORD_BOT_TOKEN)"

EXISTING_GUILD_ID="$(secret_get discordadminbot-secrets DISCORD_GUILD_ID)"

read -r -p "Discord Bot Token [****************]: " BOT_TOKEN
BOT_TOKEN="${BOT_TOKEN:-$EXISTING_BOT_TOKEN}"
[[ -z "$BOT_TOKEN" ]] && { echo "DISCORD_BOT_TOKEN is required."; exit 1; }

read -r -p "Discord Guild ID [${EXISTING_GUILD_ID}]: " GUILD_ID
GUILD_ID="${GUILD_ID:-$EXISTING_GUILD_ID}"
[[ -z "$GUILD_ID" ]] && { echo "DISCORD_GUILD_ID is required."; exit 1; }

echo ""
echo "--- discordadminbot-secrets ---"
echo "  DISCORD_BOT_TOKEN = (hidden)"
echo "  DISCORD_GUILD_ID  = ${GUILD_ID}"
echo ""

kubectl create secret generic discordadminbot-secrets \
    --namespace "${NAMESPACE}" \
    --from-literal=DISCORD_BOT_TOKEN="${BOT_TOKEN}" \
    --from-literal=DISCORD_GUILD_ID="${GUILD_ID}" \
    --dry-run=client -o yaml | kubectl apply -f -

echo "Done. Secret is ready in namespace '${NAMESPACE}'."
