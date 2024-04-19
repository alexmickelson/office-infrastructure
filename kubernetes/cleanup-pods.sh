#!/bin/bash

# Delete all evicted pods
kubectl get pods --all-namespaces --field-selector 'status.phase=Failed' -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name --no-headers | \
while read NAMESPACE NAME; do
  kubectl delete pod $NAME --namespace $NAMESPACE
done

# Delete all completed pods
kubectl get pods --all-namespaces --field-selector 'status.phase=Succeeded' -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name --no-headers | \
while read NAMESPACE NAME; do
  kubectl delete pod $NAME --namespace $NAMESPACE
done
