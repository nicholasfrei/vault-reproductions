# CMPv2 PKI Integration Repro (Vault)

This is a markdown-only, minimal runbook for reproducing Vault PKI CMPv2 behavior and proxy viability.

## Goal

Validate two things:

1. Vault CMPv2 is configured and issues certificates.
2. CMPv2 IR works both:
   - directly to Vault over HTTPS
   - via proxy HTTP ingress that forwards upstream to Vault HTTPS

## Prerequisites

- Kubernetes Vault deployment already running
- Proxy scenario already deployed from the Kubernetes proxy behavior folder
- OpenSSL 3.x with `openssl cmp` available
- Admin token with permissions for auth + PKI config

## Step 1: Configure CMPv2 on Vault PKI

Create/verify the required components:

- PKI mount at `pki/`
- dedicated cert auth mount at `cmp-cert/`
- CMP role at `pki/roles/cmp-role`
- CMP config at `pki/config/cmp`

Verification commands:

```bash
vault read pki/config/cmp
vault auth list | grep -i cmp
vault read pki/roles/cmp-role
```

Expected output example:

```text
Key                        Value
---                        -----
enabled                    true
default_path_policy        role:cmp-role
authenticators             map[cert:map[accessor:auth_cert_...]]

cmp-cert/    cert     auth_cert_...     n/a    n/a

# Useful role fields from: vault read pki/roles/cmp-role
issuer_ref                 default
key_type                   rsa
key_bits                   2048
key_usage                  [DigitalSignature KeyAgreement KeyEncipherment]
max_ttl                    72h
allow_any_name             true
```

## Step 2: Validate endpoint routing before CMP transaction

Quick reachability check to CMP role path via proxy:

```bash
curl -H "X-Vault-Token: <token>" \
  http://vault-cmp-proxy.vault.svc.cluster.local:8080/v1/pki/roles/cmp-role/cmp
```

Expected:

```text
405
{"errors":["unsupported operation"]}
```

`405` on `GET` is expected because CMP operations are POST-based.

## Step 3: Run real CMP IR request (direct Vault HTTPS)

Example command used in repro:

```bash
openssl cmp -cmd ir -batch \
  -server https://127.0.0.1:18200/v1/pki/roles/cmp-role/cmp \
  -tls_used \
  -tls_trusted test-certs/vault-server-ca.pem \
  -tls_host vault.vault.svc.cluster.local \
  -tls_cert test-certs/cmp-client-cert.pem \
  -tls_key test-certs/cmp-client-key.pem \
  -trusted test-certs/cmp-root-ca.pem \
  -own_trusted test-certs/cmp-root-ca.pem \
  -cert test-certs/cmp-client-cert.pem \
  -key test-certs/cmp-client-key.pem \
  -newkey test-certs/ir-key.pem \
  -subject "/CN=cmp-issued.local" \
  -certout test-certs/ir-direct-cert.pem \
  -rspout test-certs/ir-direct-rsp.der \
  -disable_confirm \
  -verbosity 8
```

Expected success lines:

```text
CMP info: sending IR
CMP info: received IP
received 1 newly enrolled certificate(s)
```

## Step 4: Run real CMP IR request (proxy HTTP -> Vault HTTPS)

Example command used in repro:

```bash
openssl cmp -cmd ir -batch \
  -server http://127.0.0.1:18080/v1/pki/roles/cmp-role/cmp \
  -trusted test-certs/cmp-root-ca.pem \
  -own_trusted test-certs/cmp-root-ca.pem \
  -cert test-certs/cmp-client-cert.pem \
  -key test-certs/cmp-client-key.pem \
  -newkey test-certs/ir-key.pem \
  -subject "/CN=cmp-issued-via-proxy.local" \
  -certout test-certs/ir-proxy-cert.pem \
  -rspout test-certs/ir-proxy-rsp.der \
  -disable_confirm \
  -verbosity 8
```

Expected success lines:

```text
CMP info: sending IR
CMP info: received IP
received 1 newly enrolled certificate(s)
```

## Step 5: Validate issued certs

```bash
openssl x509 -in test-certs/ir-direct-cert.pem -noout -subject -issuer -dates
openssl x509 -in test-certs/ir-proxy-cert.pem -noout -subject -issuer -dates
```

Observed repro output:

```text
subject=CN=cmp-issued.local
issuer=CN=CMP Root CA

subject=CN=cmp-issued-via-proxy.local
issuer=CN=CMP Root CA
```

## Repro conclusion

- Vault CMPv2 IR succeeded directly over HTTPS.
- Vault CMPv2 IR also succeeded through proxy HTTP ingress with HTTPS upstream to Vault.
- This demonstrates technical viability of proxy HTTP -> Vault HTTPS for CMP IR in this lab.
- Vault does not need its own unencrypted listener if a front proxy accepts HTTP and forwards to Vault over HTTPS
- In this reproduction, CMPv2 IR succeeded in both direct and proxied paths.