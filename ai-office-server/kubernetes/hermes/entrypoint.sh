#!/bin/bash
set -e

# ── 1. Root-only bootstrap ──────────────────────────────────────────────────
if [ "$(id -u)" = "0" ]; then
    chown hermes:hermes /nix

    if ! find /nix/store -maxdepth 4 -name nix -type f 2>/dev/null | grep -q .; then
        echo "[entrypoint] Bootstrapping Nix into persistent volume..."
        # Force a single well-known state dir so we don't get profile schizophrenia
        # between /opt/data/.local and /opt/data/home/.local.
        su -p hermes -c 'HOME=/opt/data NIX_STATE_DIR=/opt/data/.local/state/nix bash -c "curl -fsSL https://nixos.org/nix/install | bash -s -- --no-daemon --no-modify-profile"'
    fi
fi

# ── 2. Ensure flakes config is visible ──────────────────────────────────────
mkdir -p /opt/data/.config/nix
if [ ! -f /opt/data/.config/nix/nix.conf ]; then
    echo "experimental-features = nix-command flakes" > /opt/data/.config/nix/nix.conf
fi
chown -R hermes:hermes /opt/data/.config

# ── 3. Fix /home/hermes ownership and forwarder symlinks ────────────────────
if [ "$(id -u)" = "0" ]; then
    mkdir -p /home/hermes/.local/state/nix/profiles
    ln -sf /opt/data/.local/state/nix/profiles/profile /home/hermes/.nix-profile 2>/dev/null || true
    ln -sf /opt/data/.local/state/nix/profiles/profile /home/hermes/.local/state/nix/profiles/profile 2>/dev/null || true
    chown -R hermes:hermes /home/hermes
fi

# Ensure the running user's home also has the .nix-profile symlink
# (some sessions set HOME=/opt/data or /opt/data/home instead of /home/hermes)
if [ ! -L "$HOME/.nix-profile" ] || [ ! -e "$HOME/.nix-profile" ]; then
    mkdir -p "$HOME/.local/state/nix/profiles"
    ln -sf /opt/data/.local/state/nix/profiles/profile "$HOME/.nix-profile" 2>/dev/null || true
fi

# ── 4. Find Nix binary (not in the profile, in the installer store path) ────
NIX_BIN=$(find /nix/store -maxdepth 4 -name nix -type f 2>/dev/null | head -n1)
if [ -z "$NIX_BIN" ]; then
    echo "[entrypoint] WARNING: nix binary not found in /nix/store" >&2
    # fall through; upstream may deal with it or it may fail later
else
    NIX_DIR=$(dirname "$NIX_BIN")
    export PATH="$NIX_DIR:$HOME/.nix-profile/bin:$PATH"
fi

export NIX_STATE_DIR="/opt/data/.local/state/nix"
export NIX_USER_CONF_FILES="/opt/data/.config/nix/nix.conf"

# ── 5. Make nix-shell work in login *and* interactive shell sessions ────────
# /etc/profile.d/ catches login shells (e.g. `bash -l`, SSH, `su -`)
mkdir -p /etc/profile.d

NIX_PROFILE_SCRIPT="/etc/profile.d/nix-hermes.sh"
cat > "$NIX_PROFILE_SCRIPT" << 'NIXSCRIPT'
# Make Nix available in all login shells
for nix_profile in "$HOME/.nix-profile" "/home/hermes/.nix-profile"; do
    if [ -L "$nix_profile" ]; then
        NIX_PROFILE_BIN=$(readlink -f "$nix_profile")/bin
        if [ -d "$NIX_PROFILE_BIN" ]; then
            export PATH="$NIX_PROFILE_BIN:$PATH"
        fi
        # Source the official Nix environment if available; this sets NIX_PATH etc.
        if [ -e "$nix_profile/etc/profile.d/nix.sh" ]; then
            . "$nix_profile/etc/profile.d/nix.sh"
        fi
        break
    fi
done
# Also inject the raw nix store binary dir in case the profile link is stale
for nix_dir in /nix/store/*/bin; do
    case ":$PATH:" in
        *":$nix_dir:"*) ;;
        *) export PATH="$nix_dir:$PATH" ;;
    esac
done
# Clear command hash so newly installed binaries are found without a new shell
hash -r 2>/dev/null || true
NIXSCRIPT
chmod 644 "$NIX_PROFILE_SCRIPT"

# /etc/bash.bashrc catches interactive non-login shells (e.g. `kubectl exec`)
BASHRC_MARKER="# >>> nix-hermes setup >>>"
if [ -f /etc/bash.bashrc ] && ! grep -qF "$BASHRC_MARKER" /etc/bash.bashrc 2>/dev/null; then
    cat >> /etc/bash.bashrc << BASHRC

$BASHRC_MARKER
if [ -f /etc/profile.d/nix-hermes.sh ]; then
    . /etc/profile.d/nix-hermes.sh
fi
# <<< nix-hermes setup <<<
BASHRC
fi

# ── 6. Install .bashrc for the running user ─────────────────────────────────
# /opt/data is a persistent volume mount, so files copied in the Dockerfile
# are hidden at runtime. We create it here instead.
if [ -f /etc/hermes-bashrc ] && [ ! -f "$HOME/.bashrc" ]; then
    cp /etc/hermes-bashrc "$HOME/.bashrc"
    # If running as root, fix ownership for the hermes user
    if [ "$(id -u)" = "0" ] && [ "$HOME" = "/opt/data" ]; then
        chown hermes:hermes "$HOME/.bashrc"
    fi
fi

# ── 7. Hand off to upstream ─────────────────────────────────────────────────
exec /opt/hermes/docker/entrypoint.sh "$@"