---
name: vault-unit-tests
description: Write or review Vault Go unit and regression tests using the target checkout's authoritative go-test skill; route frontend tests to its ui skill. Use when asked to "add a Vault unit test", "write a regression test", "review this Vault test", or "check whether this test actually ran". Check assertions, regression evidence, and execution results without duplicating repository standards.
---

# Vault Unit Tests

Use this adapter to connect a support investigation or test review to the target Vault checkout's native testing guidance.

## Quick Start

1. Identify the requested mode: write, move, review, or verify tests, and the behavior to prove.
2. Resolve the Vault checkout and revision; read its `AGENTS.md` and the native Go or UI skill below.
3. Inspect the production path, relevant existing tests, and supplied results.
4. Make only requested changes; verify with the repository's appropriate commands when execution is in scope.
5. Report findings or changes, the behavior established, actual check statuses, and remaining gaps.

## When to Use

Use this skill when:
- Adding or moving a Vault Go unit or regression test.
- Reviewing test placement, assertions, stability, or whether a regression is exercised.
- Verifying that selected tests actually execute on the intended build and platform.

Do not use this skill when:
- Diagnosing a defect or mapping affected/fixed versions without a test task; use [find-vault-bugs](../find-vault-bugs/SKILL.md).
- Drafting an implementation handoff or Jira bug; use [create-implementation-doc](../create-implementation-doc/SKILL.md) or [vault-jira-bug](../vault-jira-bug/SKILL.md).
- Creating or reviewing a troubleshooting scenario; use [vault-scenario-author](../vault-scenario-author/SKILL.md) or [vault-scenario-reviewer](../vault-scenario-reviewer/SKILL.md).

For Vault UI tests, use Step 1 to load the native `ui` guidance, then follow that workflow. Do not apply Go package rules or commands to frontend tests.

## Step 1 — Resolve the Checkout and Load Its Authority

1. Use the checkout named in the task. Otherwise inspect the current repository; if it is not the Vault source checkout, consult the optional `.agents/instructions/internal-tools.md` in the support repository for local mappings. Confirm the candidate contains the requested source. Do not assume a personal absolute path or silently choose between multiple checkouts.
2. Record the relevant revision and inspect working-tree changes before editing. Preserve existing work.
3. Read the target checkout's `AGENTS.md`, applicable nested instructions, and the preferences, always-on skills, and file-type instructions it requires.
4. Load the authority for the requested work, resolving every path below from that checkout:

   | Work | Read before proceeding |
   | --- | --- |
   | Go tests | `.agents/skills/go-test/SKILL.md` and its required `.agents/instructions/go-tests.instructions.md`; also load `.agents/instructions/testing.instructions.md` as directed by the instruction index. |
   | UI tests | `.agents/skills/ui/SKILL.md`, its required `.agents/instructions/ember-general.instructions.md`, and applicable UI test/file-type instructions, including `.agents/instructions/ember-tests.instructions.md`. |

Use those sources for placement, package selection, naming, helpers, cleanup, parallelism, formatting, and required checks. Nearby tests are examples, not permission to bypass current restrictions. Do not reproduce those standards here or substitute remembered rules. If authorities are missing or disagree in a way that affects the task, follow Handling Missing Information.

## Step 2 — Establish What the Test Must Prove

1. Trace the supplied symptom or requirement to the production behavior and relevant existing tests. Read enough comparable tests and helper implementations to justify the approach; do not impose a fixed sample count.
2. State the setup, triggering action, and observable outcome. Identify a meaningful control or boundary case that distinguishes the defect from intended behavior. Confirm build tags, edition, platform, and prerequisites that determine whether the case can execute.
3. Evaluate placement and fixtures using the loaded authority. Do not infer that all public-API tests belong in one directory or copy a prohibited helper from an older test.
4. For review-only requests, inspect source and supplied results without automatically editing or running tests. Execute checks only when verification is part of the requested review; report unexecuted checks as such. For write or move requests, make the smallest useful change and check for duplicate coverage before removing an old test.

## Step 3 — Check Assertions and Stability

- Require an observable success result for acceptance cases. For rejection cases, assert the specific error identity, code, or stable diagnostic supported by the code, plus relevant state or side effects. Check setup errors before exercising the behavior.
- Reject assertions that merely exclude one error string: an unrelated permission, transport, or backend error must not make an acceptance test pass. If the target is only a validation stage, isolate it through a repository-approved test boundary and assert its explicit result; do not claim that proves the complete operation succeeds.
- Check that the test reaches the intended branch and would detect the reported defect. Avoid tautologies, unchecked mock expectations, and assertions that only prove setup or framework behavior.
- Apply the native isolation and waiting guidance. Look for shared state, uncontrolled time, filesystem/platform assumptions, and external dependencies that could mask the outcome. Use isolated fixtures and deterministic synchronization or bounded condition waits; do not fix flakes by adding sleeps, swallowing errors, skipping the failing case, or retrying until one run passes.
- Keep platform-specific claims limited to platforms actually exercised. A skip on the current host does not validate behavior on the target host.

## Step 4 — Verify the Regression and Inspect Actual Results

For test additions, moves, or edits, run verification unless the user explicitly requests a draft/source-only change or execution is blocked. For reviews, use the execution scope established in Step 2.

When execution is in scope:

1. Derive commands from the target repository's instructions and build/test configuration, including the correct module, edition/build tags, prerequisites, and test selector. Run the narrow relevant target first, then required repository checks. Broaden or repeat beyond those only for new changes, failures, or unresolved concerns.
2. For a bug regression, run the same test against the relevant pre-fix code when practical, then the fixed code with equivalent fixtures and configuration. Preserve working-tree changes; do not reset or overwrite user work to construct a baseline. Require a failure at the intended behavioral assertion before the fix and a pass after it. A compilation error, missing license, setup failure, or unrelated assertion failure is not regression evidence. If a safe baseline or fix is unavailable, report the missing comparison explicitly.
3. Inspect output for the named test and required subtests, not just exit status or a package-level `ok`. For direct `go test` runs, use `-count=1` for fresh execution and `-v` or `-json` to observe selection and outcomes, while retaining required repository flags. Use the native runner's equivalent evidence for UI tests.
4. Distinguish `passed`, `failed`, `skipped`, `cached`, `no tests matched`, `blocked`, and `not run`. A cached result is historical evidence, not a fresh run; skipped cases and empty selections do not prove the target behavior. Correct selectors or prerequisites within scope and rerun affected checks; otherwise record the gap.
5. Investigate unrelated failures without weakening the expected behavior. Report environmental blockers separately from assertion failures. Do not infer affected release ranges or a shipped fix from a successful local test.

## Step 5 — Report the Result

For changes, state the files changed, why the placement follows the loaded authority, and exactly what the test proves. For reviews, lead with actionable findings: severity, file/line, the missed behavior or false-confidence risk, and the smallest correction; say when no actionable findings were found.

Include the authority paths consulted and a concise verification record: checkout/revision, command and working directory, relevant build/platform settings, actual status and decisive output. Separate observed runs from supplied evidence and proposed commands. State before-fix/after-fix results, skipped cases, blockers, or checks not run. Scope any readiness conclusion to the files and evidence examined. Save a report only when requested or needed for a handoff.

## Examples

### Review a Weak Path-Validation Test

Request: "Review this audit-path test; it accepts any error other than the path-rejection message."

Resolve the checkout, load `go-test` and required instructions, and trace validation through backend creation. If a permission error can satisfy the assertion, report that acceptance is unproven with the offending file/line. Recommend a controlled valid-path case that asserts successful creation and the relevant state, plus an invalid-path control that asserts the specific rejection. If only helper validation is intended, use a boundary permitted by the native guidance and narrow the stated guarantee. For a static review, finish with `not run — source review only` rather than claiming a passing test.

### Add a Regression Test and Evaluate Its Evidence

Request: "Add a regression test for a rejected valid configuration."

Load the native guidance, choose the existing feature test location it supports, and assert acceptance for the valid fixture and the appropriate rejection for its control. Run the selected case against pre-fix and fixed code when available. An illustrative valid evidence pair is `failed — valid fixture rejected at the acceptance assertion` before the fix and `passed — named case and control executed` after it. If the fixed run reports `no tests to run`, correct the selection/build configuration before claiming a pass; if the baseline cannot execute, report that regression sensitivity remains unverified.

### Route a Frontend Test Request

Request: "Review a Vault UI component test."

Load the checkout's `ui` skill and its Ember test instructions. Review the component's observable behavior using those conventions. For requested execution, follow the UI verification requirements and report the selected tests and any required build/full-suite checks with their actual statuses.

## Handling Missing Information

If the checkout, revision, expected behavior, or required native guidance is missing, ask for the specific missing input before repository-dependent edits or execution. Continue any source-only review that the supplied material supports, clearly identifying provisional conclusions. If an older checkout lacks the skills, request an authoritative guidance location; do not silently apply another revision's standards. Resolve conflicting guidance by instruction precedence; if still ambiguous, cite the conflicting paths and ask before dependent changes. Treat the optional local mapping file's absence as a discovery gap, not a product failure.

## Anti-Patterns to Avoid

| Anti-pattern | Symptom | Correction |
| --- | --- | --- |
| Cloned or remembered standards | Placement or helpers conflict with the current repository | Load native skills and their required instructions from the resolved checkout. |
| Weak negative assertion | Any error except the expected rejection passes | Assert the actual success or specific failure and relevant outcome. |
| Flake suppression | Sleeps, skips, or retries hide nondeterminism | Fix fixtures or synchronization under the native guidance; retain failure evidence. |
| False-green verification | Cached, skipped, or unmatched tests are called validated | Inspect named cases and report actual execution statuses. |
| Invalid regression baseline | Build/setup failure is called proof of the bug | Require failure at the targeted behavioral assertion before the fix. |
| Review expands into implementation | Tests are edited or run without that scope | Return findings and explicit verification gaps for a source-only review. |
