#!/usr/bin/env bash
set -euo pipefail

export HOME=/home/hermes

# ── 1. Bootstrap Nix on first run ───────────────────────────────────────────
if ! find /nix/store -maxdepth 4 -name nix -type f 2>/dev/null | grep -q .; then
    echo "[entrypoint] Nix not found in persisted /nix. Bootstrapping..."
    # single-user, leaves home rc files alone (we activate manually)
    curl -fsSL https://nixos.org/nix/install | bash -s -- --no-daemon --no-modify-profile
fi

# ── 2. Activate Nix ─────────────────────────────────────────────────────────
NIX_BIN=$(find /nix/store -maxdepth 4 -name nix -type f 2>/dev/null | head -n1)
if [[ -z "$NIX_BIN" ]]; then
    echo "[entrypoint] ERROR: nix binary missing in /nix/store" >&2
    exit 1
fi
NIX_DIR=$(dirname "$NIX_BIN")
export PATH="$NIX_DIR:${PATH}"

# Source the installer env script (sets NIX_PATH, etc.)
if [[ -e /home/hermes/.nix-profile/etc/profile.d/nix.sh ]]; then
    . /home/hermes/.nix-profile/etc/profile.d/nix.sh
elif [[ -e "$NIX_DIR/../etc/profile.d/nix.sh" ]]; then
    . "$NIX_DIR/../etc/profile.d/nix.sh"
fi

# Ensure flakes
mkdir -p /home/hermes/.config/nix
if [[ ! -f /home/hermes/.config/nix/nix.conf ]]; then
    echo "experimental-features = nix-command flakes" > /home/hermes/.config/nix/nix.conf
fi

# ── 3. Re-create profile symlink if lost ────────────────────────────────────
PROFILE_LINK="/home/hermes/.nix-profile"
PROFILE_TARGET="/nix/var/nix/profiles/per-user/hermes/profile"

if [[ ! -L "$PROFILE_LINK" ]] || [[ ! -e "$PROFILE_LINK" ]]; then
    mkdir -p "$(dirname "$PROFILE_TARGET")"
    ln -sf "$PROFILE_TARGET" "$PROFILE_LINK"
fi

# ── 4. Restore tools from flake if missing ──────────────────────────────────
if [[ -f /home/hermes/tools/flake.nix ]] && [[ ! -e /home/hermes/.nix-profile/bin/gh ]]; then
    echo "[entrypoint] Restoring nix tools profile..."
    nix profile install /home/hermes/tools#default || true
fi

# ── 5. Start main process ───────────────────────────────────────────────────
# If the command resolves to a directory (e.g. shadowed by a nix package dir),
# find the real executable by searching PATH without nix-profile entries.
if [[ -n "$1" ]]; then
    RESOLVED=$(command -v "$1" 2>/dev/null || true)
    if [[ -z "$RESOLVED" ]] || [[ -d "$RESOLVED" ]]; then
        SAFE_PATH=$(echo "$PATH" | tr ':' '\n' | grep -v '\.nix-profile' | tr '\n' ':')
        RESOLVED=$(PATH="$SAFE_PATH" command -v "$1" 2>/dev/null || true)
        if [[ -z "$RESOLVED" ]]; then
            echo "[entrypoint] ERROR: cannot find executable for '$1'" >&2
            exit 1
        fi
        shift
        exec "$RESOLVED" "$@"
    fi
fi
exec "$@"