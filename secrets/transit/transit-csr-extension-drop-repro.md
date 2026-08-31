# Transit CSR Re-Signing Drops Extension Critical Flag

## Overview

When the Transit secrets engine re-signs a template CSR via `POST /transit/keys/:name/csr`, extension attributes from the template — including the `Critical` flag on custom extensions — are silently dropped in the output CSR. In cases where the template CSR carries both Subject Alternative Names (SANs) and additional extensions, the re-signing also produces a structurally invalid (malformed ASN.1) CSR that downstream tools reject entirely.

Related issues: VAULT-35786 (original, not fixed), VAULT-36036 (follow-up fix).

## Objective

Reproduce the bug where `vault write transit/keys/:name/csr` silently strips `Critical: true` from custom X.509 extensions in the re-signed output CSR.

## Prerequisites

- Vault server running and accessible (`VAULT_ADDR`, `VAULT_TOKEN` set)
- `openssl` (any modern version)
- `python3` (standard library only)

## Steps

### 1. Create a template CSR with a custom critical extension

```bash
cat > test.cnf << EOF
[ req ]
distinguished_name = req_distinguished_name
req_extensions = req_ext

[ req_distinguished_name ]
CN = test.example.com

[ req_ext ]
keyUsage = critical, nonRepudiation
EOF
```

Generate a private key and CSR:

```bash
openssl genrsa -out test.key 2048
openssl req -new -key test.key -out test.csr -config test.cnf -subj "/CN=test.example.com"
```

Confirm the critical flag is present in the template CSR:

```bash
openssl req -in test.csr -noout -text
```

Expected output (excerpt):

```text
        Attributes:
            Requested Extensions:
                X509v3 Key Usage: critical
                    Non Repudiation
```

### 2. Enable the Transit secrets engine and create an RSA-2048 key

```bash
vault secrets enable transit
vault write transit/keys/rsa-key type=rsa-2048
```

### 3. Re-sign the CSR with the Transit-managed key

```bash
vault write -format=json transit/keys/rsa-key/csr csr=@test.csr \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['data']['csr'])" \
  > vault-resigned.csr
```

### 4. Inspect the output CSR

```bash
openssl req -in vault-resigned.csr -noout -text
```

## Observed Behavior (Buggy)

The `Critical` flag is missing from the re-signed output:

```text
        Attributes:
            Requested Extensions:
                X509v3 Key Usage:
                    Non Repudiation
```

The `critical` keyword is gone. On affected versions, if the template CSR also includes SANs alongside the custom extension, `openssl req` may return a parse error instead:

```text
asn1 error in read object
```

## Expected Behavior

The `Critical` flag should be preserved in the output CSR:

```text
        Attributes:
            Requested Extensions:
                X509v3 Key Usage: critical
                    Non Repudiation
```

## Root Cause

Two independent bugs in `parseCsr()` in `builtin/logical/transit/path_certificates.go` combined to cause the failure.

**Bug 1 — Stale `Attributes` not cleared (Critical flags dropped)**

`x509.ParseCertificateRequest` populates `CertificateRequest.Attributes` with the raw `requestedExtensions` attribute set from the original CSR's ASN.1 structure. When `x509.CreateCertificateRequest` is subsequently called with that same struct as a template, it detects the non-empty `Attributes` field and takes an internal merge path that re-serialises extensions as `AttributeTypeAndValue` entries. The Go standard library explicitly states in that code path:

> There is no place for the critical flag in an AttributeTypeAndValue.

The `Critical` flag is therefore unconditionally discarded by the Go stdlib before Vault can act on it.

A prior patch attempt set `ExtraExtensions` correctly but left `Attributes` populated. Because `CreateCertificateRequest` checks `Attributes` first, it still took the broken merge path, ignoring `ExtraExtensions` entirely.

**Bug 2 — SAN extension duplicated, producing malformed ASN.1**

`x509.CreateCertificateRequest` automatically generates the Subject Alternative Name extension (OID `2.5.29.17`) from the struct fields `DNSNames`, `EmailAddresses`, `IPAddresses`, and `URIs` — all of which `ParseCertificateRequest` also populates. Naively copying all entries from `Extensions` into `ExtraExtensions` (including the SAN entry) caused the SAN extension to be emitted twice, producing a malformed CSR.

**Fix**

```go
csr.Attributes = nil                                        // Bug 1: force clean encoding path
for _, ext := range csr.Extensions {
    if !ext.Id.Equal(oidExtensionSubjectAltName) {          // Bug 2: skip auto-generated SAN
        csr.ExtraExtensions = append(csr.ExtraExtensions, ext)
    }
}
```

## Affected Versions

Reproduced through Vault `2.0.4`. The fix targets `path_certificates.go` in the Transit secrets engine.

## Validation

After the fix is applied, re-run the reproduction steps and confirm the output CSR contains `critical` in the `X509v3 Key Usage` extension:

```bash
openssl req -in vault-resigned.csr -noout -text | grep -A2 "Key Usage"
```

Expected output:

```text
                X509v3 Key Usage: critical
                    Non Repudiation
```

Also confirm the CSR is structurally valid by parsing it without error:

```bash
openssl req -in vault-resigned.csr -noout -verify
```

Expected output:

```text
Certificate request self-signature verify OK
```

## Cleanup

```bash
vault secrets disable transit
rm -f test.key test.csr test.cnf vault-resigned.csr
```
