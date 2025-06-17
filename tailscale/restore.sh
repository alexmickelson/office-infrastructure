#! /usr/bin/env nix-shell
#! nix-shell -i bash -p bash

HOSTS=(
  "144.17.92.11" 
  "144.17.92.12" 
  "144.17.92.13" 
  "144.17.92.14" 
  "144.17.92.15"
)

LOCAL_BACKUP_DIR="./backups"

for HOST in "${HOSTS[@]}"; do
    TARGET="alex@$HOST"
    BACKUP_DIR="$LOCAL_BACKUP_DIR/$HOST"
    REMOTE_DIR="/var/lib/tailscale"

    echo "Restoring Tailscale backup to $TARGET..."

    # 1. SSH onto the target, stop tailscale, then start it (to ensure it's running, then stopped cleanly)
    ssh "$TARGET" "sudo -S systemctl start tailscaled && sudo systemctl stop tailscaled"

    # 2. Move the backup directory onto the machine with admin access
    scp -r "$BACKUP_DIR/" "$HOST:~/tailscale_restore/"
    ssh "$TARGET" "sudo -S rm -rf $REMOTE_DIR && \
        sudo-S mv ~/tailscale_restore $REMOTE_DIR && \
        sudo -S chown -R _tailscale:_tailscale $REMOTE_DIR"

    # 3. Restart tailscale on the destination
    ssh "$TARGET" "sudo -S systemctl start tailscaled"

    echo "Restore to $HOST completed."

done