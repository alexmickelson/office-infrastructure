
# Cloudflare Tunnel

Managed by ArgoCD via `kubernetes/argocd/yml/cloudflared.yml`.

```bash
kubectl apply -f kubernetes/argocd/yml/cloudflared.yml
```

The tunnel token must be created manually as a secret (not stored in Git):

```bash
kubectl create namespace cloudflared
kubectl delete secret cloudflared-cloudflare-tunnel-remote -n cloudflared
kubectl create secret generic cloudflared-cloudflare-tunnel-remote \
    -n cloudflared \
    --from-literal=tunnelToken=<paste-raw-token-here>
```