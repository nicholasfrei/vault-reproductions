# Vault Pod Auto-Recovery on TLS Certificate Expiration

## Overview

This reproduction demonstrates how to configure Vault pods to automatically restart when TLS certificates expire using Kubernetes livenessProbe and cert-manager.

Modern corporations increasingly rely on automated certificate management systems, such as cert-manager, to handle their internal TLS certificate lifecycles. This approach enhances security by programmatically issuing and renewing certificates, often with very short Time-to-Live (TTL) values, instead of relying on long-lived, manually-managed certificates. While this practice improves security, it introduces a challenge for long-running services like Vault.

**Reference**: [Automating Vault Pod Recovery from Expired TLS Certificates](https://support.hashicorp.com/hc/en-us/articles/45878404965267-Automating-Vault-Pod-Recovery-from-Expired-TLS-Certificates-using-a-Kubernetes-livenessProbe)

## Problem Statement

When using cert-manager to issue TLS certificates for Vault pods, the certificate secret (`vault-server-tls`) is automatically rotated on disk. However, the running Vault pod does not automatically reload this new certificate, continuing to serve the old, expired one.

This leads to a production outage when the old certificate expires:

```bash
/ $ vault status
Error checking seal status: Get "https://127.0.0.1:8200/v1/sys/seal-status": tls: failed to verify certificate: x509: certificate has expired or is not yet valid: current time 2025-09-16T19:39:52Z is after 2025-09-16T18:51:34Z
```

## Solution

Use a Kubernetes livenessProbe to detect the expired certificate, fail the health check, and force Kubernetes to restart the pod, which then loads the new certificate on startup.

## Prerequisites

- Running Kubernetes cluster
- kubectl access to the cluster
- Vault Helm chart (for deploying Vault)
- Vault 1.18.x or newer

## Setup Instructions

### Step 1: Install cert-manager

```bash
# Install cert-manager (check for latest version)
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.15.1/cert-manager.yaml
```

Wait for the cert-manager pods to be running in the cert-manager namespace before proceeding.

**Note**: Always check for the latest stable cert-manager version at https://github.com/cert-manager/cert-manager/releases

### Step 2: Create Self-Signed Issuer

Create a file named `vault-ca-issuer.yaml`:

```yaml
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: vault-selfsigned-issuer
  namespace: vault
spec:
  selfSigned: {}
```

Apply the issuer:

```bash
kubectl apply -f vault-ca-issuer.yaml -n vault
```

### Step 3: Create Certificate Resource

Create a file named `vault-certificate.yaml`:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: vault-server-tls
  namespace: vault
spec:
  # The secret that will be created with tls.crt, tls.key, and ca.crt
  secretName: vault-server-tls

  # Short duration for testing automatic restart
  duration: 1h
  renewBefore: 5m

  # References the Issuer created in the previous step
  issuerRef:
    name: vault-selfsigned-issuer
    kind: Issuer

  # Common Name for the certificate
  commonName: vault.vault.svc.cluster.local

  # Subject Alternative Names (SANs)
  dnsNames:
    - vault
    - vault.vault
    - vault.vault.svc
    - vault.vault.svc.cluster.local
    - vault-0.vault-internal
    - vault-1.vault-internal
    - vault-2.vault-internal
    - localhost
  ipAddresses:
    - 127.0.0.1

  # Required usages for Vault
  usages:
    - server auth
    - client auth
    - key encipherment
    - data encipherment
```

Apply the certificate:

```bash
kubectl apply -f vault-certificate.yaml -n vault
```

After applying this certificate and ensuring your Vault pods are using the `vault-server-tls` secret, you can monitor the Vault pods. After ~1 hour, the certificate will expire, the livenessProbe will fail, and you should see Kubernetes restart the pods.

### Step 4: Configure Vault Liveness Probe

Add the following to your Vault Helm chart `values.yaml`:

```yaml
server:
  # ... other server configurations ...
  livenessProbe:
    enabled: true
    execCommand:
      - /bin/sh
      - -ec
      - vault status
```

Apply the changes:

```bash
helm upgrade vault hashicorp/vault -f values.yaml -n vault
```

## How the Probe Works

The livenessProbe runs a health check command inside the container:

- **execCommand**: Specifies the command to run
- **`/bin/sh -ec`**: Critical flags:
  - `-e`: Exit immediately if `vault status` fails
  - `-c`: Execute the command string
- **`vault status`**: Attempts to connect to Vault API at 127.0.0.1:8200

When the TLS certificate expires, the `vault status` command fails with an x509 error. The `-e` flag instructs the shell to exit immediately with a non-zero exit code, signaling that the probe has failed.

After the probe fails, kubelet will kill the pod. A new pod will start up and load the new TLS certificates (given the certificates are automatically updated by your certificate management system). This livenessProbe partners with cert-manager to automatically load the freshly updated certificates in Vault.

## Verification

### Expected Behavior

After the certificate's duration expires (1h in this example):

1. **Certificate Expires**: The original certificate served by Vault expires
2. **cert-manager Renews**: Updates the `vault-server-tls` secret with new certificate
3. **Liveness Probe Fails**: `vault status` fails because Vault still serves expired cert from memory
4. **Kubelet Detects Failure**: Check with:
   ```bash
   kubectl describe pod vault-0 -n vault
   ```
   
   You'll see events like:
   ```
   Events:
     Type     Reason     Age    From      Message
     ----     ------     ----   ----      -------
     Warning  Unhealthy  5m35s  kubelet   Liveness probe failed: Error checking seal status: ...
     Normal   Killing    50s    kubelet   Container vault failed liveness probe, will be restarted
   ```

5. **Pod Restarts**: Kubernetes terminates and recreates the pod
6. **Pod Recovers**: New pod loads the fresh certificate and becomes healthy

### Verify Certificate Expiration

You can check when the certificate will expire:

```bash
kubectl get secret vault-server-tls -n vault -o jsonpath='{.data.tls\.crt}' | base64 --decode | openssl x509 -noout -dates
```

## Testing

Monitor the pod after applying the certificate (expires in ~1 hour):

```bash
# Watch pod events
kubectl get events -n vault --watch

# Monitor pod restarts
kubectl get pods -n vault -w

# Check certificate status
kubectl get certificate -n vault vault-server-tls -o yaml
```

## Cleanup

```bash
# Delete certificate and issuer
kubectl delete certificate vault-server-tls -n vault
kubectl delete issuer vault-selfsigned-issuer -n vault

# Uninstall cert-manager (optional)
kubectl delete -f https://github.com/cert-manager/cert-manager/releases/download/v1.15.1/cert-manager.yaml
```

## Additional Resources

- [HashiCorp Support KB Article](https://support.hashicorp.com/hc/en-us/articles/45878404965267-Automating-Vault-Pod-Recovery-from-Expired-TLS-Certificates-using-a-Kubernetes-livenessProbe)
- [cert-manager Documentation](https://cert-manager.io/docs/)
- [cert-manager GitHub](https://github.com/cert-manager/cert-manager)
- [Vault Helm Chart Documentation](https://developer.hashicorp.com/vault/docs/platform/k8s/helm)