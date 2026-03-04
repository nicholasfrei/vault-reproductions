# KB: AWS Secrets Engine Upgrade Nuances (`1.19.1` to `1.19.9/1.19.10`)

## Overview

This KB summarizes issues faced with a customer in relation to the AWS secrets engine in Vault versions `1.19.x`. There were several bugs/changes throughout these Vault versions, and some of these bug fixes inadvertently introduced new issues for customers that previously had working configurations. This impacted a ton of customers and multiple support tickets were opened by various large enterprises. Below, I will outline the various issues faced and the resolution steps taken. 

- STS client initialization failures
- root config write timeouts
- IAM signature/region failures during root rotation
- rotation schedule/window regressions in `1.19.9`

Use this document as a flow: identify the symptom family, apply the matching fix, then re-test.

## Summary of Errors Faced

### 1) Post-upgrade STS credential generation failures

Customers were facing credential generation failures across all interfaces (Terraform, UI, API) with errors indicating `could not obtain sts client` or similar. This happened for customers who upgraded to `1.19.4+`, had a `region` set, and had a default endpoint for `sts_endpoint`.

Command run:

```shell
vault read aws/creds/<role-name>
```

Errors seen:

```
Validation error: Failed to get AWS credentials: could not obtain sts client
Code: 400. Errors: could not obtain sts client
```

Vault debug logs also showed:

```
couldn't connect with config trying next: failed endpoint=sts.amazonaws.com failed region=us-west-2
```

Most common trigger in this case:

- `region` was set and `sts_endpoint` remained set to `sts.amazonaws.com`

Interpretation:

- After STS handling changes in `1.19.x` (including fix paths introduced around `1.19.4`), endpoint/region combinations became less forgiving.
- For affected upgraded mounts, the global default endpoint (`sts.amazonaws.com`) with explicit `region` became error-prone.

Fix:

- set a regional endpoint that matches `region` (for example `sts.us-west-2.amazonaws.com`)
- or unset `sts_endpoint` entirely
- validate network/firewall reachability to the STS endpoint in use

### 2) Root rotation failures with IAM signature errors

The customer was facing an issue where root credential rotation would fail.

Command run:

```shell
vault write -f aws/config/rotate-root
```

Error seen:

```
Code: 500. Errors: error calling GetUser: SignatureDoesNotMatch: Credential should be scoped to a valid region.
```

Finding:

- `iam_endpoint` was set to `iam.amazonaws.com`. With a `region` also set, the scoped IAM API call failed signature validation.

Fix:

- unset `iam_endpoint` in root config
- verify Vault root IAM user has exactly one active key for rotation flows

### 3) Intermittent root config update timeouts on legacy upgraded mounts

The customer was facing intermittent timeout errors when trying to read/write to their root config after upgrade.

Commands run:

```shell
vault write aws/config/root region=us-west-2 ...
vault read aws/config/root
```

Errors seen:

```
Error writing data to aws/.../config/root: context deadline exceeded
Canceled desc = context canceled
```

Typical handling:

- apply STS/endpoint and IAM key-hygiene remediations from issues 1 and 2 first
- if still unstable, use a controlled break-glass path:
  - export mount config/roles
  - recreate mount
  - reapply config and roles

### 4) Rotation schedule/window regressions in `1.19.9`

Customers with `rotation_schedule` or `rotation_window` set on `1.19.9` were facing continuous rotation manager errors and failed rotations. 

Sample config:

```shell
vault read aws/config/root 
```
```text
Key                           Value
---                           -----
rotation_schedule             0 0 * * *
rotation_window               1h
```

Error seen in Vault debug logs:

```
rotation job not inside rotation window, re-prioritizing and pushing back to queue
```

Resolution:

- upgrade to Vault Enterprise `1.19.10` or later fixed versions

## Safe Baseline Config Guidance

For regional deployments:

- set `region` explicitly
- avoid hardcoding global endpoints unless required
- prefer empty/unset `iam_endpoint`
- if `sts_endpoint` is set, use regional endpoint matching `region`
  - e.g. sts.us-west-2.amazonaws.com for region us-west-2

## References

1. Vault `1.19.x` known issues (rotation manager and rotation registrations)
   - https://developer.hashicorp.com/vault/docs/v1.19.x/updates/important-changes#known-issues
   - Known issue window: affected `1.19.0`, fixed in `1.19.10`

2. AWS STS configuration issue with unspecified STS endpoints
   - https://developer.hashicorp.com/vault/docs/v1.19.x/updates/important-changes#aws-sts-configuration-can-fail-with-unspecified-sts-endpoints
   - Affected: `1.19.0-1.19.3`, fixed in `1.19.4`
   - Workaround in affected versions: set both `sts_region` and `sts_endpoint` explicitly

3. AWS STS regional endpoints docs (public AWS reference)
   - https://docs.aws.amazon.com/IAM/latest/UserGuide/id_credentials_temp_region-endpoints.html