---
name: scenario-maintainer
description: Assesses and updates published Vault scenarios when releases, fixes, documentation, or user reports introduce drift. Use for scenario maintenance, deprecation, or revalidation.
---

# Scenario Maintainer

Turn new evidence into a bounded maintenance decision before changing published content.

## Inputs

Read:

- Root `AGENTS.md`
- All files under `.agents/shared/`
- The published scenario and its `README.md` entry
- `drafts/<scenario-slug>/source-notes.md`
- `drafts/<scenario-slug>/links.md`
- `drafts/<scenario-slug>/scenario-brief.md`; bootstrap it from the published scenario when absent
- Prior contract reports when available

## Process

1. Confirm intake artifacts are `ready` and use the stable scenario ID, `maintain` workflow, published path, baseline brief, and current scenario revision.
2. Compare new evidence with the scenario's claims, commands, versions, and expected output.
3. Classify the impact as `no-change`, `content-update`, `revalidation-required`, or `deprecate`.
4. Identify affected files and validation that must be repeated.
5. Do not infer a fixed version or upstream status from an unmerged change.
6. For bounded corrections, propose and apply the smallest update.
7. Increment the scenario revision before changing the scenario or supporting files.
8. Return `maintenance-report.md` to the planner when the purpose, type, or reproduction path changes materially.
9. Require validation for every published content change and behavioral validation for changed executable behavior.

## Output

Copy `.agents/templates/maintenance-report.md` to:

```text
drafts/<scenario-slug>/maintenance-report.md
```

Write the assessment before editing published files, then record changes made.

Set metadata status and next action to:

- `no-change` and `close`
- `needs-input` and `collect-input` or `human-approve`
- `ready-for-update` and `maintain`
- `ready-for-validation` and `validate`
- `ready-for-review` and `review`
- `deprecate` and `human-approve`, with aggregate human approval required and pending

Use `ready-for-update` for the accepted assessment before editing. After applying and recording a bounded change, move to `ready-for-validation`.

Hand `maintenance-report.md` with changed scenarios to the validator, reviewer, and index curator. Update `README.md` only through the release index workflow.

