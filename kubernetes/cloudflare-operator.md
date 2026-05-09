

```bash
helm repo add cloudflare https://cloudflare.github.io/helm-charts
helm repo update

helm upgrade --install cloudflared cloudflare/cloudflare-tunnel-remote \
    -n cloudflared \
    --create-namespace \
    --set image.tag=2026.3.0

kubectl delete secret cloudflared-cloudflare-tunnel-remote -n cloudflared
kubectl create secret generic cloudflared-cloudflare-tunnel-remote \
    -n cloudflared \
    --from-literal=tunnelToken=<paste-raw-token-here>
```
