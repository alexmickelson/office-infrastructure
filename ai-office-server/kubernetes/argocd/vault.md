
```bash
# create vault
kubectl exec -n vault -ti vault-0 -- vault operator init -key-shares=1 -key-threshold=1

# unseal
vault operator unseal

# Enable KV v2 secrets engine:
vault secrets enable -path=secret kv-v2
```

Enable Kubernetes auth:
```bash
vault auth enable kubernetes
vault write auth/kubernetes/config kubernetes_host="https://kubernetes.default.svc:443"
vault policy write external-secrets-operator-policy - <<'EOF'
path "secret/data/*" {
capabilities = ["read"]
}
path "secret/metadata/*" {
capabilities = ["read", "list"]
}
EOF

vault write auth/kubernetes/role/external-secrets-operator-policy-role \
  bound_service_account_names=external-secrets \
  bound_service_account_namespaces=external-secrets-system \
  policies=external-secrets-operator-policy \
  ttl=1h
```