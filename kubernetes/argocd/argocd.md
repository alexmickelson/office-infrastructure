https://argo-cd.readthedocs.io/en/latest/getting_started/


```bash
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

let gateway handle tls

```bash
kubectl patch configmap argocd-cmd-params-cm \
    -n argocd \
    --type merge \
    -p '{"data":{"server.insecure":"true"}}'
```

## Observability

Managed by ArgoCD via the `yml/` folder. Apply all at once:

```bash
kubectl apply -f kubernetes/argocd/yml/00-monitoring-mtls.yml
kubectl apply -f kubernetes/argocd/yml/prometheus.yml
kubectl apply -f kubernetes/argocd/yml/jaeger.yml
kubectl apply -f kubernetes/argocd/yml/kiali-operator.yml
kubectl apply -f kubernetes/argocd/yml/monitoring-access.yml
```

Grafana is bundled with prometheus. Import the Istio dashboards (IDs: `7639`, `7636`, `7630`, `11829`, `7645`, `13277`) from grafana.com.
