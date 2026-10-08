---
name: vault-unit-tests
description: Write, move, or review Go unit and regression tests in Vault Enterprise, using its authoritative go-test skill. Use when asked to "add a Vault unit test", "write a regression test", "review this Vault test", or "check whether this test actually ran".
---

# Vault Unit Tests

Create or review tests in `vault-enterprise` using its native testing guidance.

## Quick Start

1. Identify the behavior to prove and whether the request is to write, move, review, or verify a test.
2. Read `vault-enterprise/AGENTS.md` and its authoritative `.agents/skills/go-test/SKILL.md` (or the corresponding files in a user-specified checkout).
3. Inspect the production path and comparable tests, then make only the requested changes.
4. Run the relevant checks when in scope; report what the test proves and what actually ran.

## When to Use

Use this skill when adding or moving a Vault Go unit or regression test, reviewing its placement or assertions, or checking whether it actually executed.

Do not use this skill when:
- Investigating a defect or affected versions without a test task; use [find-vault-bugs](../find-vault-bugs/SKILL.md).
- Creating or reviewing a troubleshooting scenario; use [vault-scenario-author](../vault-scenario-author/SKILL.md) or [vault-scenario-reviewer](../vault-scenario-reviewer/SKILL.md).

For Vault UI tests, follow the checkout's `.agents/skills/ui/SKILL.md` instead of Go test rules.

## Step 1 — Instructions

1. Read `vault-enterprise/AGENTS.md`, applicable instructions, and `.agents/skills/go-test/SKILL.md`. Follow the additional instructions, if applicable.
2. Defer to those files for placement, helpers, isolation, formatting, and verification. Do not copy a pattern from an older test when it conflicts with current rules.

## Step 2 — Establish What the Test Must Prove

1. Trace the requested behavior through the production code and read comparable tests and helpers in the feature area.
2. Identify the setup, action, expected result, and a useful control or boundary case. Check edition, build tags, platform, and prerequisites that affect execution.
3. Choose the test package and fixtures using the Enterprise guidance. Prefer an existing external test package for public behavior; use internal tests only when the current guidance permits and the behavior requires it. For related cases, use table-driven subtests with `t.Run`, keeping resources isolated as the checkout requires.
4. Make the smallest useful change. For review-only requests, inspect the test and supplied evidence without editing it; run tests only if verification is requested.

## Step 3 — Check Assertions and Stability

- Assert observable success for acceptance cases and a specific error or state for rejection cases. Check setup errors separately; an unrelated permission or backend failure must not make the test pass.
- Confirm the assertions reach the intended branch and would fail for the reported defect. If testing only validation, do not claim to prove the complete operation succeeds.
- Check for shared state, filesystem or platform assumptions, and flaky waiting. Follow the checkout's isolation and waiting rules; do not hide failures with sleeps, skips, or retries.

## Step 4 — Verify the Regression and Inspect Actual Results

For test changes, verify unless the user requests a draft or execution is blocked. For reviews, use the requested verification scope.

1. Derive the command, build tags, and prerequisites from the checkout. Run the narrow target first, then required checks.
2. When safe and practical, show that a regression test fails at the intended assertion before the fix and passes after it. A build or setup failure is not regression evidence; do not disturb existing work to create a baseline.
3. Inspect the named test and subtests, not only the package exit status. For direct `go test`, use `-count=1` and `-v` or `-json` alongside required flags; distinguish fresh passes from skipped, cached, or unmatched cases.
4. Report unrelated failures or blockers without weakening assertions or claiming an untested platform or release is validated.

## Step 5 — Report the Result

For changes, state the files changed, why the test belongs there, and what it proves. For reviews, lead with actionable findings and file references, or state that none were found.

Include the checkout/revision, guidance consulted, commands and actual results. Distinguish observed runs from supplied results and note skipped cases, blockers, or checks not run. Save a report only when requested or needed for a handoff.

## Examples

### Add a Regression Test

Request: "Add a regression test for a valid configuration that was rejected."

Read the Enterprise `go-test` guidance and comparable feature tests. Add isolated table-driven cases for the valid configuration and an invalid control; assert success for the first and the specific rejection for the second. Run the named test and both subtests. If a safe pre-fix baseline is available, confirm the valid case fails at its acceptance assertion there and passes after the fix; otherwise report that comparison as unverified.

### Review a Weak Assertion

Request: "Review this audit-path test; it passes if the error is not the expected rejection."

Trace validation and backend creation. If a permission error could satisfy the assertion, identify the file and line, and recommend a valid-path case that proves success plus an invalid-path control that proves the specific rejection. For a source-only review, report the tests as not run.

## Handling Missing Information

If the checkout, expected behavior, or native guidance is missing, ask for the specific input before editing. Do not silently use guidance from another revision. For a source-only review, state which conclusions remain provisional.

## Anti-Patterns to Avoid

| Anti-pattern | Symptom | Correction |
| --- | --- | --- |
| Cloned standards | Old tests use prohibited placement or helpers | Follow the target checkout's current guidance. |
| Shared table cases | Subtests reuse mutable resources | Isolate resources per case. |
| Weak assertion | An unrelated error makes an acceptance case pass | Assert actual success or a specific rejection. |
| False-green result | A cached, skipped, or unmatched case is called validated | Inspect named cases and report what ran. |
| Invalid baseline | Setup failure is called proof of the bug | Require failure at the targeted behavioral assertion. |
