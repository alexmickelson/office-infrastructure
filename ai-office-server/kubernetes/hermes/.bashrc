# Nix profile integration for Hermes shells
# Ensures newly installed nix binaries are discoverable

if [ -f /etc/profile.d/nix-hermes.sh ]; then
    . /etc/profile.d/nix-hermes.sh
fi

# Clear command hash cache so nix-installed binaries are found
# immediately after `nix profile install` without starting a new shell
hash -r 2>/dev/null || true
