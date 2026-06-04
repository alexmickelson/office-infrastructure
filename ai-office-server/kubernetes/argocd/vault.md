# Vault Setup

## Initialize and Unseal

Initialize:
    kubectl exec -n vault vault-0 -- vault operator init

SAVE THE OUTPUT (5 unseal keys + root token)

Unseal with any 3 keys:
    kubectl exec -n vault vault-0 -- vault operator unseal <key-1>
    kubectl exec -n vault vault-0 -- vault operator unseal <key-2>
    kubectl exec -n vault vault-0 -- vault operator unseal <key-3>

Verify:
    kubectl exec -n vault vault-0 -- vault status

## Basic Usage

Enable KV secrets:
    kubectl exec -n vault vault-0 -- vault secrets enable -path=secret kv-v2

Create secret:
    kubectl exec -n vault vault-0 -- vault kv put secret/myapp/config username=admin password=secret

Access UI:
    kubectl port-forward -n vault vault-0 8200:8200
    # Open http://localhost:8200/ui

## External Secrets Integration

Configure Vault:
    kubectl exec -n vault vault-0 -- vault auth enable kubernetes
    kubectl exec -n vault vault-0 -- vault write auth/kubernetes/config kubernetes_host="https://kubernetes.default.svc:443"
    
    kubectl exec -n vault vault-0 -- vault policy write external-secrets - <<EOF
    path "secret/data/*" {
      capabilities = ["read", "list"]
    }
    EOF
    
    kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/external-secrets \
      bound_service_account_names=external-secrets \
      bound_service_account_namespaces=external-secrets-system \
      policies=external-secrets \
      ttl=24h

Create SecretStore:
    apiVersion: external-secrets.io/v1beta1
    kind: SecretStore
    metadata:
      name: vault-backend
    spec:
      provider:
        vault:
          server: "http://vault.vault.svc.cluster.local:8200"
          path: "secret"
          version: "v2"
          auth:
            kubernetes:
              mountPath: "kubernetes"
              role: "external-secrets"

Create ExternalSecret:
    apiVersion: external-secrets.io/v1beta1
    kind: ExternalSecret
    metadata:
      name: myapp-secret
    spec:
      refreshInterval: 1h
      secretStoreRef:
        name: vault-backend
      target:
        name: myapp-secret
      data:
      - secretKey: username
        remoteRef:
          key: secret/myapp/config
          property: username

## Notes

After pod restart, Vault seals automatically - re-run unseal commands.
Store unseal keys securely (password manager, sealed secrets, etc).
For production, use auto-unseal with cloud KMS.
