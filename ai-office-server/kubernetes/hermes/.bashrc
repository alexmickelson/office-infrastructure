# Nix profile integration for Hermes shells
# Re-resolves the symlink each invocation so newly installed nix binaries
# are found right after `nix profile install` without starting a new shell.

if [ -L "$HOME/.nix-profile" ]; then
    NIX_PROFILE_BIN=$(readlink -f "$HOME/.nix-profile")/bin
    case ":$PATH:" in
        *":$NIX_PROFILE_BIN:"*) ;;
        *) export PATH="$NIX_PROFILE_BIN:$PATH" ;;
    esac
fi

# Clear command hash cache so nix-installed binaries are found
# immediately after `nix profile install` without starting a new shell
hash -r 2>/dev/null || true
