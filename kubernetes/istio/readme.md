https://istio.io/latest/docs/setup/install/helm/

## Components

- **istio-base** — CRDs and cluster roles (sync wave 0)
- **istio-cni** — per-node DaemonSet for networking (sync wave 1); uses k3s CNI paths
- **istiod** — control plane (sync wave 2)
- **main-gateway** — `Gateway` resource using Kubernetes Gateway API, managed via `argocd-server-access.yml`; no legacy `istio-ingressgateway` Deployment needed

## Managed by ArgoCD

```bash
kubectl apply -f kubernetes/argocd/yml/istio.yml
```
## Gateway API CRDs

Managed by ArgoCD via `kubernetes/argocd/yml/gateway-api-crds.yml` at version `v1.5.1`. Sync wave `-1` ensures CRDs exist before any Istio component syncs.

```bash
kubectl apply -f kubernetes/argocd/yml/gateway-api-crds.yml
```
