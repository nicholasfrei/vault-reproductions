---
schema_version: 1
scenario_id: <scenario-slug>
workflow: maintain
artifact_type: maintenance-report
status: assessing
scenario_revision: "0"
predecessors:
  - source-notes.md
  - links.md
  - scenario-brief.md
owner: scenario-maintainer
next_action: maintain
updated_at: "<YYYY-MM-DDTHH:MM:SSZ>"
human_approval:
  required: false
  status: not-required
  approver: ""
  approved_at: ""
  scope: ""
---

# Maintenance Report

## Subject

- Published scenario:
- Trigger:
- Maintainer:

## New evidence

- Vault versions:
- Documentation, issue, PR, or source changes:
- Reported failure or drift:

## Impact assessment

- Classification: `no-change` | `content-update` | `revalidation-required` | `deprecate`
- Affected sections/files:
- User impact:

## Proposed changes

1.

## Validation plan

- Checks to repeat:
- New environments or versions:
- Cleanup:

## Changes made

- None.

## Validation result

- Required: `yes` | `no`
- Report: `validation-report.md` | `not-required`

## Publication decision

- README update required: `yes` | `no`
- Reason:

