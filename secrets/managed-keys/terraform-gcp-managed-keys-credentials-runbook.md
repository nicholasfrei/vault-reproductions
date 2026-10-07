# Terraform GCP managed-key credentials failure (local Kubernetes)

## Objective

Reproduce [VAULT-50985](https://hashicorp.atlassian.net/browse/VAULT-50985): `vault_managed_keys` requires GCP `credentials`; `jsonencode({})` passes provider validation but Vault interprets the resulting `"{}"` as a credential-file path. Configuration can be created, but test-sign fails with `open {}: no such file or directory`.

This procedure uses a local Kubernetes cluster and a credential file mounted into Vault, not GKE Workload Identity. It exercises the same per-key credentials failure. The issue reports Vault Enterprise `1.20.2+ent`; the local provider used for this lab was `5.12.0`.

## Prerequisites

- Vault Enterprise cluster, accessed in the root namespace, with no existing managed keys of any type.
- Local Kubernetes Vault StatefulSet with a container named `vault`; a pod rollout is acceptable. Confirm `GOOGLE_CREDENTIALS` is unset.
- GCP sandbox project and permissions to enable Cloud KMS, create a key ring and asymmetric signing key, create a service account/key, and change IAM on the test key.
- `gcloud`, `kubectl`, `vault`, and `terraform` installed.

## Steps

### 1. Create the GCP key and Vault identity

Set the target values for your disposable environment; choose unused names:

```bash
export PROJECT="$(gcloud config get-value project)"
export REGION=us-central1 RING=vault-50985-lab KEY=vault-50985-lab
export GSA=vault-50985-lab EMAIL="vault-50985-lab@$PROJECT.iam.gserviceaccount.com"
export VAULT_NS="<vault-namespace>" VAULT_STS="<vault-statefulset>" VAULT_SVC="<vault-service>"

gcloud services enable cloudkms.googleapis.com --project="$PROJECT"
gcloud kms keyrings create "$RING" --location="$REGION" --project="$PROJECT"
gcloud kms keys create "$KEY" --keyring="$RING" --location="$REGION" \
  --project="$PROJECT" --purpose=asymmetric-signing \
  --default-algorithm=rsa-sign-pkcs1-4096-sha256
gcloud iam service-accounts create "$GSA" --project="$PROJECT"
gcloud kms keys add-iam-policy-binding "$KEY" --keyring="$RING" \
  --location="$REGION" --project="$PROJECT" \
  --member="serviceAccount:$EMAIL" --role=roles/cloudkms.signerVerifier
gcloud kms keys add-iam-policy-binding "$KEY" --keyring="$RING" \
  --location="$REGION" --project="$PROJECT" \
  --member="serviceAccount:$EMAIL" --role=roles/cloudkms.viewer
```

Both key-scoped roles matter: Vault needs `cloudkms.cryptoKeys.get` (Viewer) to check key existence, as well as signing permission (Signer/Verifier). Do not grant project-wide KMS Admin for this test.

### 2. Make the credentials available to Vault

Create a Kubernetes Secret without printing or retaining the service-account JSON file. Do not commit the Secret or Terraform state. These are test credentials; rotate/delete them after the lab.

```bash
(
  set -euo pipefail
  umask 077
  f="$(mktemp)"
  trap 'rm -f "$f"' EXIT
  gcloud iam service-accounts keys create "$f" --iam-account="$EMAIL" --project="$PROJECT"
  kubectl -n "$VAULT_NS" create secret generic vault-50985-creds \
    --from-file=credentials.json="$f"
)
```

Check the selected StatefulSet/container names before applying the patch. This patch changes the Vault pod template and rolls its pods; use only on the disposable cluster.

```bash
kubectl -n "$VAULT_NS" get sts "$VAULT_STS" \
  -o jsonpath='{.spec.template.spec.containers[*].name}{"\n"}'
kubectl -n "$VAULT_NS" patch sts "$VAULT_STS" --type=strategic -p \
  '{"spec":{"template":{"spec":{"volumes":[{"name":"gcp-kms-creds","secret":{"secretName":"vault-50985-creds"}}],"containers":[{"name":"vault","env":[{"name":"GOOGLE_APPLICATION_CREDENTIALS","value":"/vault/userconfig/gcp/credentials.json"}],"volumeMounts":[{"name":"gcp-kms-creds","mountPath":"/vault/userconfig/gcp","readOnly":true}]}]}}}}'
kubectl -n "$VAULT_NS" rollout status "sts/$VAULT_STS"
```

In another terminal, leave a port-forward running (restart it after any pod rollout):

```bash
kubectl -n "$VAULT_NS" port-forward "svc/$VAULT_SVC" 8200:8200
```

Continue in the first terminal with your authorized `VAULT_TOKEN` already set:

```bash
export VAULT_ADDR=http://127.0.0.1:8200
vault status
```

### 3. Prove ambient credentials work, then remove the control

Vault receives no per-key `credentials` value here. The sign operation must succeed before testing Terraform. Confirm no other managed keys exist (including `awskms`, `azurekeyvault`, and `pkcs11`), or stop and use a clean Vault.

```bash
vault write sys/managed-keys/gcpckms/control \
  project="$PROJECT" region="$REGION" key_ring="$RING" crypto_key="$KEY" \
  crypto_key_version=1 algorithm=RSA_SIGN_PKCS1_4096_SHA256
vault write -force sys/managed-keys/gcpckms/control/test/sign
vault delete sys/managed-keys/gcpckms/control
```

Expected (illustrative): `Success! Data written to: sys/managed-keys/gcpckms/control/test/sign`. Deleting the Vault `control` configuration does not delete the Cloud KMS key. The Terraform create will refuse to run if this control key remains.

### 4. Apply the Terraform configuration from a new, empty directory

Use a directory outside this repository to keep state and credentials out of version control. `mkdir` intentionally fails if that lab directory already exists; choose a new name rather than reusing an existing state.

Example `main.tf`:
[main.tf](main.tf)

```bash
terraform init
terraform apply
```

Expected: one `vault_managed_keys.repro` resource is created. `jsonencode({})` is the non-empty string `"{}"`, not an omitted or empty `credentials` field. A later `terraform apply` reporting `No changes` does not repeat the write.

### 5. Test signing

```bash
vault write -force sys/managed-keys/gcpckms/tf-repro/test/sign
```

Expected failure:

```text
error initializing GCP CKMS wrapper client: failed to create KMS client: open {}: no such file or directory
```

The direct control signed with the same GCP key; the Terraform-managed key fails because Vault tries to open `"{}"` as a file. A local reproduction of this failure does not prove the behavior of GKE Workload Identity itself.

### Rerun after manually deleting `tf-repro` in Vault

In provider `5.12.0`, deleting the managed key outside Terraform can leave `vault_managed_keys.repro` in Terraform state even though `vault list sys/managed-keys/gcpckms` finds nothing. A no-op `terraform apply` does not rewrite `credentials`. Only in this disposable lab, and only after checking that no other managed keys exist, back up this Terraform state outside the repository and remove the stale state address:

```bash
BACKUP="$(mktemp "$HOME/vault-50985-state.XXXXXX")"
terraform state pull > "$BACKUP"
test -s "$BACKUP"
terraform state rm vault_managed_keys.repro
terraform plan
terraform apply
vault write -force sys/managed-keys/gcpckms/tf-repro/test/sign
```

Expect a create in the plan and the same `open {}: no such file or directory` error on test-sign. `terraform state rm` removes tracking only; it does not delete a Vault or Cloud KMS key. Do not use this sequence in a shared Vault or against state containing other managed keys. Keep the backup private; it may contain secrets. Avoid `terraform destroy` or `-replace` as a reset for a shared Vault: the collection resource can delete managed-key configurations beyond `tf-repro`.

## Cleanup

Run `terraform destroy` only from this lab's directory/state; `vault_managed_keys` deletion removes managed-key configurations. Then undo only the Vault pod-template fields introduced above, remove the Secret, and remove the test service account's key-scoped bindings and account. Check the rollout before deleting the Secret.

```bash
terraform destroy
kubectl -n "$VAULT_NS" patch sts "$VAULT_STS" --type=strategic -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"vault","env":[{"name":"GOOGLE_APPLICATION_CREDENTIALS","$patch":"delete"}],"volumeMounts":[{"mountPath":"/vault/userconfig/gcp","$patch":"delete"}]}],"volumes":[{"name":"gcp-kms-creds","$patch":"delete"}]}}}}'
kubectl -n "$VAULT_NS" rollout status "sts/$VAULT_STS"
kubectl -n "$VAULT_NS" delete secret vault-50985-creds
gcloud kms keys remove-iam-policy-binding "$KEY" --keyring="$RING" \
  --location="$REGION" --project="$PROJECT" \
  --member="serviceAccount:$EMAIL" --role=roles/cloudkms.viewer
gcloud kms keys remove-iam-policy-binding "$KEY" --keyring="$RING" \
  --location="$REGION" --project="$PROJECT" \
  --member="serviceAccount:$EMAIL" --role=roles/cloudkms.signerVerifier
gcloud iam service-accounts delete "$EMAIL" --project="$PROJECT"
```

The Cloud KMS key is not deleted by Terraform. If the key is no longer needed, arrange destruction of the dedicated test key version according to your GCP sandbox policy; do not destroy shared keys.

## References

- [VAULT-50985](https://hashicorp.atlassian.net/browse/VAULT-50985)
- [Vault managed-keys API](https://developer.hashicorp.com/vault/api-docs/system/managed-keys)
- [Terraform provider `vault_managed_keys` implementation (v5.12.0)](https://github.com/hashicorp/terraform-provider-vault/blob/v5.12.0/vault/resource_managed_keys.go)
- [Google Cloud KMS permissions and roles](https://cloud.google.com/kms/docs/reference/permissions-and-roles)
