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

### Prometheus + Grafana (kube-prometheus-stack)

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add jaegertracing https://jaegertracing.github.io/helm-charts
helm repo add kiali https://kiali.org/helm-charts

helm repo update

helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
  -n monitoring \
  --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
  --set-string 'grafana.grafana\.ini.server.root_url=https://alexmonitoring.snowse.io/grafana' \
  --set-string 'grafana.grafana\.ini.server.serve_from_sub_path=true' \
  --set prometheus.prometheusSpec.externalUrl="https://alexmonitoring.snowse.io/prometheus" \
  --set prometheus.prometheusSpec.routePrefix="/prometheus"
helm upgrade --install jaeger jaegertracing/jaeger \
  -n monitoring \
  --set query.basePath="/jaeger"
helm upgrade --install kiali-operator kiali/kiali-operator \
  --namespace kiali-operator --create-namespace \
  --set cr.create=true \
  --set cr.namespace=istio-system \
  --set cr.spec.server.web_root="/kiali" \
  --set cr.spec.external_services.prometheus.url="http://prometheus-kube-prometheus-prometheus.monitoring.svc.cluster.local:9090" \
  --set cr.spec.external_services.grafana.enabled=true \
  --set cr.spec.external_services.grafana.in_cluster_url="http://prometheus-grafana.monitoring.svc.cluster.local:80" \
  --set cr.spec.external_services.grafana.url="https://alexmonitoring.snowse.io/grafana" \
  --set cr.spec.external_services.tracing.enabled=true \
  --set cr.spec.external_services.tracing.in_cluster_url="http://jaeger-query.monitoring.svc.cluster.local:16686"
```

Grafana is bundled. Import the Istio dashboards (IDs: `7639`, `7636`, `7630`, `11829`, `7645`, `13277`) from grafana.com.
