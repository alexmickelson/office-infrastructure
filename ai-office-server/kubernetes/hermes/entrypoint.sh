#!/bin/bash
set -e

# ── Bootstrap Nix into the persistent /nix volume (runs as root) ────────────
if [ "$(id -u)" = "0" ]; then
    chown hermes:hermes /nix

    if ! find /nix/store -maxdepth 4 -name nix -type f 2>/dev/null | grep -q .; then
        echo "[entrypoint] Bootstrapping Nix into persistent volume..."
        gosu hermes env HOME=/opt/data bash -c 'curl -fsSL https://nixos.org/nix/install | bash -s -- --no-daemon --no-modify-profile'
    fi
fi

# ── Hand off to the upstream Hermes entrypoint ───────────────────────────────
exec /opt/hermes/docker/entrypoint.sh "$@"