#! /usr/bin/env bash
# k3s_cluster_reset.sh
# Usage: ./k3s_cluster_reset.sh
# Edit SSH_USER, CONTROL_PLANE_NODES and WORKER_NODES arrays as needed.

SSH_USER="root"

CONTROL_PLANE_NODES=(
  "144.17.92.11"
  "144.17.92.12"
  "144.17.92.13"
)

WORKER_NODES=(
  "144.17.92.14"
  "144.17.92.15"
  "144.17.92.21"
)

ALL_NODES=("${CONTROL_PLANE_NODES[@]}" "${WORKER_NODES[@]}")

# Confirmation prompt
read -n 1 -r -p "[WARNING] This will uninstall k3s and delete cluster data on ALL nodes. Are you sure you want to continue? [y/N] " CONFIRM
if [[ ! $CONFIRM =~ ^[Yy]$ ]]; then
  echo -e "\n[ABORTED] No changes made."
  exit 1
fi

echo
for NODE in "${ALL_NODES[@]}"; do
  echo "[INFO] Resetting k3s on $NODE..."
  ssh "$SSH_USER@$NODE" "k3s-uninstall.sh || true"
  ssh "$SSH_USER@$NODE" "rm -rf /var/lib/rancher/k3s/server/db/etcd /var/lib/rancher/k3s/server/tls"
  echo "[SUCCESS] $NODE reset complete."
done

echo "[SUCCESS] All nodes have been reset."
