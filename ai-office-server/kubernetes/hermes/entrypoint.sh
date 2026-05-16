#!/bin/sh
set -e

# Bootstrap /nix on first run (empty hostPath volume shadows the image store).
if [ ! -d /nix/store ] || [ -z "$(ls -A /nix/store 2>/dev/null)" ]; then
  echo "[entrypoint] /nix/store is empty, installing Nix into the persistent volume..."
  curl -L https://nixos.org/nix/install | sh -s -- --no-daemon --no-modify-profile
  echo "[entrypoint] Nix installed"
fi

# Restore nix.conf and .nix-profile if home volume is fresh.
if [ ! -e "$HOME/.config/nix/nix.conf" ]; then
  mkdir -p "$HOME/.config/nix"
  echo "experimental-features = nix-command flakes" > "$HOME/.config/nix/nix.conf"
fi

# Source nix environment so subcommands (nix-channel, etc.) get NIX_PATH and other vars.
if [ -e "$HOME/.nix-profile/etc/profile.d/nix.sh" ]; then
  . "$HOME/.nix-profile/etc/profile.d/nix.sh"
fi

ENV_FILE="/opt/data/.env"

if ! grep -q '^API_SERVER_KEY=' "$ENV_FILE" 2>/dev/null; then
  KEY=$(openssl rand -hex 32)
  echo "API_SERVER_KEY=$KEY" >> "$ENV_FILE"
  echo "[entrypoint] Generated new API_SERVER_KEY and appended to $ENV_FILE"
else
  echo "[entrypoint] API_SERVER_KEY already set, skipping"
fi

exec /opt/hermes/docker/entrypoint.sh "$@"
