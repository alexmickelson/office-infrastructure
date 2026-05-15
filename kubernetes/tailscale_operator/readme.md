
<https://tailscale.com/docs/features/kubernetes-operator>

## Install

Managed by ArgoCD via `kubernetes/argocd/yml/tailscale.yml`. OAuth credentials must be created as a secret manually:

Create and seal the secret once (requires `kubeseal` and the sealed-secrets controller running):

```bash
kubectl create secret generic operator-oauth \
  --namespace tailscale \
  --from-literal=client_id="<OAuth client ID>" \
  --from-literal=client_secret="<OAuth client secret>"
```

## CoreDNS split-DNS fix

k3s sets `/etc/resolv.conf` to use Tailscale MagicDNS (`100.100.100.100`) as the nameserver.
CoreDNS forwards all external queries there by default, creating a circular dependency:
CoreDNS crashes → Tailscale proxy can't resolve `kubernetes.default.svc` → crashes → CoreDNS can't come up.

Fix: forward only `.ts.net` to MagicDNS and use `8.8.8.8` for everything else. Managed via `kubernetes/argocd/yml/coredns-fix.yml`:

```bash
kubectl apply -f kubernetes/argocd/yml/coredns-fix.yml
```
