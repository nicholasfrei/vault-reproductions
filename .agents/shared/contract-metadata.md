# Contract Metadata

Every Markdown handoff under `drafts/<scenario-slug>/` begins with YAML frontmatter using this schema. The metadata is the machine-readable source of truth for artifact state; the Markdown body explains the evidence and reasoning.

## Common block

```yaml
---
schema_version: 1
scenario_id: <scenario-slug>
workflow: create | maintain
artifact_type: source-notes | links | scenario-brief | validation-report | review-report | maintenance-report
status: <artifact-specific-status>
scenario_revision: "0"
predecessors: []
owner: <human-or-specialist-role>
next_action: <action>
updated_at: "<YYYY-MM-DDTHH:MM:SSZ>"
human_approval:
  required: false
  status: not-required
  approver: ""
  approved_at: ""
  scope: ""
---
```

## Field rules

- `schema_version`: Integer contract schema version. The current version is `1`.
- `scenario_id`: Stable, lowercase kebab-case identifier. It must match the directory name in `drafts/<scenario-slug>/` and must not change when the published file moves.
- `workflow`: `create` for a new scenario or `maintain` for an existing published scenario.
- `artifact_type`: The template or handoff type. Do not invent aliases.
- `status`: One value from the artifact-specific status list below. Do not repeat status in the Markdown body.
- `scenario_revision`: Quoted, monotonic workflow revision shared by the brief, implementation, validation, review, and maintenance artifacts. It is not a Vault version or Git commit. Use `"0"` before implementation exists. The author or maintainer increments it before changing scenario or supporting files. Validation and review copy the exact revision they evaluated.
- `predecessors`: Paths to the contract files used to produce the artifact, relative to the same draft directory. Use `[]` only when there is no predecessor.
- `owner`: Human or specialist role accountable for resolving the artifact's current state.
- `next_action`: One action from the list below. Do not hide the next action only in prose.
- `updated_at`: UTC timestamp in RFC 3339 format.
- `human_approval`: Aggregate approval for the current gate. Specialized approval details may remain in the body.

## Human approval

Allowed `human_approval.status` values:

- `not-required`: No human judgment gate applies.
- `pending`: Approval is required and the workflow must stop.
- `approved`: The named human approved the stated `scope`.
- `rejected`: The named human rejected the stated `scope`.

Agents must never mark their own output `approved`. They may record an explicit human decision, including the approver and timestamp.

When approval is required:

- Set `required: true`.
- Set `status: pending` until a human responds.
- Set `next_action: human-approve`.
- Do not continue through the gate until `status: approved`.

## Artifact statuses

- `source-notes`: `draft` | `ready` | `needs-input`
- `links`: `draft` | `ready` | `needs-input`
- `scenario-brief`: `draft` | `needs-input` | `rejected` | `awaiting-approval` | `ready-for-authoring`
- `validation-report`: `not-run` | `passed` | `failed` | `partial`
- `review-report`: `draft` | `ready` | `needs-changes` | `blocked`
- `maintenance-report`: `assessing` | `needs-input` | `no-change` | `ready-for-update` | `ready-for-validation` | `ready-for-review` | `deprecate`

## Next actions

Use one of:

- `collect-input`
- `plan`
- `human-approve`
- `author`
- `maintain`
- `validate`
- `review`
- `remediate`
- `replan`
- `index`
- `close`
- `none`

Set `owner` to the role expected to take `next_action`:

- `plan` or `replan`: `vault-scenario-planner`
- `author` or `remediate`: `vault-scenario-author`
- `maintain`: `scenario-maintainer`
- `validate`: `vault-scenario-validator`
- `review`: `vault-scenario-reviewer`
- `index`: `scenario-index-curator`
- `collect-input` or `human-approve`: `human`
- `close`: `workflow-owner`
- `none`: `none`

## Standard transitions

Creation:

1. Intake `ready` -> `plan`.
2. Brief `awaiting-approval` -> `human-approve`.
3. Approved brief `ready-for-authoring` -> `author`.
4. Validation `passed` -> `review`.
5. Validation `failed` or `partial` -> `remediate` or `replan`.
6. Validation `not-run` -> `collect-input` or `human-approve`.
7. Review `needs-changes` -> `remediate`.
8. Review `blocked` -> `collect-input` or `human-approve`.
9. Review `ready` -> `human-approve` when required, then `index` or `close`.

Maintenance:

1. Intake `ready` -> `maintain`.
2. Maintenance `no-change` -> `close`.
3. Maintenance `needs-input` -> `collect-input` or `human-approve`.
4. Maintenance `ready-for-update` -> `maintain`.
5. Maintenance `ready-for-validation` -> `validate`.
6. Maintenance `ready-for-review` -> `review`.
7. Maintenance `deprecate` -> `human-approve`, then validation, review, and index update.
8. Material scope change -> `replan`.

## Transition invariants

1. Update `status`, `owner`, `next_action`, and `updated_at` together.
2. A consumer must stop when `schema_version` is unsupported, a required predecessor is missing, or metadata conflicts with the current `scenario_id`, `workflow`, or `scenario_revision`.
3. A scenario revision change invalidates prior validation and review decisions. New reports must be produced for the new revision.
4. `scenario-brief` may become `ready-for-authoring` only after its human approval is `approved`.
5. `review-report` may become `ready` only when validation is `passed` for the same scenario revision.
6. Release indexing may run only when review is `ready` and human approval is either `not-required` or `approved`.
7. If a scope change alters purpose, type, path, safety constraints, or version claims, return to planning and require approval of the revised brief.
8. `maintenance-report` may become `ready-for-review` only after validation is `passed` for the same scenario revision.
