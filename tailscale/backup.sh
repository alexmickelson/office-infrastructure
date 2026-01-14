#! /usr/bin/env nix-shell
#! nix-shell -i bash -p bash rsync yq

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.yml"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Config file not found at $CONFIG_FILE"
    exit 1
fi

# Read configuration from YAML file
mapfile -t HOSTS < <(yq -r '.hosts[]' "$CONFIG_FILE")
SSH_USER=$(yq -r '.ssh_user' "$CONFIG_FILE")
REMOTE_DIR=$(yq -r '.remote_dir' "$CONFIG_FILE")
LOCAL_BACKUP_DIR=$(yq -r '.local_backup_dir' "$CONFIG_FILE")

# Create backup directory if it doesn't exist
mkdir -p "$LOCAL_BACKUP_DIR"

for HOST in "${HOSTS[@]}"; do
    TARGET="$SSH_USER@$HOST"
    echo "----------------------Backing up $HOST----------------------"
    mkdir -p "$LOCAL_BACKUP_DIR/$HOST"
    ssh "$TARGET" "sudo -S cp -r $REMOTE_DIR ~/tailscale_backup && sudo -S chown -R $SSH_USER:$SSH_USER ~/tailscale_backup"
    scp -r "$TARGET:~/tailscale_backup/" "$LOCAL_BACKUP_DIR/$HOST/"
    ssh "$TARGET" "rm -rf ~/tailscale_backup"
    if [ $? -eq 0 ]; then
        echo "Backup of $HOST completed."
    else
        echo "Backup of $HOST failed."
    fi
done