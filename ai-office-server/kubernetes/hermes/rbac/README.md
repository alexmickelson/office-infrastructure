# Hermes Kubernetes RBAC (Read-Only)

This folder contains read-only RBAC manifests for the `hermes` ServiceAccount.
No Secret access is granted.

## Files

| File | Purpose |
|------|---------|
| `01-namespace.yml` | Creates the `hermes` namespace |
| `02-serviceaccount.yml` | Creates the `hermes` ServiceAccount |
| `03-clusterrole.yml` | Read-only ClusterRole (excludes Secrets) |
| `04-clusterrolebinding.yml` | Binds the ClusterRole to the ServiceAccount |
| `05-token-secret.yml` | Creates a long-lived ServiceAccount token |
| `generate-kubeconfig.sh` | Generates a kubeconfig for the hermes user |

## What is Granted

- Read (`get`, `list`, `watch`) on all common cluster resources across all namespaces
- Pods, Services, Deployments, Nodes, Events, ConfigMaps, etc.
- RBAC objects (read-only)
- Metrics (via `metrics.k8s.io`)

## What is Excluded

- **Secrets** (no access)
- No write/create/delete/update permissions on anything

## Setup Steps

### 1. Apply the manifests

```bash
kubectl apply -f ai-office-server/kubernetes/hermes/rbac/
```

### 2. Generate the kubeconfig

```bash
cd ai-office-server/kubernetes/hermes/rbac
chmod +x generate-kubeconfig.sh
./generate-kubeconfig.sh > hermes.kubeconfig
```

### 3. Test read-only access

```bash
KUBECONFIG=hermes.kubeconfig kubectl get pods -A
KUBECONFIG=hermes.kubeconfig kubectl get nodes

# This should fail
KUBECONFIG=hermes.kubeconfig kubectl get secrets
```

## Cleanup

```bash
kubectl delete namespace hermes
kubectl delete clusterrole hermes-readonly
kubectl delete clusterrolebinding hermes-readonly-binding
```
