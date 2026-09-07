---
schema_version: 1
scenario_id: <scenario-slug>
workflow: create
artifact_type: review-report
status: draft
scenario_revision: "0"
predecessors:
  - source-notes.md
  - links.md
  - scenario-brief.md
  - validation-report.md
owner: vault-scenario-reviewer
next_action: review
updated_at: "<YYYY-MM-DDTHH:MM:SSZ>"
human_approval:
  required: false
  status: not-required
  approver: ""
  approved_at: ""
  scope: ""
---

# Review Report

## Subject

- Scenario:
- Scenario brief: `scenario-brief.md`
- Validation report: `validation-report.md`
- Reviewer:

## Release decision

- Reason:

## Quality rubric

- Scope: `pass` | `needs-work` | `not-applicable`
- Technical accuracy: `pass` | `needs-work` | `not-applicable`
- Reproducibility: `pass` | `needs-work` | `not-applicable`
- Safety: `pass` | `needs-work` | `not-applicable`
- Repository fit: `pass` | `needs-work` | `not-applicable`
- Evidence: `pass` | `needs-work` | `not-applicable`

## Findings

### Blocking

- None.

### Non-blocking

- None.

## Evidence gaps

- None.

## Required changes

1. None.

## Index recommendation

- Include in `README.md`: `yes` | `no`
- Suggested section:
- Suggested title:
- Suggested tags:
- Summary bullets:
- Known Bugs & Regressions action: `none` | `add` | `update` | `remove`

## Human approvals

- [ ] Destructive or shared-infrastructure actions reviewed, if applicable
- [ ] Customer-derived information approved for publication, if applicable
- [ ] Security and version-range claims approved, if applicable

When any approval is required, set the aggregate `human_approval` metadata to `pending` until a human decision is recorded.

