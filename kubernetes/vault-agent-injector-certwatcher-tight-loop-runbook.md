# Vault Agent Injector Certificate Watcher Log Loop Runbook

## Summary

With an invalid webhook TLS certificate, the Vault Agent Injector logs `Could not load TLS keypair` while retrying. VAULT-51159 describes a tight warning loop after the injector's retry backoff is exhausted, about 15 minutes after continuous failures. The linked PR estimates roughly 5–6 warnings per second. In my local repro, I captured ~4M matching lines in a 2 minute window (`--since=2m`). This runbook tests the behavior using a temporary injector release and namespace.

## Objective

Reproduce and measure the Vault Agent Injector certificate-watcher warning rate after its retry backoff is exhausted.

## Prerequisites and safety

- A local or disposable Kubernetes cluster with an existing Vault cluster and Agent Injector.
- `kubectl`, Helm 3, OpenSSL 1.1.1 or newer, `base64`, `grep`, and a POSIX-compatible shell.
- Permission to create a namespace, deployment, RBAC resources, and a cluster-scoped `MutatingWebhookConfiguration`.
- A temporary namespace and Helm release name that are not already in use.
- Run only against a local or disposable cluster. The test release creates a cluster-scoped admission webhook, restricted to the test namespace by a namespace selector.
- This procedure does not change the existing Vault or Agent Injector Helm release and does not require a Vault token or license.

The example uses Helm chart `0.34.1` and injector image `docker.io/hashicorp/vault-k8s:1.7.6`, matching the environment used when preparing this runbook. This is a reproduction target, not a confirmed affected-version range. Record different versions if you substitute them.

## 1. Confirm the target and choose test names

Check the active Kubernetes context and current Helm releases before creating anything:

```bash
kubectl config current-context
helm list -A
```

Set unique names for this test. Change them if either is already in use:

```bash
TEST_NS=vault-51159
TEST_REL=vault-51159
TLS_SECRET=vault-51159-webhook-tls
CHART_VERSION=0.34.1
INJECTOR_TAG=1.7.6
```

Confirm the namespace does not already exist:

```bash
kubectl get namespace "$TEST_NS" --ignore-not-found
```

If it exists, choose a different `TEST_NS` and `TEST_REL` before continuing. Do not reuse or delete a namespace you did not create for this test.

## 2. Create a valid test certificate

The injector must start with a valid certificate so it remains able to serve TLS while the mounted certificate file is later made invalid.

```bash
WORK_DIR=$(mktemp -d)

openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$WORK_DIR/webhook.key" \
  -out "$WORK_DIR/webhook.crt" \
  -days 1 \
  -subj "/CN=${TEST_REL}-agent-injector-svc.${TEST_NS}.svc" \
  -addext "subjectAltName=DNS:${TEST_REL}-agent-injector-svc,DNS:${TEST_REL}-agent-injector-svc.${TEST_NS},DNS:${TEST_REL}-agent-injector-svc.${TEST_NS}.svc"

kubectl create namespace "$TEST_NS"
kubectl label namespace "$TEST_NS" vault-51159-test=true

kubectl -n "$TEST_NS" create secret tls "$TLS_SECRET" \
  --cert="$WORK_DIR/webhook.crt" \
  --key="$WORK_DIR/webhook.key"

CA_BUNDLE=$(base64 < "$WORK_DIR/webhook.crt" | tr -d '\n')
```

## 3. Install an injector-only test release

Add the HashiCorp chart repository if it is not already configured, then install the specified chart version. The external Vault address is a placeholder: this test measures certificate handling and does not send injector requests to Vault.

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com --force-update
helm repo update

helm install "$TEST_REL" hashicorp/vault -n "$TEST_NS" \
  --version "$CHART_VERSION" \
  --set server.enabled=false \
  --set injector.enabled=true \
  --set csi.enabled=false \
  --set ui.enabled=false \
  --set global.externalVaultAddr=https://vault.invalid:8200 \
  --set injector.image.repository=docker.io/hashicorp/vault-k8s \
  --set-string injector.image.tag="$INJECTOR_TAG" \
  --set injector.certs.secretName="$TLS_SECRET" \
  --set-string injector.certs.caBundle="$CA_BUNDLE" \
  --set injector.webhook.namespaceSelector.matchLabels.vault-51159-test=true \
  --wait \
  --timeout 5m
```

Wait for the injector pod to be ready and confirm the deployed image:

```bash
kubectl -n "$TEST_NS" get pods -w
kubectl -n "$TEST_NS" get deploy "${TEST_REL}-agent-injector" \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

Expected image:

```text
docker.io/hashicorp/vault-k8s:1.7.6
```

Stop if the deployment is not ready or the deployed image does not match the intended test version.

## 4. Replace the certificate with invalid PEM

Record the start time, then update only `tls.crt`. Do not restart the injector. The pod should already have loaded and be serving the original valid certificate.

```bash
date -u

BAD_CERT=$(printf 'not a PEM certificate\n' | base64 | tr -d '\n')

kubectl -n "$TEST_NS" patch secret "$TLS_SECRET" \
  --type merge \
  -p "{\"data\":{\"tls.crt\":\"$BAD_CERT\"}}"
```

Find the injector pod and watch for the first matching warning:

```bash
POD=$(kubectl -n "$TEST_NS" get pods \
  -l "app.kubernetes.io/instance=$TEST_REL,component=webhook" \
  -o jsonpath='{.items[0].metadata.name}')

kubectl -n "$TEST_NS" logs "$POD" --since=1m --timestamps \
  | grep -F 'Could not load TLS keypair'
```

If no matching line appears yet, repeat the command after a few seconds while the Secret volume update propagates.

The exact error should include:

```text
Could not load TLS keypair: tls: failed to find any PEM data in certificate input. Trying again...
```

Note the time the first `certwatcher` warning appears. The backoff interval is measured from retry failures, so use this as the observation start. Leave the invalid certificate in place for at least 15 minutes after the first warning.

## 5. Count warnings after the backoff window

After at least 15 minutes of continuous certificate failure, check that the injector has not restarted:

```bash
kubectl -n "$TEST_NS" get pod "$POD" \
  -o jsonpath='{.status.containerStatuses[0].restartCount}{"\n"}'
```

Count matching warnings from the last two minutes:

```bash
kubectl -n "$TEST_NS" logs "$POD" --since=2m \
  | grep -F 'Could not load TLS keypair' \
  | wc -l
```

Potential output: 
```text
4024529
```

Interpret the result:

- The linked PR estimates approximately 5–6 warnings per second after backoff exhaustion, or roughly 600–720 matching lines in a full two-minute window.
- In my repro, I observed a count of `4,024,529`. This count is far above that estimate in the PR.

## 6. Restore the certificate and clean up

Restore the valid certificate first. Wait for the injector to observe it and confirm that new certificate-load warnings stop:

```bash
kubectl -n "$TEST_NS" create secret tls "$TLS_SECRET" \
  --cert="$WORK_DIR/webhook.crt" \
  --key="$WORK_DIR/webhook.key" \
  --dry-run=client -o yaml \
  | kubectl apply -f -
```

After restoration, remove only the test Helm release and test namespace:

```bash
helm uninstall "$TEST_REL" -n "$TEST_NS"
kubectl delete namespace "$TEST_NS"
rm -f "$WORK_DIR/webhook.key" "$WORK_DIR/webhook.crt"
rmdir "$WORK_DIR"
```

Confirm cleanup:

```bash
helm list -A
kubectl get namespace "$TEST_NS"
```

The test namespace should be absent. Do not uninstall or modify the existing Vault release.

## References

- [VAULT-51159](https://hashicorp.atlassian.net/browse/VAULT-51159): Reports the invalid-certificate warning flood.
- [vault-k8s PR #904](https://github.com/hashicorp/vault-k8s/pull/904): Describes the exhausted-backoff tight loop and proposed retry-interval fallback. Check the PR and release status separately; this runbook does not establish a fixed version.
- [Vault Helm chart documentation](https://developer.hashicorp.com/vault/docs/deploy/kubernetes/helm): Official Helm deployment reference.
