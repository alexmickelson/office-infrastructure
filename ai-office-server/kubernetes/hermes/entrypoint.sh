#!/bin/bash
set -e

# ── 1. Root-only bootstrap ──────────────────────────────────────────────────
if [ "$(id -u)" = "0" ]; then
    chown hermes:hermes /nix

    if ! find /nix/store -maxdepth 4 -name nix -type f 2>/dev/null | grep -q .; then
        echo "[entrypoint] Bootstrapping Nix into persistent volume..."
        su -p hermes -c 'HOME=/opt/data bash -c "curl -fsSL https://nixos.org/nix/install | bash -s -- --no-daemon --no-modify-profile"'
    fi
fi

# ── 2. Ensure flakes + PATH for whatever user ends up running ───────────────
mkdir -p /opt/data/.config/nix
if [ ! -f /opt/data/.config/nix/nix.conf ]; then
    echo "experimental-features = nix-command flakes" > /opt/data/.config/nix/nix.conf
fi

# Make the profile visible even when HOME=/home/hermes
mkdir -p /home/hermes/.local/state/nix/profiles
ln -sf /opt/data/.local/state/nix/profiles/profile /home/hermes/.nix-profile 2>/dev/null || true
ln -sf /opt/data/.local/state/nix/profiles/profile /home/hermes/.local/state/nix/profiles/profile 2>/dev/null || true

export PATH="/opt/data/.nix-profile/bin:$PATH"

# ── 3. Hand off to upstream ─────────────────────────────────────────────────
exec /opt/hermes/docker/entrypoint.sh "$@"