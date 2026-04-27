# Vault Proxy TLS Behavior Reproduction

## Introduction

This runbook reproduces a proxy + TLS topology used in a real support scenario where clients send HTTP traffic to an internal proxy, and the proxy forwards requests to Vault over HTTPS while Vault remains TLS-only.

To do this, deploy Vault TLS materials (issuer/certificate + Helm TLS values), then deploy an NGINX proxy service in front of Vault. Validate that direct Vault HTTP is rejected, direct Vault HTTPS succeeds, and proxied HTTP requests are successfully re-encrypted upstream to Vault HTTPS.

The outcome confirms this architecture is technically valid for lab testing and serves as a prerequisite transport check before running the CMPv2 PKI integration flow.

## Objective

Validate this transport pattern before running the CMPv2 integration runbook:

- client -> proxy over HTTP
- proxy -> Vault over HTTPS
- Vault remains TLS-only

This runbook validates network and listener behavior only. CMP transaction validation is covered in `cmpv2-pki-integration-guide.md`.

## Preconditions

- Existing Vault Helm release in namespace `vault`
- `kubectl`, `helm`, and `curl` installed and configured for the target cluster
- Valid Vault token with permissions to:
  - enable a secrets engine at `cmp/`
  - write/read `cmp/data/demo`
- Files in this directory:
  - `vault-ca-issuer.yaml`
  - `vault-certificate.yaml`
  - `vault-tls-values.yaml`
  - `vault-proxy.yaml`

## Step 1: Enable TLS for Vault

Apply the issuer and certificate, then upgrade the Helm release with TLS values.

```bash
kubectl apply -f secrets-pki/cmpv2/vault-ca-issuer.yaml
kubectl apply -f secrets-pki/cmpv2/vault-certificate.yaml
kubectl wait --for=condition=Ready certificate/vault-server-tls -n vault --timeout=180s
helm upgrade vault hashicorp/vault -n vault --reuse-values -f secrets-pki/cmpv2/vault-tls-values.yaml --timeout 10m
```

Success criteria:

- `kubectl get certificate vault-server-tls -n vault` shows `READY   True`
- `kubectl rollout status statefulset/vault -n vault --timeout=180s` succeeds

## Step 2: Confirm direct Vault listener behavior

First confirm plaintext HTTP is rejected by Vault.

```bash
curl -i http://vault.vault.svc.cluster.local:8200/v1/sys/health
```

Expected:

- status `400`
- response contains `Client sent an HTTP request to an HTTPS server.`

Then confirm HTTPS succeeds.

```bash
curl -k -i https://vault.vault.svc.cluster.local:8200/v1/sys/health
```

Expected:

- status `200`

## Step 3: Deploy proxy and verify proxy health

Deploy the proxy that accepts HTTP and forwards to Vault over HTTPS.

```bash
kubectl apply -f secrets-pki/cmpv2/vault-proxy.yaml
kubectl rollout status deploy/vault-cmp-proxy -n vault --timeout=180s
```

Verify proxy health endpoint.

```bash
curl -i http://vault-cmp-proxy.vault.svc.cluster.local:8080/healthz
```

Expected:

- status `200`
- body `ok`

## Step 4: Create test data path for forwarding validation

Mount a test backend at `cmp/` and write sample data to avoid `404 no handler`.

```bash
kubectl exec -n vault vault-0 -- sh -lc '
export VAULT_ADDR=https://127.0.0.1:8200
export VAULT_CACERT=/vault/tls/ca.crt
export VAULT_TOKEN="<token>"
vault secrets enable -path=cmp kv-v2 || true
vault kv put cmp/demo status=ok source=proxy-repro
'
```

Success criteria:

- no error from `vault kv put cmp/demo ...`

Rollback note:

- if this mount was created only for this test, remove it later with `vault secrets disable cmp`

## Step 5: Verify proxy forwarding against the same Vault path

Read the same test secret through proxy HTTP and direct Vault HTTPS.

```bash
curl -H "X-Vault-Token: <token>" \
  http://vault-cmp-proxy.vault.svc.cluster.local:8080/v1/cmp/data/demo
```

```bash
curl -k -H "X-Vault-Token: <token>" \
  https://vault.vault.svc.cluster.local:8200/v1/cmp/data/demo
```

Expected for both:

- status `200`
- response includes `status":"ok"` and `source":"proxy-repro"`

## Results Summary

- Direct Vault HTTP health: `400`
- Direct Vault HTTPS health: `200`
- Proxy `/healthz`: `200`
- Proxy read `v1/cmp/data/demo`: `200`
- Direct Vault read `v1/cmp/data/demo`: `200`

## Conclusion

Vault can remain TLS-only while a front proxy accepts HTTP and re-encrypts to Vault over HTTPS. Vault does not require a plaintext listener for this pattern.

## Caveat

If Vault must validate original client TLS certificates for identity, avoid TLS termination before Vault. Use TLS passthrough (end-to-end TLS) so client certificate identity is preserved.

## Cleanup (Optional)

Remove proxy and test path if this environment was dedicated to the repro:

```bash
kubectl delete -f secrets-pki/cmpv2/vault-proxy.yaml --ignore-not-found
```
