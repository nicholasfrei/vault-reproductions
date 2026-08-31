# CMPv2 Sentinel Nil Map Panic Repro

## Overview

When `enable_sentinel_parsing=true` is set in the CMPv2 config and a CR (Certificate Request) message is submitted with an empty `SEQUENCE OF CertReqMessages` body, `getCmpSentinelAuditingFields` attempts to write to a nil map and causes a server panic.

The panic surfaces in Vault logs as:

```text
http: panic serving <addr>: assignment to entry in nil map
```

The root is in `path_cmpv2_ent.go:245` — sentinel field extraction assumes the parsed CR slice is non-empty, but a validly-encoded ASN.1 empty sequence parses without error and returns a zero-length slice, leaving downstream fields nil.

## Objective

Reproduce the nil map panic triggered by a malformed CMP CR payload when `enable_sentinel_parsing` is enabled.

## Required Vault Version

- Vault Enterprise `1.21.8` (CMPv2 support requires Enterprise)
- Fix not yet confirmed upstream at time of writing; validate against your target build

## Prerequisites

- Vault Enterprise running in Kubernetes; `VAULT_ADDR` set to the active node (port-forward or direct service address)
- Root token available
- `go` installed locally (for payload generation in Step 6)
- `jq` installed locally
- `curl` installed locally

## Step 1: Set environment

```bash
export VAULT_ADDR="https://<vault-active-node>:8200"
export VAULT_TOKEN=<root-token>
export CMPV2_TMPDIR=/tmp/cmpv2-demo-test
mkdir -p $CMPV2_TMPDIR
```

## Step 2: Build mock hardware root CA and vendor CA (origin PKI)

```bash
vault secrets enable -path=pki_mock_origin_root pki

vault write -field=certificate pki_mock_origin_root/root/generate/internal \
  common_name=fake-root-ca.com ttl=87600h \
  > $CMPV2_TMPDIR/hardware_root_cert.pem

vault secrets enable -path=pki_mock_origin_ca pki

vault write -format=json pki_mock_origin_ca/issuers/import/cert \
  pem_bundle="@$CMPV2_TMPDIR/hardware_root_cert.pem" > /dev/null

vault write -field=csr pki_mock_origin_ca/intermediate/generate/internal \
  common_name="Vendor Intermediate Origin CA" \
  > $CMPV2_TMPDIR/pki_mock_origin_ca.csr

vault write -field=certificate pki_mock_origin_root/root/sign-intermediate \
  csr="@$CMPV2_TMPDIR/pki_mock_origin_ca.csr" ttl=43800h \
  > $CMPV2_TMPDIR/vendor_ca.cert.pem

vault write pki_mock_origin_ca/intermediate/set-signed \
  certificate="@$CMPV2_TMPDIR/vendor_ca.cert.pem" > /dev/null

vault write pki_mock_origin_ca/roles/myrole allow_any_name=true ttl=121h

vault write -format=json pki_mock_origin_ca/issue/myrole \
  common_name="device.example.com" > $CMPV2_TMPDIR/mock-origin-client-info.json

jq -r '.data.certificate' $CMPV2_TMPDIR/mock-origin-client-info.json \
  > $CMPV2_TMPDIR/initial-device-cert.pem
jq -r '.data.private_key' $CMPV2_TMPDIR/mock-origin-client-info.json \
  > $CMPV2_TMPDIR/initial-device-key.pem
```

## Step 3: Build the Vault PKI (root + intermediate) that serves CMPv2

```bash
vault secrets enable -path=pki pki
vault secrets tune -max-lease-ttl=87600h pki

vault write -field=certificate pki/root/generate/internal \
  common_name=root-example.com ttl=8760h \
  > $CMPV2_TMPDIR/root-ca-cert.pem

vault secrets enable -path=pki_int pki

vault write -field=csr pki_int/intermediate/generate/internal \
  common_name="example.com Intermediate Authority" \
  key_usage="CertSign,CRLSign,DigitalSignature" \
  > $CMPV2_TMPDIR/pki_intermediate.csr

vault write -field=certificate pki/root/sign-intermediate \
  csr="@$CMPV2_TMPDIR/pki_intermediate.csr" ttl=43800h use_csr_values=true \
  > $CMPV2_TMPDIR/intermediate.cert.pem

INT_ISSUER_ID=$(vault write -format=json pki_int/intermediate/set-signed \
  certificate=@$CMPV2_TMPDIR/intermediate.cert.pem \
  | jq -r '.data.imported_issuers[0]')

vault write pki_int/config/issuers default=$INT_ISSUER_ID
```

## Step 4: Configure cert auth and CMPv2 policy

```bash
vault auth enable cert

vault write auth/cert/certs/cmp-vendor-ca \
  display_name="CMPV2 Vendor CA" \
  token_policies="access-cmp" \
  certificate="@$CMPV2_TMPDIR/vendor_ca.cert.pem" \
  token_type="batch" \
  allowed_common_names="device.example.com"

CERT_ACCESSOR=$(vault read -field=accessor sys/auth/cert)

cat <<EOF | vault policy write access-cmp -
path "pki_int/cmp" {
  capabilities=["read","update","create"]
}
path "pki_int/roles/cmp-clients/cmp" {
  capabilities=["read","update","create"]
}
EOF

vault write pki_int/roles/cmp-clients \
  allow_any_name=true no_store=false max_ttl=720h require_cn=false

vault secrets tune \
  -allowed-response-headers="Content-Transfer-Encoding" \
  -allowed-response-headers="Content-Length" \
  -allowed-response-headers="WWW-Authenticate" \
  -delegated-auth-accessors="$CERT_ACCESSOR" \
  pki_int
```

## Step 5: Enable CMPv2 with `enable_sentinel_parsing=true`

This flag is the prerequisite for the panic. Without it the nil map write is not reached.

```bash
CERT_ACCESSOR=$(vault read -field=accessor sys/auth/cert)

cat <<EOF | vault write pki_int/config/cmp -
{
  "enabled": true,
  "enable_sentinel_parsing": true,
  "default_path_policy": "sign-verbatim",
  "authenticators": {
    "cert": { "accessor": "$CERT_ACCESSOR" }
  }
}
EOF
```

## Step 6: Generate the malformed CR payload

Run this locally. The payload encodes a CMP `PKIMessage` where the body is `[2] cr` containing an empty `SEQUENCE OF CertReqMessages`. ASN.1 decoding succeeds and returns a zero-length slice — no parse error is raised — but the nil sentinel fields cause the panic downstream.

```bash
mkdir -p /tmp/gen_cr && cat > /tmp/gen_cr/main.go << 'EOF'
package main

import (
    "crypto/x509/pkix"
    "encoding/asn1"
    "encoding/base64"
    "fmt"
)

func main() {
    atv := pkix.AttributeTypeAndValue{Type: asn1.ObjectIdentifier{2, 5, 4, 3}, Value: "UNKNOWN"}
    nameBytes, _ := asn1.Marshal(pkix.RDNSequence{pkix.RelativeDistinguishedNameSET{atv}})
    dirNameBytes, _ := asn1.Marshal(asn1.RawValue{Class: 2, Tag: 4, IsCompound: true, Bytes: nameBytes})
    pvnoBytes, _ := asn1.Marshal(2)
    headerBytes, _ := asn1.Marshal(asn1.RawValue{Tag: 16, IsCompound: true,
        Bytes: append(append(pvnoBytes, dirNameBytes...), dirNameBytes...)})
    // PKIBody [2] cr = empty SEQUENCE OF CertReqMessages
    // Parses successfully (empty slice, no error) but len==0 leaves fields nil -> PANIC
    emptySeqBytes, _ := asn1.Marshal(asn1.RawValue{Tag: 16, IsCompound: true, Bytes: []byte{}})
    bodyBytes, _ := asn1.Marshal(asn1.RawValue{Class: 2, Tag: 2, IsCompound: true, Bytes: emptySeqBytes})
    msg, _ := asn1.Marshal(asn1.RawValue{Tag: 16, IsCompound: true, Bytes: append(headerBytes, bodyBytes...)})
    fmt.Println(base64.StdEncoding.EncodeToString(msg))
}
EOF

go run /tmp/gen_cr/main.go | base64 -d > /tmp/cmp_cr_empty.der
echo "Payload ready: $(wc -c < /tmp/cmp_cr_empty.der) bytes"
```

## Step 7: Send the CR and trigger the panic

```bash
curl --header "X-Vault-Token: $VAULT_TOKEN" \
  --header "Content-Type: application/pkixcmp" \
  --request POST \
  --data-binary @/tmp/cmp_cr_empty.der \
  $VAULT_ADDR/v1/pki_int/cmp
```

## Validation

In a Kubernetes HA deployment, the panic is logged on the active node only — standbys forward the request and do not log it. Identify the active pod first:

```bash
kubectl get pods -n <vault-namespace> -l vault-active=true
kubectl logs -n <vault-namespace> <active-pod> | grep -A5 "nil map"
```

The panic appears as:

```text
2026-08-27T13:29:59.152-0700 [INFO]  http: panic serving 127.0.0.1:49549: assignment to entry in nil map

goroutine 1789 [running]:
net/http.(*conn).serve.func1()
	/home/runner/actions-runner/_work/_tool/go/1.25.11/x64/src/net/http/server.go:1943 +0xb4
panic({0x10c9c09e0?, 0x116b12120?})
	/home/runner/actions-runner/_work/_tool/go/1.25.11/x64/src/runtime/panic.go:783 +0x120
github.com/hashicorp/vault/builtin/logical/pki/cmpv2.(*Backend).getCmpSentinelAuditingFields(...)
	.../builtin/logical/pki/cmpv2/path_cmpv2_ent.go:245 +0x44c
github.com/hashicorp/vault/builtin/logical/pki/cmpv2.(*Backend).saveCmpSentinelFields(...)
	.../builtin/logical/pki/cmpv2/path_cmpv2_ent.go:201 +0x1c4
github.com/hashicorp/vault/builtin/logical/pki/cmpv2.(*Backend).saveCmpBinaryData(...)
	.../builtin/logical/pki/cmpv2/path_cmpv2_ent.go:171 +0x3b8
github.com/hashicorp/vault/builtin/logical/pki/cmpv2.(*Backend).handlerCmpEntry(...)
	.../builtin/logical/pki/cmpv2/path_cmpv2_ent.go:91 +0x100
```

The `curl` request receives no response body (connection reset or empty reply) because the goroutine panicked before writing a response. Vault itself stays running — the panic is caught by `net/http`'s per-connection recover handler.

Key stack frames confirming the code path:

| Frame | File | Line |
|---|---|---|
| `getCmpSentinelAuditingFields` | `path_cmpv2_ent.go` | 245 |
| `saveCmpSentinelFields` | `path_cmpv2_ent.go` | 201 |
| `saveCmpBinaryData` | `path_cmpv2_ent.go` | 171 |
| `handlerCmpEntry` | `path_cmpv2_ent.go` | 91 |

## References

- [Vault PKI CMPv2 documentation](https://developer.hashicorp.com/vault/docs/secrets/pki/cmpv2)
- [Vault PKI secrets engine](https://developer.hashicorp.com/vault/docs/secrets/pki)
- [Vault cert auth method](https://developer.hashicorp.com/vault/docs/auth/cert)
