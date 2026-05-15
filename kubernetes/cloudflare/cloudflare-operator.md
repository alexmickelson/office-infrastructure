
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