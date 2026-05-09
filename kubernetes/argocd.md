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


```bash
cat <<EOF | kubectl apply -f -
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: argocd-gateway
  namespace: argocd
spec:
  gatewayClassName: istio
  listeners:
    # - name: http
    #   port: 80
    #   protocol: HTTP
    #   hostname: "alexargocd.example.com"
    - name: https
      port: 443
      protocol: HTTPS
      hostname: "alexargocd.snowse.io"
      tls:
        mode: Terminate
        certificateRefs:
          - name: argocd-tls
EOF
```