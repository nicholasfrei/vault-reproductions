# Vault CSI Provider TLS CA Bundle Runbook

This runbook is based on a support case where a customer was struggling to configure the Vault CSI provider. It shows what is required to resolve the error below when the provider cannot validate the TLS certificate presented by Vault:

```text
MountVolume.SetUp failed for volume "db-config-secret" ... failed to login: Post "https://test.com/v1/auth/test/login": tls: failed to verify certificate: x509: certificate signed by unknown authority
```

## Goal

- Extract the Vault CA bundle from the existing `vault-tls` Kubernetes secret
- Mount that CA bundle into the Vault CSI provider daemonset running in `vault-csi-lab`
- Configure both the CSI provider and the Vault Agent sidecar to trust that CA
- Show the matching `SecretProviderClass` settings when `vaultAddress` is set explicitly

## Lab Assumptions

- Your Vault cluster is already running in the `vault-1` namespace with TLS enabled
- The Vault TLS material is stored in the `vault-tls` secret in `vault-1`
- The CA bundle inside that secret is stored under the `vault.ca` key
- The CSI repro is installed into the separate `vault-csi-lab` namespace

If you are following along in your own environment, adjust the namespaces and secret names as needed.

Current namespaces in this lab:

```bash
kubectl get ns
```

Expected relevant namespaces:

- `vault-1`
- `vault-csi-lab`

## Why This Happens

The CSI provider is making an HTTPS request to Vault and does not trust the certificate authority that signed the Vault server certificate.

Two details matter here:

1. `server.extraVolumes` is not the correct setting for this problem.
   It only mounts content into Vault server pods.

2. The Vault CSI provider needs its own mount and TLS settings.
   For the CSI provider daemonset, use `csi.volumes` and `csi.volumeMounts`.

If the `SecretProviderClass` sets `vaultAddress`, that address can override the chart defaults for where the provider connects. In that case, the provider must also be told where the CA bundle exists on disk using `vaultCACertPath`.

## Step 1: Verify the Existing Vault TLS Secret

Confirm that the `vault-tls` secret exists in `vault-1`:

```bash
kubectl get secret -n vault-1 vault-tls
```

List the available keys:

```bash
kubectl get secret -n vault-1 vault-tls -o json | jq -r '.data | keys[]'
```

You should see the key used by your CA bundle. In this lab, the runbook assumes the CA bundle is stored as `vault.ca`.

## Step 2: Extract the CA Bundle from the Existing Vault Cluster

Export the CA bundle from the `vault-tls` secret in `vault-1`:

```bash
kubectl get secret -n vault-1 vault-tls \
  -o jsonpath='{.data.vault\.ca}' | base64 -d > /tmp/vault.ca
```

Validate that the extracted file is readable as PEM:

```bash
openssl x509 -in /tmp/vault.ca -text -noout >/dev/null
```

If your secret uses a different key name, replace `vault.ca` with the correct one.

## Step 3: Create a CA Secret for the CSI Provider Namespace

Create a dedicated secret in `vault-csi-lab` from the exported CA file:

```bash
kubectl create namespace vault-csi-lab --dry-run=client -o yaml | kubectl apply --server-side -f -

kubectl -n vault-csi-lab create secret generic vault-ca-bundle \
  --from-file=vault.ca=/tmp/vault.ca \
  --dry-run=client -o yaml | kubectl apply --server-side -f -
```

Verify it exists:

```bash
kubectl get secret -n vault-csi-lab vault-ca-bundle
```

## Step 4: Install the Secrets Store CSI Driver

```bash
helm repo add secrets-store-csi-driver https://kubernetes-sigs.github.io/secrets-store-csi-driver/charts
helm repo update

helm upgrade --install secrets-store-csi-driver secrets-store-csi-driver/secrets-store-csi-driver \
  --namespace vault-csi-lab \
  --set 'tokenRequests[0].audience=vault' \
  --set enableSecretRotation=true \
  --set rotationPollInterval=30s
```

## Step 5: Use a CSI Values File for the Existing TLS-Enabled Vault Cluster

In this lab, the CSI provider connects to the existing Vault service in `vault-1`.

Use the values file already included in this repository:

- `vault-csi-provider/values-csi-ca.yaml`

Relevant contents:

```yaml
global:
  enabled: false
  externalVaultAddr: "https://vault-1-active.vault-1.svc.cluster.local:8200"

server:
  enabled: false

injector:
  enabled: false

csi:
  enabled: true

  volumes:
    - name: vault-ca
      secret:
        secretName: vault-ca-bundle

  volumeMounts:
    - name: vault-ca
      mountPath: /vault/vault-tls
      readOnly: true

  extraArgs:
    - --vault-tls-ca-cert=/vault/vault-tls/vault.ca

  agent:
    enabled: true
    extraArgs:
      - -ca-cert=/vault/vault-tls/vault.ca
```

Why these values are correct for this lab:

- `global.externalVaultAddr` points at the active Vault service in `vault-1`
- `csi.volumes` and `csi.volumeMounts` mount the CA bundle into the CSI daemonset
- `--vault-tls-ca-cert=/vault/vault-tls/vault.ca` tells the CSI provider which CA file to trust
- `-ca-cert=/vault/vault-tls/vault.ca` tells the Vault Agent sidecar to trust the same CA

## Step 6: Install the Vault CSI Provider

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update

helm upgrade --install vault hashicorp/vault \
  --namespace vault-csi-lab \
  --version 0.32.0 \
  -f vault-csi-provider/values-csi-ca.yaml
```

## Step 7: Verify the CA Bundle Is Mounted into the CSI Daemonset

Capture the provider pod name once so the remaining commands are copy-pasteable:

```bash
CSI_POD=$(kubectl -n vault-csi-lab get pods \
  -l app.kubernetes.io/name=vault-csi-provider \
  -o jsonpath='{.items[0].metadata.name}')

echo "$CSI_POD"
```

Inspect the provider container:

```bash
kubectl -n vault-csi-lab exec -it "$CSI_POD" -c vault-csi-provider -- sh -c 'ls -l /vault/vault-tls && echo && cat /vault/vault-tls/vault.ca'
```

Inspect the agent sidecar:

```bash
kubectl -n vault-csi-lab exec -it "$CSI_POD" -c vault-agent -- ls -l /vault/vault-tls
```

Inspect the rendered daemonset:

```bash
kubectl -n vault-csi-lab get daemonset vault-csi-provider -o yaml
```

Look for:

- a `volumes` entry named `vault-ca`
- a `volumeMounts` entry with `mountPath: /vault/vault-tls`
- the provider arg `--vault-tls-ca-cert=/vault/vault-tls/vault.ca`
- the agent arg `-ca-cert=/vault/vault-tls/vault.ca`

Example successful validation from this repro:

```text
$ kubectl -n vault-csi-lab get pods -l app.kubernetes.io/name=vault-csi-provider
NAME                       READY   STATUS    RESTARTS   AGE
vault-csi-provider-zrkm8   2/2     Running   0          8s

$ kubectl -n vault-csi-lab exec -it "$CSI_POD" -c vault-csi-provider -- sh -c 'ls -l /vault/vault-tls'
total 0
lrwxrwxrwx    1 root     root            13 Apr 16 19:58 ca.crt -> ..data/ca.crt
lrwxrwxrwx    1 root     root            15 Apr 16 19:58 vault.ca -> ..data/vault.ca

$ kubectl -n vault-csi-lab exec -it "$CSI_POD" -c vault-agent -- ls -l /vault/vault-tls
total 0
lrwxrwxrwx    1 root     root            13 Apr 16 19:58 ca.crt -> ..data/ca.crt
lrwxrwxrwx    1 root     root            15 Apr 16 19:58 vault.ca -> ..data/vault.ca
```

## Step 8: Match the SecretProviderClass to the Same CA Path

If the `SecretProviderClass` sets `vaultAddress`, also set `vaultCACertPath` so the provider uses the mounted CA bundle.

Example:

```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: vault-db-example
spec:
  provider: vault
  parameters:
    vaultAddress: "https://vault-1-active.vault-1.svc.cluster.local:8200"
    vaultCACertPath: "/vault/vault-tls/vault.ca"
    roleName: "my-role"
    vaultAuthMountPath: "kubernetes"
    objects: |
      - objectName: "db-password"
        secretPath: "secret/data/app"
        secretKey: "password"
```

If you instead point the `SecretProviderClass` at an external DNS name such as `https://test.com`, the same rule applies: `vaultCACertPath` must reference the mounted CA bundle path inside the CSI pod.

## Expected Result

After the CA bundle is mounted and referenced correctly:

- the CSI provider pod contains `/vault/vault-tls/vault.ca`
- the provider no longer fails with `x509: certificate signed by unknown authority`
- the provider can authenticate to Vault successfully, assuming auth role and policy are correct

## Key Takeaway

For this lab, the CA source is not a generic `/path/to/ca.crt`. It comes from the existing TLS-enabled Vault cluster in `vault-1`, specifically from the `vault-tls` secret, and the CSI provider should trust `/vault/vault-tls/vault.ca` after that secret is mounted into the CSI daemonset.

## References

- [Vault Helm chart `extraVolumes` configuration reference](https://developer.hashicorp.com/vault/docs/v1.20.x/deploy/kubernetes/helm/configuration#extravolumes): Describes the server-side volume settings and helps explain why `server.extraVolumes` does not solve CSI provider trust issues.
- [Vault Helm chart CSI configuration reference](https://developer.hashicorp.com/vault/docs/v1.20.x/deploy/kubernetes/helm/configuration#csi): Documents the `csi.volumes`, `csi.volumeMounts`, and related CSI chart settings used in this runbook.