https://istio.io/latest/docs/setup/install/helm/


base -> crds and roles
cni -> per-node daemonset that manages netowrking
istiod -> actual controller
gateway -> ingress replacement

```bash
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update
kubectl create namespace istio-system --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install istio-base istio/base \
    -n istio-system \
    --set defaultRevision=default
helm upgrade --install istio-cni istio/cni -n istio-system --wait \
  --set cni.cniBinDir=/var/lib/rancher/k3s/data/cni \
  --set cni.cniConfDir=/var/lib/rancher/k3s/agent/etc/cni/net.d
```


configure kube gateway crd's

```bash
kubectl get crd gateways.gateway.networking.k8s.io &> /dev/null || \
{ kubectl kustomize "github.com/kubernetes-sigs/gateway-api/config/crd?ref=v1.4.0" | kubectl apply -f -; }

kubectl get crd | grep gateway
```


```bash
helm upgrade --install istiod istio/istiod -n istio-system --wait
```


```bash
helm upgrade --install istio-ingressgateway istio/gateway -n istio-system \
  --set service.loadBalancerClass=tailscale
```


## Uninstall

```bash
helm uninstall istio-ingressgateway -n istio-system
helm uninstall istiod -n istio-system
helm uninstall istio-cni -n istio-system
helm uninstall istio-base -n istio-system
```
