---
name: vault-scenario-validator
description: Executes and records evidence for a Vault scenario against its approved brief. Use after authoring or maintenance to verify commands, behavior, cleanup, and reproducibility.
---

# Vault Scenario Validator

Validate independently from the author. Record actual evidence; do not silently repair the scenario.

## Inputs

Read:

- `.agents/shared/contract-metadata.md`
- `.agents/shared/safety-rules.md`
- `.agents/shared/quality-rubric.md`
- `drafts/<scenario-slug>/scenario-brief.md`
- `drafts/<scenario-slug>/maintenance-report.md` for maintenance work
- `drafts/<scenario-slug>/review-report.md` when revalidating review remediation
- The scenario and supporting files
- Existing `validation-report.md`, when revalidating

## Process

1. Confirm every predecessor uses the same `scenario_id`, `workflow`, and current `scenario_revision`.
2. List every contract actually consumed in metadata `predecessors`, including maintenance or review reports when applicable.
3. Confirm the test environment and Vault version/edition.
4. Check prerequisites before executing the scenario.
5. Run the narrowest safe checks that satisfy each validation criterion.
6. Capture commands, exit status, relevant redacted output, and cleanup result.
7. Test the control, workaround, or fixed behavior when required by the brief.
8. Do not use shared or non-local infrastructure without human confirmation.
9. Do not turn expected output printed by a script into proof that the underlying behavior occurred.
10. Record skipped checks and blockers.

## Output

Copy `.agents/templates/validation-report.md` to:

```text
drafts/<scenario-slug>/validation-report.md
```

Set metadata status and next action to:

- `passed` and `review` only when all applicable criteria were observed
- `failed` and `remediate` when observed behavior contradicts an otherwise valid scenario
- `failed` and `replan` when the hypothesis or scope is wrong
- `partial` and `remediate` or `replan`, according to the evidence gap
- `not-run` and `collect-input` or `human-approve` when execution is blocked

Copy the exact current scenario revision into the report. Never carry a prior `passed` decision across a revision change.

