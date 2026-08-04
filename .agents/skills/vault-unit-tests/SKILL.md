---
name: vault-unit-tests
description: Write or review Vault Enterprise unit tests using repo-native patterns. Covers test placement, external vs internal test selection, path and platform edge cases, assertions, and required verification.
---

Write, move, or review a Vault Enterprise unit test in `~/repos/vault-enterprise` using existing repo conventions first, with minimal changes and explicit verification.

## When to use

Use this skill when the request involves any of:

- Adding a new unit test or regression test in `vault-enterprise`
- Moving a test between internal package tests and `vault/external_tests/`
- Reviewing whether a Vault test is in the right place, named correctly, or asserting the right thing
- Confirming whether a test truly exercises a code path or is accidentally skipped, too weak, or masked by unrelated failures

Do not use this skill for general product troubleshooting without changing tests. Use a diagnosis command first unless the user explicitly wants test work.

## Primary repo

- Repository: `~/repos/vault-enterprise`

If that path is missing, ask the user to confirm the correct repo location before making claims about test placement or conventions.

## Core rule: inspect existing tests first

Before writing or moving a test:

1. Find the production code path being exercised.
2. Find at least 3 to 5 comparable tests already in the repo.
3. Match the nearest existing package, naming pattern, setup style, and assertion style.
4. Prefer the smallest correct change.

Do not invent a new test area or helper unless the repo already points there or the existing structure clearly does not fit.

## Placement rules

Choose the test location based on the behavior under test, not the file you first found.

### Use internal package tests when:

- The test must call unexported functions or methods.
- The test must construct internal types directly and there is no stable public path.
- The test is tightly coupled to implementation details rather than externally visible behavior.

Examples:

- `vault/audit_test.go`
- `vault/logical_system_test.go`

### Use `vault/external_tests/...` when:

- The behavior is exercised through the public API, a test cluster, or externally visible server behavior.
- The test should validate behavior at the package boundary, not implementation internals.
- There is already a feature-area external test package that fits.

Examples:

- `vault/external_tests/audit/`
- `vault/external_tests/router/`
- `vault/external_tests/core/`

### Placement heuristics

- If the behavior is audit-related and there is already a package under `vault/external_tests/audit`, prefer that over creating a new directory.
- If the test uses `minimal.NewTestSoloCluster` or `vault.NewTestCluster` and makes real API calls, that is usually a strong sign it belongs in `external_tests`.
- If the test requires `TestCoreUnsealed`, pause and check whether the same behavior can be tested externally first. In Vault, external cluster-based tests are often preferred for new work.

## How to choose internal vs external for path validation

For path-validation behavior, decide what you actually need to prove.

### Use an internal test if you need to prove:

- An unexported validation helper or method returns a precise result before backend creation.
- A path is classified a certain way independent of later file creation or backend init.

### Use an external test if you need to prove:

- The public API path accepts or rejects a configuration in the real server path.
- The regression is about externally observable behavior, not just helper internals.

Important: external audit tests can fail for reasons unrelated to the target validation, such as real file backend creation, permissions, or filesystem semantics. When that happens, assert on the specific error you care about instead of demanding unconditional success.

## Test writing checklist

Before editing:

1. Identify the exact production file and lines under test.
2. Find 3 to 5 comparable tests in the same feature area.
3. Check whether `external_tests` already has a matching package.
4. Confirm whether the test should exercise the public API or an internal helper.

While writing:

1. Keep the change minimal.
2. Reuse existing helpers and cluster builders.
3. Use table-driven subtests when the behavior varies by path or option.
4. Use comments only when they clarify the test's purpose or an environment-specific nuance.
5. Prefer `require.*` assertions when failure should stop the subtest.
6. Assert on the exact behavior you care about. Do not require success if a later unrelated phase can legitimately fail.

After writing:

1. Confirm the test name describes what is truly being guaranteed.
2. Confirm the comments state the control case and the platform nuance clearly.
3. Run the narrowest relevant test command first.
4. If practical, compare with at least one similar test file to ensure style consistency.

## Formatting and style expectations

- Match the nearest local package's style and imports.
- Use ASCII unless the file already requires otherwise.
- Prefer concise, behavior-oriented test names.
- Avoid over-abstracting helpers for one small test.
- Use `t.Run(...)` for case matrices.
- Prefer the existing setup style in that package:
  - `minimal.NewTestSoloCluster(...)`
  - `vault.NewTestCluster(...)`
  - `TestCoreUnsealed(...)`
- Keep comments factual. Explain what the test proves, not what the code obviously does.

## Review checklist for an existing test

When reviewing a Vault test, explicitly check:

1. Is it in the right package and directory?
2. Does it use the right test style for that subsystem: external cluster test vs internal helper test?
3. Does it assert the intended behavior, or a weaker side effect?
4. Could unrelated backend creation or filesystem behavior mask the intended assertion?
5. Are platform-specific claims accurate?
6. Is there a control case proving the check still works?
7. Does the test name and comment match what is truly guaranteed?
8. Is there unnecessary duplication with an existing test in a better location?

## Suggested tool workflow

1. Search for the production code path with `grep`.
2. Search for comparable tests with `glob` and `grep`.
3. Read 3 to 5 nearby tests before editing.
4. If moving a test, remove the old duplicate after the new one is in place.
5. Run a narrow `go test` command first.
6. If the user asked for review, report findings first with file references.

## Verification requirements

At minimum, run the narrowest test command that proves the changed test compiles and executes.

Examples:

```bash
go test ./vault/external_tests/audit -run TestAudit_PluginDirectorySecurityCheck_WithPathOrFilePath
```

```bash
go test ./vault -run TestAudit_enableAudit
```

If a test fails for an unrelated reason:

- explain the unrelated blocker clearly
- tighten the assertion or test scope if appropriate
- rerun the smallest relevant command

Do not report a test as validated unless you actually ran it and saw it pass, or you clearly label what prevented verification.

## Output expectations

When finishing the task, provide:

1. What changed
2. Why the test belongs in that location
3. What exact behavior the test now proves
4. The command run for verification
5. Whether it passed
6. Any remaining limitations, especially platform-specific ones

## Common Vault patterns to prefer

- For external audit behavior, look in `vault/external_tests/audit/` first.
- For path and public API behavior, cluster-based tests are often preferred over direct internal helpers if the public path is the real target.
- Keep one real host-path control case that proves the rejection still works.