
## k3s 

`curl -sfL https://get.k3s.io | sh -`


first node:

`curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server" sh -s - --cluster-init --disable=traefik --node-taint ""  --tls-san 100.96.241.36`


`--tls-san` is to generate certificate with additional valid ip's

token in `/var/lib/rancher/k3s/server/token`

uninstall with `/usr/local/bin/k3s-uninstall.sh`

kubeconfig in `/etc/rancher/k3s/k3s.yaml`


add server node
```bash
curl -sfL https://get.k3s.io | K3S_TOKEN=<token> K3S_URL=https://144.17.92.11:6443 sh -s - server  \
  --disable=traefik \
  --node-taint "" \
  --tls-san 100.96.241.36 \
  --tls-san alex-office1.tail8bfa2.ts.net \
  --tls-san alex-office2.tail8bfa2.ts.net \
  --tls-san alex-office3.tail8bfa2.ts.net \
  --tls-san alex-office4.tail8bfa2.ts.net \
  --tls-san alex-office5.tail8bfa2.ts.net 
```


when removing a node to re-add it, clean up etcd stuff:
```bash
sudo rm -rf /var/lib/rancher/k3s/server/db/etcd
sudo rm -rf /var/lib/rancher/k3s/server/tls
```


add worker node
```bash
curl -sfL https://get.k3s.io | K3S_TOKEN=<token> K3S_URL=https://144.17.92.11:6443 sh -s - 
```

upgrade nodes in place
```bash
  # --node-taint "" \ # breaks updates
curl -sfL https://get.k3s.io | sh -s - server  \
  --disable=traefik \
  --kube-apiserver-arg="feature-gates=MaxUnavailableStatefulSet=true" \
  --kube-controller-manager-arg="feature-gates=MaxUnavailableStatefulSet=true" \
  --tls-san 100.96.241.36 \
  --tls-san alex-office1.tail8bfa2.ts.net \
  --tls-san alex-office2.tail8bfa2.ts.net \
  --tls-san alex-office3.tail8bfa2.ts.net \
  --tls-san alex-office4.tail8bfa2.ts.net \
  --tls-san alex-office5.tail8bfa2.ts.net
# worker (same as adding)
curl -sfL https://get.k3s.io | K3S_TOKEN=<token> K3S_URL=https://144.17.92.11:6443 sh -s - 

```

<https://docs.k3s.io/quick-start>

<!-- k0s has betrayed me -->
<!-- ## install cluster
```bash
k0sctl apply --config k0sctl.yaml
```

get up to date starting config with `k0sctl init`


```bash
sudo k0s install controller --enable-metrics-scraper
``` -->

## ingress

<!-- 

## reuse pod IP's

`kubectl create namespace alex`

untaint all nodes: `kubectl taint nodes --all node-role.kubernetes.io/master-`
`kubectl taint node alex-office2 node-role.kubernetes.io/master-`

<https://github.com/kubernetes/ingress-nginx/blob/main/docs/deploy/index.md#bare-metal-clusters>


`kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.0/deploy/static/provider/baremetal/deploy.yaml`

```
kubectl patch ingressclass nginx \
  --patch '{"metadata": {"annotations": {"ingressclass.kubernetes.io/is-default-class": "true"}}}'
``` -->


```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.kind=DaemonSet \
  --set controller.hostPort.enabled=true \
  --set controller.hostPort.ports.http=80 \
  --set controller.hostPort.ports.https=443 \
  --set controller.service.type=NodePort \
  --set controller.allowSnippetAnnotations=true \
  --set controller.config.annotations-risk-level=Critical \
  --set controller.metrics.enabled=false \
  --set controller.ingressClassResource.default=true
```

### metallb

```bash
helm repo add metallb https://metallb.github.io/metallb
helm install metallb metallb/metallb \
  --namespace metallb \
  --create-namespace
kubectl apply -f metallb.yml
```

### cert manager

first: <https://github.com/cert-manager/cert-manager>

<https://dev.to/javiermarasco/https-with-ingress-controller-cert-manager-and-duckdns-in-akskubernetes-2jd1>


```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install \
  cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.16.1 \
  --set crds.enabled=true

# helm install \
#                             cert-manager jetstack/cert-manager \
#                             --namespace cert-manager \
#                             --version v1.2.0 \
#                             --set 'extraArgs={--dns01-recursive-nameservers=8.8.8.8:53\,1.1.1.1:53}' \
#                             --create-namespace \
#                             --set installCRDs=true
kubectl get pods --namespace cert-manager --watch


git clone https://github.com/ebrianne/cert-manager-webhook-duckdns.git
cd cert-manager-webhook-duckdns

DUCKDNS_TOKEN=<duckdns token>
MY_NAME=alex
EMAIL=alexmickelson96@gmail.com

helm install cert-manager-webhook-duckdns-$MY_NAME \
     --namespace cert-manager \
     --set duckdns.token=$DUCKDNS_TOKEN \
     --set clusterIssuer.production.create=true \
     --set clusterIssuer.staging.create=true \
     --set clusterIssuer.email=$EMAIL \
     --set logLevel=2 \
     ./deploy/cert-manager-webhook-duckdns

kubectl get clusterissuer
```


## nfs storage

nfs server /etc/exports

```
/data 144.17.92.0/24(rw,no_subtree_check,no_root_squash)
```
- `sudo apt install -y nfs-server`
- `sudo apt install -y nfs-common` for clients
- `sudo systemctl enable --now nfs-server`
- `exportfs -ra`



<https://kubedemy.io/kubernetes-storage-part-1-nfs-complete-tutorial>

```bash
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner

helm install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --create-namespace \
  --namespace nfs-provisioner \
  --set nfs.server=144.17.92.14 \
  --set nfs.path=/data

kubectl patch storageclass nfs-client -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```


## Image Registry

https://hub.docker.com/_/registry


<!-- in office 2 -->

```bash
docker run -d -p 0.0.0.0:5000:5000 --restart always --name image_registry registry:2
```

<https://docs.k0sproject.io/stable/runtime/?h=runtime#using-docker-as-the-container-runtime>

/etc/k0s/containerd.toml

```
version = 2
root = "/var/lib/k0s/containerd"
state = "/run/k0s/containerd"

[grpc]
  address = "/run/k0s/containerd.sock"
[plugins."io.containerd.grpc.v1.cri".registry]
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors]
        [plugins."io.containerd.grpc.v1.cri".registry.mirrors."docker.io"]
          endpoint = ["https://registry-1.docker.io"]
        [plugins."io.containerd.grpc.v1.cri".registry.mirrors."144.17.92.12:5000"]
          endpoint = ["http://144.17.92.12:5000"]
      [plugins."io.containerd.grpc.v1.cri".registry.configs]
        [plugins."io.containerd.grpc.v1.cri".registry.configs."144.17.92.12:5000".tls]
          insecure_skip_verify = true

```


## metrics


```bash
kubectl create namespace metrics-server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/high-availability-1.21+.yaml
```
(downloaded as high-availability.yml)


https://artifacthub.io/packages/helm/prometheus-community/kube-state-metrics/
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
# helm install [RELEASE_NAME] prometheus-community/kube-state-metrics [flags]
helm install \
  --namespace monitoring \
  kube-state-metrics \
  prometheus-community/kube-state-metrics
```
<!-- metrics endpoint: kube-state-metrics.monitoring.svc.cluster.local:8080/metrics -->

## update all kubeconfigs after reinstall

scp source file to `/root/kubeconfig`

```bash
find /home -type f -path '*/.kube/config' -exec sh -c 'cat /root/kubeconfig > "$1"' _ {} \;
```
