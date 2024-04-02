


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