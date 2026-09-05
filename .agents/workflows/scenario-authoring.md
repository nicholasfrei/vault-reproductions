# Scenario Authoring Workflow

Use this workflow to turn rough evidence into a validated Vault scenario.

## Inputs

Create `drafts/<scenario-slug>/` with:

- A copy of `.agents/templates/source-notes.md` for the request, sanitized incident evidence, or idea
- A copy of `.agents/templates/links.md` for documentation, issues, PRs, and source references

Fill the common frontmatter defined in `.agents/shared/contract-metadata.md`. These files may be incomplete; use `needs-input` and preserve unknowns instead of filling them with assumptions.

When intake is sufficient to plan, set both artifacts to `ready`, use the same `scenario_id`, and set `next_action: plan`. A `links.md` file with no available reference may still be `ready` when the absence is recorded explicitly.

## 1. Plan

Run the `vault-scenario-planner` skill.

Output:

- `drafts/<scenario-slug>/scenario-brief.md`

Gate:

- The planner sets `awaiting-approval` when the brief is technically complete and `next_action` to `human-approve`.
- A human accepts the scope by recording approval and changing the brief to `ready-for-authoring`.
- Continue only when the brief is `ready-for-authoring` and `human_approval.status` is `approved`.
- Ask for human input when a missing fact materially changes safety, scope, or scenario type.

## 2. Author

Run the `vault-scenario-author` skill.

Inputs:

- `scenario-brief.md`
- `validation-report.md` when resuming after `failed` or `partial`
- `review-report.md` when resuming after `needs-changes`
- Root `AGENTS.md`
- Files under `.agents/shared/`
- Relevant neighboring scenarios

Output:

- The scenario and its supporting files at the path approved in the brief

Set `scenario_revision` to `"1"` for the first implementation. Increment it in `scenario-brief.md` before every later change to the scenario or supporting files. A revision change invalidates prior validation and review decisions.

The author must not update `README.md`.

## 3. Validate

Run the `vault-scenario-validator` skill.

Output:

- `drafts/<scenario-slug>/validation-report.md`

Gate:

- `passed` with `next_action: review`: send to scenario review.
- `partial` or `failed` with `next_action: remediate`: return the report to the author.
- `partial` or `failed` with `next_action: replan`: return the report to the planner and revise the brief.
- `not-run`: stop for the named blocker or human decision.

## Handoff

The scenario, brief, and validation report are the complete handoff to review. Their `scenario_id` and `scenario_revision` must match. Chat history is not required.

