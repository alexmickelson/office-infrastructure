#!/bin/bash
# generate-kubeconfig.sh
# Run this after applying the RBAC manifests to generate a kubeconfig for the hermes user.
# Usage: ./generate-kubeconfig.sh > hermes.kubeconfig

set -euo pipefail

NAMESPACE="hermes"
SERVICE_ACCOUNT="hermes"
SECRET_NAME="hermes-token"

# Get cluster info from current kubeconfig context
CURRENT_CONTEXT=$(kubectl config current-context)
CLUSTER_NAME=$(kubectl config view -o jsonpath="{.contexts[?(@.name == \"$CURRENT_CONTEXT\")].context.cluster}")
SERVER=$(kubectl config view -o jsonpath="{.clusters[?(@.name == \"$CLUSTER_NAME\")].cluster.server}")
CA_DATA=$(kubectl config view --raw -o jsonpath="{.clusters[?(@.name == \"$CLUSTER_NAME\")].cluster.certificate-authority-data}")

# If CA_DATA is empty, try reading the file path
if [ -z "$CA_DATA" ]; then
  CA_FILE=$(kubectl config view -o jsonpath="{.clusters[?(@.name == \"$CLUSTER_NAME\")].cluster.certificate-authority}")
  if [ -n "$CA_FILE" ]; then
    CA_DATA=$(base64 -w 0 "$CA_FILE")
  fi
fi

# Get token from the Secret
TOKEN=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath="{.data.token}" | base64 -d)

cat <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: ${CLUSTER_NAME}
    cluster:
      server: ${SERVER}
      certificate-authority-data: ${CA_DATA}
contexts:
  - name: hermes@${CLUSTER_NAME}
    context:
      cluster: ${CLUSTER_NAME}
      namespace: ${NAMESPACE}
      user: hermes
users:
  - name: hermes
    user:
      token: ${TOKEN}
current-context: hermes@${CLUSTER_NAME}
EOF
