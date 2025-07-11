#! /usr/bin/env bash
# k3s_cluster_install.sh
# Usage: ./k3s_cluster_install.sh
# Edit SSH_USER, CONTROL_PLANE_NODES, and WORKER_NODES arrays as needed.

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

# The first control plane node will initialize the cluster
FIRST_CP_NODE="${CONTROL_PLANE_NODES[0]}"
K3S_TOKEN=""
K3S_URL=""

# Additional SANs for the cluster (edit as needed)
TLS_SANS=(
  "144.17.92.11"
  "144.17.92.12"
  "144.17.92.13"
  "144.17.92.14"
  "144.17.92.15"
  "144.17.92.21"
  "100.96.241.36"
  "100.80.248.138"
  "100.90.251.1"
  "100.112.33.3"
  "100.115.59.64"
  "100.87.13.73"
  "alex-office1.reindeer-pinecone.ts.net"
  "alex-office2.reindeer-pinecone.ts.net"
  "alex-office3.reindeer-pinecone.ts.net"
  "alex-office4.reindeer-pinecone.ts.net"
  "alex-office5.reindeer-pinecone.ts.net"
  "alex-office6.reindeer-pinecone.ts.net"
)

TLS_SAN_ARGS=""
for san in "${TLS_SANS[@]}"; do
  TLS_SAN_ARGS+=" --tls-san $san"
done

# Colors for log output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 1. Install k3s on the first control plane node (cluster-init)
echo -e "${BLUE}[SCRIPT] Installing k3s on first control plane node: $FIRST_CP_NODE${NC}"
ssh "$SSH_USER@$FIRST_CP_NODE" "curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC=\"server\" sh -s - --cluster-init --disable=traefik $TLS_SAN_ARGS"

# 2. Get the token and API URL from the first control plane node
K3S_TOKEN=$(ssh "$SSH_USER@$FIRST_CP_NODE" "cat /var/lib/rancher/k3s/server/node-token")
K3S_URL="https://$FIRST_CP_NODE:6443"

echo -e "${YELLOW}[SCRIPT] K3S_TOKEN: $K3S_TOKEN${NC}"
echo -e "${YELLOW}[SCRIPT] K3S_URL: $K3S_URL${NC}"

# 3. Install k3s on the rest of the control plane nodes
for NODE in "${CONTROL_PLANE_NODES[@]:1}"; do
  echo -e "${BLUE}[SCRIPT] Installing k3s on control plane node: $NODE${NC}"
  ssh "$SSH_USER@$NODE" "curl -sfL https://get.k3s.io | K3S_TOKEN=$K3S_TOKEN K3S_URL=$K3S_URL sh -s - server --disable=traefik $TLS_SAN_ARGS"
done

# 4. Install k3s on worker nodes
for NODE in "${WORKER_NODES[@]}"; do
  echo -e "${GREEN}[SCRIPT] Installing k3s on worker node: $NODE${NC}"
  ssh "$SSH_USER@$NODE" "curl -sfL https://get.k3s.io | K3S_TOKEN=$K3S_TOKEN K3S_URL=$K3S_URL sh -s -"
done



echo -e "${YELLOW}[SCRIPT] Removing taints from control plane nodes...${NC}"
ssh "$SSH_USER@$FIRST_CP_NODE" \
  "KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl taint nodes --all node-role.kubernetes.io/master-"


echo -e "${GREEN}[SCRIPT] k3s cluster installation complete.${NC}"