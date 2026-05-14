

## Install

```bash
helm repo add tailscale https://pkgs.tailscale.com/helmcharts
helm repo update
helm upgrade \
  --install \
  tailscale-operator \
  tailscale/tailscale-operator \
  --namespace=tailscale \
  --create-namespace \
  --set-string oauth.clientId="<OAauth client ID>" \
  --set-string oauth.clientSecret="<OAuth client secret>" \
  --wait
```


## CoreDNS split-DNS fix

k3s sets `/etc/resolv.conf` to use Tailscale MagicDNS (`100.100.100.100`) as the nameserver.
CoreDNS forwards all external queries there by default, creating a circular dependency:
CoreDNS crashes → Tailscale proxy can't resolve `kubernetes.default.svc` → crashes → CoreDNS can't come up.

Fix: forward only `.ts.net` to MagicDNS and use `8.8.8.8` for everything else.

```fish
set corefile "ts.net {
    forward . 100.100.100.100
}
.:53 {
    errors
    health
    ready
    kubernetes cluster.local in-addr.arpa ip6.arpa {
      pods insecure
      fallthrough in-addr.arpa ip6.arpa
    }
    hosts /etc/coredns/NodeHosts {
      ttl 60
      reload 15s
      fallthrough
    }
    prometheus :9153
    cache 30
    loop
    reload
    loadbalance
    import /etc/coredns/custom/*.override
    forward . 8.8.8.8 1.1.1.1
}"

kubectl create configmap coredns -n kube-system \
  --from-literal=Corefile=$corefile \
  --dry-run=client -o yaml | kubectl apply -f -

```
