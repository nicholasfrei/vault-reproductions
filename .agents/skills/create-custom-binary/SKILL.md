---
name: create-custom-binary
description: Prepare and validate custom binaries through Common Release Tooling (CRT), with Vault version and packaging safeguards. Use for "create a custom binary", "customer build", "CRT custom build", or "choose a custom Vault version".
---

# Create Custom Binary

Prepare an identifiable, narrowly scoped custom build without changing normal release behavior.

## Quick Start

1. Confirm the source revision, patch, edition, platforms, and recipient.
2. Read the CRT references; isolate the branch and choose a package-compatible version.
3. Validate processed artifacts before authorized delivery; report evidence and gaps.

## When to Use

Use for diagnostic or patched builds in CRT-onboarded repositories, especially Vault. Do not use for normal releases, CRT onboarding, or unrelated CI failures.

## Step 1 — Establish the Build

- Read [CRT Custom Builds](https://hashicorp.atlassian.net/wiki/spaces/RELENG/pages/2303983722/CRT+Custom+Builds) and [CRT Configuration](https://hashicorp.atlassian.net/wiki/spaces/RELENG/pages/2303230114/CRT+Configuration). Follow repository rules and team protocols.
- Record the base SHA/tag, patch purpose, edition (including HSM/FIPS), OS/architecture, and artifact formats. Preserve unrelated work; use a dedicated branch from the intended base.
- Locate the version file and build matrices. For Vault, start with `version/VERSION`, `.github/workflows/build.yml`, and `.release/ci.hcl`.
- Obtain explicit authorization before commits, pushes, remote builds, or distribution. Do not promote a custom build as a normal release.

## Step 2 — Choose the Version and Scope

- Prefer a SemVer prerelease such as `2.1.3-custom`; add detail with dots (`2.1.3-custom.1`), not more hyphens. Prereleases sort below the corresponding stable version. Leave `+ent` and other build metadata to the build machinery.
- Inspect the target revision's package naming; RPM and DEB normalization can differ. For Vault, check `scripts/ci-helper.sh`'s `version_package` and workflow artifact-name calculations.
- On the custom branch only, restrict `.release/ci.hcl`'s `release_branches` and the build workflow's push-branch filter to that branch. Never merge these restrictions into normal release branches.
- Narrow platforms only when authorized; align build/test matrices and preserve required signing, scanning, and compliance processing.

## Step 3 — Validate and Deliver

- Run focused regression tests and configuration checks (`actionlint` for workflows). Rebuild from the new commit; rerunning an old commit retains its old version.
- In the Vault source checkout, check package naming:

  ```bash
  VAULT_VERSION=2.1.3-custom make ci-get-version-package
  ```

  Expected with the global hyphen-to-tilde helper:

  ```text
  2.1.3~custom
  ```

- Compare uploaded names with test downloads. For `Artifact not found for name:`, check naming before assuming compilation failed.
- Wait for CRT processing and confirm artifacts reach `hashicorp-crt-stable-local`; GitHub build success alone is insufficient.
- Download processed artifacts and SHASUMS, verify checksums, then test the displayed version, startup, and intended change in a disposable environment.
- Deliver validated artifacts and SHASUMS through the approved secure channel. Report the SHA, version, artifacts, actual checks, and limitations.

## Handling Missing Information

Ask only for details affecting correctness or safety. State missing source, CRT access, or validation; never invent readiness or bypass processing.

## Anti-Patterns to Avoid

| Pattern | Consequence | Instead |
| --- | --- | --- |
| `2.1.3_custom` or `2.1.3.custom` | Invalid SemVer; Vault startup/plugin-version parsing can fail | Use `2.1.3-custom` |
| Multiple hyphens, e.g. `2.1.3-team-custom` | Valid SemVer, but a global hyphen-to-tilde helper can disagree with RPM/DEB names | Prefer `2.1.3-team.custom`; verify actual artifact names |
| Disabling tests or processing to get green CI | Hides defects or ships unvalidated artifacts | Fix the mismatch and validate the processed build |
