#! /usr/bin/env nix-shell
#! nix-shell -i bash -p bash yq

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

for HOST in "${HOSTS[@]}"; do
  TARGET="$SSH_USER@$HOST"
  BACKUP_DIR="$LOCAL_BACKUP_DIR/$HOST"
  REMOTE_DIR="$REMOTE_DIR"

  echo "[INFO] Restoring Tailscale backup to $TARGET..."

  echo "[INFO] Stopping and starting tailscaled on $TARGET..."
  ssh "$TARGET" \
    "sudo -S bash -c 'systemctl start tailscaled && \
      systemctl stop tailscaled'"

  echo "[INFO] Copying backup to $TARGET..."
  ssh "$TARGET" \
    "rm -rf ~/tailscale_restore \
      && mkdir -p ~/tailscale_restore"

  scp -r "$BACKUP_DIR/tailscale_backup/." "$TARGET:~/tailscale_restore/"

  echo "[INFO] Restoring backup to $REMOTE_DIR on $TARGET..."
  ssh "$TARGET" \
    "sudo -S bash -c '\
      rm -rf $REMOTE_DIR && \
      mv /home/$SSH_USER/tailscale_restore $REMOTE_DIR && \
      chown -R root:root $REMOTE_DIR && \
      systemctl start tailscaled\
    '"

  echo "[SUCCESS] Restore to $HOST completed."
done