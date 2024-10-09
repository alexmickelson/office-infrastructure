
## k3s 

`curl -sfL https://get.k3s.io | sh -`


first node:

`curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server" sh -s - --cluster-init --disable=traefik --node-taint "" `

token in `/var/lib/rancher/k3s/server/token`


uninstall with `/usr/local/bin/k3s-uninstall.sh`

kubeconfig in `/etc/rancher/k3s/k3s.yaml`


add server node
```bash
curl -sfL https://get.k3s.io | K3S_TOKEN=K101f2d607d80a37e0056012293361b7cd5516d65f7519678a642c7b256dc7477a8::server:29c9fcc2ef70c34ef84c8f6e256274b9 K3S_URL=https://144.17.92.11:6443 sh -s - server  --disable=traefik --node-taint ""
```


add worker node
```bash
curl -sfL https://get.k3s.io | K3S_TOKEN=K101f2d607d80a37e0056012293361b7cd5516d65f7519678a642c7b256dc7477a8::server:29c9fcc2ef70c34ef84c8f6e256274b9 K3S_URL=https://144.17.92.11:6443 sh -s - 
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

`kubectl create namespace alex`

untaint all nodes: `kubectl taint nodes --all node-role.kubernetes.io/master-`
`kubectl taint node alex-office2 node-role.kubernetes.io/master-`

<https://github.com/kubernetes/ingress-nginx/blob/main/docs/deploy/index.md#bare-metal-clusters>


`kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.0/deploy/static/provider/baremetal/deploy.yaml`

```
kubectl patch ingressclass nginx \
  --patch '{"metadata": {"annotations": {"ingressclass.kubernetes.io/is-default-class": "true"}}}'
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


```
kubectl create namespace metrics-server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/high-availability.yaml
(downloaded as high-availability.yml)
```


## update all kubeconfigs after reinstall

scp source file to `/root/kubeconfig`

```bash
find /home -type f -path '*/.kube/config' -exec sh -c 'cat /root/kubeconfig > "$1"' _ {} \;
```