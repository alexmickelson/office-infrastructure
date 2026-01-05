#!/usr/bin/env bash
SSH_USER="root"

NODES=(
  "144.17.92.11"
  "144.17.92.12"
  "144.17.92.13"
  "144.17.92.14"
  "144.17.92.15"
  "144.17.92.21"
)

# Confirmation prompt
read -n 1 -r -p "[WARNING] This will stop and uninstall all GitHub runner services on ALL nodes. Are you sure you want to continue? [y/N] " CONFIRM
if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
  echo -e "\n[ABORTED] No changes made."
  exit 1
fi

echo
for NODE in "${NODES[@]}"; do
  echo "[INFO] Processing GitHub runners on $NODE..."
  
  # Find all GitHub runner services (they typically follow the pattern actions.runner.*)
  RUNNER_SERVICES=$(ssh "$SSH_USER@$NODE" "systemctl list-units --type=service --all --no-pager | grep -E 'actions\.runner\.' | awk '{print \$1}'" 2>/dev/null)
  
  if [ -z "$RUNNER_SERVICES" ]; then
    echo "[INFO] No GitHub runner services found on $NODE"
    continue
  fi
  
  echo "[INFO] Found runner services on $NODE:"
  echo "$RUNNER_SERVICES"
  
  # Stop and disable each service
  while IFS= read -r service; do
    if [ -n "$service" ]; then
      echo "[INFO] Stopping and disabling $service..."
      ssh "$SSH_USER@$NODE" "systemctl stop $service 2>/dev/null || true"
      ssh "$SSH_USER@$NODE" "systemctl disable $service 2>/dev/null || true"
    fi
  done <<< "$RUNNER_SERVICES"
  
  # Remove the service files
  ssh "$SSH_USER@$NODE" "rm -f /etc/systemd/system/actions.runner.*.service 2>/dev/null || true"
  
  # Reload systemd to recognize the changes
  ssh "$SSH_USER@$NODE" "systemctl daemon-reload"
  
  # Optional: Remove runner directories (uncomment if you want to remove the runner installations)
  # ssh "$SSH_USER@$NODE" "rm -rf /opt/actions-runner* 2>/dev/null || true"
  # ssh "$SSH_USER@$NODE" "rm -rf /home/*/actions-runner* 2>/dev/null || true"
  
  echo "[SUCCESS] $NODE processing complete."
done

echo "[SUCCESS] All nodes have been processed."
