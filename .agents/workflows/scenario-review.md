# Scenario Review Workflow

Use this workflow after authoring and validation, or after maintenance changes.

## Entry criteria

Required inputs:

- `drafts/<scenario-slug>/scenario-brief.md`
- The proposed or updated scenario files
- `drafts/<scenario-slug>/validation-report.md`
- `drafts/<scenario-slug>/maintenance-report.md` when `workflow` is `maintain`

Read every metadata predecessor. The brief, validation report, and maintenance report when present must use the same `scenario_id` and `scenario_revision`.

Validation should be `passed`. If it is `partial`, review may continue only to identify gaps; the release decision cannot be `ready`. A `not-run` or revision mismatch blocks release review.

## Review

Run the `vault-scenario-reviewer` skill.

The reviewer must independently compare:

- The scenario against the brief
- The validation evidence against scenario claims
- The changes against `.agents/shared/quality-rubric.md`
- Commands and content against `.agents/shared/safety-rules.md`
- Structure and formatting against root `AGENTS.md`

Output:

- `drafts/<scenario-slug>/review-report.md`

## Decision

- `ready` with index recommendation `yes`: complete any required human approval. Use `next_action: human-approve` while pending, then `next_action: index` before the release index workflow.
- `ready` with index recommendation `no`: set `next_action: close` and record why indexing is intentionally skipped.
- `needs-changes`: set `next_action: remediate`, return `review-report.md` to the author, increment the scenario revision when files change, then revalidate.
- `blocked`: set `next_action` to `human-approve` or `collect-input` and obtain the named decision or missing evidence.

Do not downgrade a blocking finding merely to complete the workflow. Record accepted limitations explicitly.

