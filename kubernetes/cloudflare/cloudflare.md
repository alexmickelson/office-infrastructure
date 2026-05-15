
# Cloudflare Tunnel

Managed by ArgoCD via `kubernetes/argocd/yml/cloudflared.yml`.

`credentials.json` is gitignored — generate or recover it, seal it, then commit the sealed secret.


## Seal the credentials secret

```bash
nix-shell -p kubeseal --run '
kubectl create secret generic cloudflared-credentials \
  --namespace cloudflared \
  --from-file=credentials.json=kubernetes/cloudflare/credentials.json \
  --dry-run=client -o yaml \
  | kubeseal --controller-namespace kube-system -o yaml \
  > kubernetes/cloudflare/yml/cloudflared-credentials-sealed.yml
'
```

## external dns

use <https://github.com/kubernetes-sigs/external-dns> to create dns records when you make the kubernetes routes

dash.cloudflare.com → My Profile → API Tokens with Edit zone DNS permission

```bash
kubectl create secret generic external-dns-cloudflare \
  --namespace external-dns \
  --from-literal=cloudflare-api-token="<YOUR_TOKEN>"
```