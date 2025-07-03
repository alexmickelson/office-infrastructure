#! /usr/bin/env nix-shell
#! nix-shell -i bash -p bash

HOSTS=(
  # "144.17.92.11" 
  # "144.17.92.12" 
  "144.17.92.13" 
  # "144.17.92.14" 
  # "144.17.92.15"
)

LOCAL_BACKUP_DIR="./backups"

for HOST in "${HOSTS[@]}"; do
  USER="alex"
  TARGET="$USER@$HOST"
  BACKUP_DIR="$LOCAL_BACKUP_DIR/$HOST"
  REMOTE_DIR="/var/lib/tailscale"

  echo "[INFO] Restoring Tailscale backup to $TARGET..."

  echo "[INFO] Stopping and starting tailscaled on $TARGET..."
  ssh "$TARGET" "sudo -S systemctl start tailscaled && sudo -S systemctl stop tailscaled"

  echo "[INFO] Copying backup to $TARGET..."

  ssh "$TARGET" "rm -rf ~/tailscale_restore && mkdir -p ~/tailscale_restore"
  scp -r "$BACKUP_DIR/tailscale_backup/." "$TARGET:~/tailscale_restore/"

  echo "[INFO] Restoring backup to $REMOTE_DIR on $TARGET..."
  ssh "$TARGET" "sudo -S rm -rf $REMOTE_DIR && \
      sudo -S mv ~/tailscale_restore $REMOTE_DIR && \
      sudo -S chown -R _tailscale:_tailscale $REMOTE_DIR"

  echo "[INFO] Restarting tailscaled on $TARGET..."
  ssh "$TARGET" "sudo -S systemctl start tailscaled"

  echo "[SUCCESS] Restore to $HOST completed."
done