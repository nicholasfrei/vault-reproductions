---
name: vault-scenario-reviewer
description: Reviews a Vault scenario, its brief, and validation evidence for accuracy, safety, reproducibility, and repository fit. Use before publication or after maintenance.
---

# Vault Scenario Reviewer

Perform an evidence-based release review. Do not edit the scenario while reviewing.

## Inputs

Read:

- Root `AGENTS.md`
- All files under `.agents/shared/`
- `drafts/<scenario-slug>/scenario-brief.md`
- `drafts/<scenario-slug>/validation-report.md`
- `drafts/<scenario-slug>/maintenance-report.md` when `workflow` is `maintain`
- `drafts/<scenario-slug>/source-notes.md` and `links.md`
- The complete scenario diff and relevant neighboring scenarios

## Review

1. Confirm all required predecessors use the same `scenario_id`, `workflow`, and current `scenario_revision`.
2. Confirm the implementation satisfies the brief without scope drift.
3. Apply every category in `.agents/shared/quality-rubric.md`.
4. Verify important claims are supported by validation, official docs, source, or upstream references.
5. Check exact commands, paths, policy semantics, versions, and error strings.
6. Check redaction, target safety, rollback, and cleanup.
7. Search for overlap with existing scenarios and index entries.
8. Separate blocking findings from optional improvements.
9. Require human approval where `.agents/shared/safety-rules.md` specifies a gate.

## Output

Copy `.agents/templates/review-report.md` to:

```text
drafts/<scenario-slug>/review-report.md
```

Set metadata status and next action to:

- `ready` and `index` when every applicable rubric category passes, indexing is recommended, and approval is not required or is already approved
- `ready` and `close` when the scenario is intentionally not indexed
- `needs-changes` and `remediate` when the author can resolve blocking findings
- `blocked` and `collect-input` when required evidence or an unplanned human decision is unavailable

Copy the exact reviewed scenario revision into the report. Provide a precise README and Known Bugs action when status is `ready`. A partial, not-run, or stale validation report cannot produce a `ready` decision.

When an otherwise-ready report reaches a planned human gate, keep status `ready`, set `next_action: human-approve`, set aggregate approval to `pending`, and stop. After explicit approval is recorded, set the next action to `index` or `close`. Do not record `approved` without an explicit human decision.

