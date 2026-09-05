---
schema_version: 1
scenario_id: <scenario-slug>
workflow: create
artifact_type: scenario-brief
status: draft
scenario_revision: "0"
predecessors:
  - source-notes.md
  - links.md
owner: vault-scenario-planner
next_action: plan
updated_at: "<YYYY-MM-DDTHH:MM:SSZ>"
human_approval:
  required: true
  status: pending
  approver: ""
  approved_at: ""
  scope: authoring
---

# Scenario Brief

## Classification

- Type: `repro` | `runbook` | `kb` | `guide` | `script`
- Domain:
- Proposed path:
- Vault version(s): `unknown`
- Edition: `unknown`
- Deployment context: `local` | `Docker` | `Kubernetes` | `cloud` | `Enterprise`
- Storage backend: `unknown`

## Source material

- Request or incident:
- Local notes: `source-notes.md`
- References: `links.md`

## Problem statement

<!-- What user-visible behavior are we proving, explaining, or troubleshooting? -->

## Expected behavior

## Observed behavior

## Scope

- In scope:
- Out of scope:

## Preconditions

- Tools:
- Infrastructure:
- Credentials or test-only resources:
- Version constraints:

## Minimal reproduction or procedure

1.

## Validation criteria

- [ ] The initial behavior is observable.
- [ ] A control, workaround, or fixed behavior is observable when applicable.
- [ ] Commands have expected output or clear success criteria.
- [ ] Cleanup can be verified.

## Cleanup requirements

## Safety constraints

- [ ] No real credentials or customer identifiers are committed.
- [ ] Commands do not target non-local infrastructure by default.

## Open questions

- None.

## Planner decision

- Reason:

The planner may set `awaiting-approval`, but only an explicit human decision may set the metadata to `ready-for-authoring`.

