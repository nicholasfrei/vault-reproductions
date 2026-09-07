---
schema_version: 1
scenario_id: <scenario-slug>
workflow: create
artifact_type: validation-report
status: not-run
scenario_revision: "0"
predecessors:
  - scenario-brief.md
owner: vault-scenario-validator
next_action: validate
updated_at: "<YYYY-MM-DDTHH:MM:SSZ>"
human_approval:
  required: false
  status: not-required
  approver: ""
  approved_at: ""
  scope: ""
---

# Validation Report

## Subject

- Scenario:
- Scenario brief: `scenario-brief.md`
- Validator:
- Environment:
- Vault version/edition:

## Validation summary

- Summary:

## Checks performed

### Check 1

- Purpose:
- Command:

```bash
# command
```

- Exit status:
- Observed output:

```text
output
```

- Result: `pass` | `fail`

## Criteria results

- [ ] Initial behavior observed
- [ ] Control/workaround/fixed behavior observed, if applicable
- [ ] Expected outputs match the scenario
- [ ] Cleanup verified
- [ ] Sensitive output redacted

## Deviations from the brief

- None.

## Unrun checks and blockers

- None.

## Next-action reason

<!-- Explain the metadata `next_action` and name any blocking evidence. -->

