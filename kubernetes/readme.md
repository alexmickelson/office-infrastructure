


```
sudo k0s install controller --enable-metrics-scraper
```


## ingress

`kubectl create namespace alex`

untaint all nodes: `kubectl taint nodes --all node-role.kubernetes.io/master-`
`kubectl taint node alex-office2 node-role.kubernetes.io/master-`

<https://github.com/kubernetes/ingress-nginx/blob/main/docs/deploy/index.md#bare-metal-clusters>


`kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.0/deploy/static/provider/baremetal/deploy.yaml`

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
  --set nfs.server=144.17.92.12 \
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