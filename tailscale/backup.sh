#! /usr/bin/env nix-shell
#! nix-shell -i bash -p bash rsync


# List of hosts (one per line)
HOSTS=(
  "144.17.92.11" 
  "144.17.92.12" 
  "144.17.92.13" 
  "144.17.92.14" 
  "144.17.92.15"
)
# Remote tailscale directory to backup
REMOTE_DIR="/var/lib/tailscale"
# Local backup base directory
LOCAL_BACKUP_DIR="./backups"

mkdir -p "$LOCAL_BACKUP_DIR"

for HOST in "${HOSTS[@]}"; do
    TARGET="alex@$HOST"
    echo "----------------------Backing up $HOST----------------------"
    mkdir -p "$LOCAL_BACKUP_DIR/$HOST"
    ssh "$TARGET" "sudo -S cp -r $REMOTE_DIR ~/tailscale_backup && sudo -S chown -R alex:alex ~/tailscale_backup"
    scp -r "$TARGET:~/tailscale_backup/" "$LOCAL_BACKUP_DIR/$HOST/"
    ssh "$TARGET" "rm -rf ~/tailscale_backup"
    if [ $? -eq 0 ]; then
        echo "Backup of $HOST completed."
    else
        echo "Backup of $HOST failed."
    fi
done