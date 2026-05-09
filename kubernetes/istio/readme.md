https://istio.io/latest/docs/setup/install/helm/


base -> crds and roles
cni -> per-node daemonset that manages netowrking
istiod -> actual controller
gateway -> ingress replacement

```bash
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update
helm upgrade --install istio-base istio/base \
    -n istio-system \
    --set defaultRevision=default \
    --create-namespace
helm upgrade --install istio-cni istio/cni -n istio-system --wait
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
helm upgrade --install istio-ingressgateway istio/gateway -n istio-system
```