# Vault Proxy TLS Behavior Reproduction

## Overview

This runbook validates a simple network pattern:

- Client traffic enters a proxy over HTTP
- The proxy forwards upstream to Vault over HTTPS
- Vault itself remains TLS-only

This is a transport and listener behavior test.

## What this proves

1. Vault can remain TLS-only.
2. A front proxy can expose HTTP and re-encrypt traffic to Vault over HTTPS.
3. Vault does not need its own plaintext listener in this architecture.

## Prerequisites

- Existing Vault Helm release in namespace `vault`
- `kubectl` and `helm` access to cluster
- TLS secret and values files in this folder:
  - `vault-ca-issuer.yaml`
  - `vault-certificate.yaml`
  - `vault-tls-values.yaml`
  - `vault-proxy.yaml`

## 1) Enable TLS for Vault

```bash
kubectl apply -f kubernetes/proxy-tls-behavior/vault-ca-issuer.yaml
kubectl apply -f kubernetes/proxy-tls-behavior/vault-certificate.yaml
kubectl wait --for=condition=Ready certificate/vault-server-tls -n vault --timeout=180s
helm upgrade vault hashicorp/vault -n vault --reuse-values -f kubernetes/proxy-tls-behavior/vault-tls-values.yaml --timeout 10m
```

## 2) Verify Vault listener behavior directly

HTTP request to Vault should fail:

```bash
curl http://vault.vault.svc.cluster.local:8200/v1/sys/health
```

Expected status: `400`  
Expected message: `Client sent an HTTP request to an HTTPS server.`

HTTPS request to Vault should succeed:

```bash
curl -k https://vault.vault.svc.cluster.local:8200/v1/sys/health
```

Expected status: `200`

## 3) Deploy HTTP proxy in front of Vault

```bash
kubectl apply -f kubernetes/proxy-tls-behavior/vault-proxy.yaml
kubectl rollout status deploy/vault-cmp-proxy -n vault --timeout=180s
```

Proxy health endpoint should succeed:

```bash
curl http://vault-cmp-proxy.vault.svc.cluster.local:8080/healthz
```

Expected status: `200`

## 4) Create a test path in Vault (`cmp/`) for route validation

This removes `404 no handler` errors by mounting a backend at `cmp/` and writing test data.

```bash
kubectl exec -n vault vault-0 -- sh -lc '
export VAULT_ADDR=https://127.0.0.1:8200
export VAULT_CACERT=/vault/tls/ca.crt
export VAULT_TOKEN="<token>"
vault secrets enable -path=cmp kv-v2 || true
vault kv put cmp/demo status=ok source=proxy-repro
'
```

## 5) Verify proxy-to-Vault forwarding on mounted route

Through proxy (HTTP ingress):

```bash
curl -H "X-Vault-Token: <token>" \
  http://vault-cmp-proxy.vault.svc.cluster.local:8080/v1/cmp/data/demo
```

Direct to Vault (HTTPS):

```bash
curl -k -H "X-Vault-Token: <token>" \
  https://vault.vault.svc.cluster.local:8200/v1/cmp/data/demo
```

Expected status for both: `200`

## Observed results:

- Direct Vault HTTP health: `400`
- Direct Vault HTTPS health: `200`
- Proxy health (`/healthz`): `200`
- Proxy read (`/v1/cmp/data/demo`) with token: `200`
- Direct Vault read (`/v1/cmp/data/demo`) with token: `200`

## Final conclusion

Vault can stay TLS-only while a proxy accepts HTTP and forwards to Vault over HTTPS. Vault does not require its own unencrypted listener for this pattern.

## Caveat

If Vault must validate original client TLS certificates for identity, avoid TLS termination before Vault. Use TLS passthrough/end-to-end TLS so client certificate identity is preserved.
