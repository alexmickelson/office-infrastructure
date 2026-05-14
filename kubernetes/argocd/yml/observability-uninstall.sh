#!/usr/bin/env bash
set -e
# export KUBECONFIG=~/.kube/office-framework-config

# Remove Kiali CR first so the operator can clean up before it's removed
kubectl delete kiali --all --all-namespaces --ignore-not-found

helm uninstall kiali-operator -n kiali-operator --ignore-not-found
kubectl delete crd kialis.kiali.io --ignore-not-found

helm uninstall jaeger -n monitoring --ignore-not-found
helm uninstall prometheus -n monitoring --ignore-not-found

