

## Auth

```bash
az login
az account show
```

## Create

```bash
# Resource group
az group create \
  --name test-kuberentes-resource-group \
  --location westus3

# AKS cluster
az aks create \
  --resource-group test-kuberentes-resource-group \
  --name office-aks \
  --location westus3 \
  --node-count 1 \
  --node-vm-size Standard_A4_v2 \
  --vm-set-type VirtualMachineScaleSets \
  --load-balancer-sku standard \
  --network-plugin azure 
  --tier free \
  --generate-ssh-keys \
  --enable-cluster-autoscaler \
  --min-count 1 \
  --max-count 5 \
  --cluster-autoscaler-profile scan-interval=30s,scale-down-unneeded-time=5m,scale-down-delay-after-add=5m \
  --enable-gateway-api

# Fetch kubeconfig
az aks get-credentials \
  --resource-group test-kuberentes-resource-group \
  --name office-aks \
  --file ~/.kube/azureconfig \
  --overwrite-existing
```

## Inspect

```bash
az group show \
  --name test-kuberentes-resource-group \
  --output table

az aks show \
  --resource-group test-kuberentes-resource-group \
  --name office-aks \
  --output table

az aks nodepool list \
  --resource-group test-kuberentes-resource-group \
  --cluster-name office-aks \
  --output json
```

## Update node pool (drift fix)

```bash
# Toggle / update autoscaler bounds
az aks nodepool update \
  --resource-group test-kuberentes-resource-group \
  --cluster-name office-aks \
  --name <pool-name> \
  --enable-cluster-autoscaler \
  --min-count 1 \
  --max-count 5

# Re-sync autoscaler bounds only (autoscaler already enabled)
az aks nodepool update \
  --resource-group test-kuberentes-resource-group \
  --cluster-name office-aks \
  --name <pool-name> \
  --update-cluster-autoscaler \
  --min-count 1 \
  --max-count 5
```

> `vm_size` cannot be changed on an existing node pool; recreate it instead.

## Teardown

```bash
az aks delete \
  --resource-group test-kuberentes-resource-group \
  --name office-aks \
  --yes --no-wait

az group delete \
  --name test-kuberentes-resource-group \
  --yes --no-wait
```

## References

- <https://learn.microsoft.com/en-us/azure/aks/cluster-autoscaler?utm_source=chatgpt.com&tabs=azure-cli>
- <https://josephrperez.com/posts/aks-cluster-autoscaling-strategies-comprehensive-guide-best-practices/?utm_source=chatgpt.com>

