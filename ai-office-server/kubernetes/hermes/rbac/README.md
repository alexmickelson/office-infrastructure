# Hermes Kubernetes RBAC

Read-only cluster access for the `hermes` service account. No Secret access.

## Setup

```bash
kubectl apply -f ai-office-server/kubernetes/hermes/rbac/
./generate-kubeconfig.sh > hermes.kubeconfig
```

## Test

```bash
KUBECONFIG=hermes.kubeconfig kubectl get pods -A   # works
KUBECONFIG=hermes.kubeconfig kubectl get secrets     # fails (expected)
```

## Cleanup

```bash
kubectl delete -f ai-office-server/kubernetes/hermes/rbac/
```
