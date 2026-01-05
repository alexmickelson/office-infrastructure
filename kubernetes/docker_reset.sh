#! /usr/bin/env bash
# docker_reset.sh
# Usage: ./docker_reset.sh
# Edit SSH_USER and NODES arrays as needed.

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
read -n 1 -r -p "[WARNING] This will stop and remove all Docker containers and prune all unused data on ALL nodes. Are you sure you want to continue? [y/N] " CONFIRM
if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
  echo -e "\n[ABORTED] No changes made."
  exit 1
fi

echo
for NODE in "${NODES[@]}"; do
  echo "[INFO] Resetting Docker on $NODE..."
  
  # Stop all running containers
  ssh "$SSH_USER@$NODE" "docker stop \$(docker ps -aq) 2>/dev/null || true"
  
  # Remove all containers
  ssh "$SSH_USER@$NODE" "docker rm \$(docker ps -aq) 2>/dev/null || true"
  
  # Full system prune
  ssh "$SSH_USER@$NODE" "docker system prune -af --volumes 2>/dev/null || true"
  
  echo "[SUCCESS] $NODE reset complete."
done

echo "[SUCCESS] All nodes have been reset."
