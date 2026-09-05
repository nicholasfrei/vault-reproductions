---
name: vault-scenario-author
description: Creates or updates a Vault scenario from an approved scenario brief and repository conventions. Use after planning to author a repro, runbook, KB, guide, script, or supporting files.
---

# Vault Scenario Author

Implement only the scenario defined by an approved brief.

## Required inputs

Read:

- Root `AGENTS.md`
- `.agents/shared/contract-metadata.md`
- `.agents/shared/repo-conventions.md`
- `.agents/shared/scenario-schema.md`
- `.agents/shared/safety-rules.md`
- `drafts/<scenario-slug>/scenario-brief.md`
- `drafts/<scenario-slug>/validation-report.md` when resuming after failed or partial validation
- `drafts/<scenario-slug>/review-report.md` when resuming after review findings
- Three to five relevant neighboring scenarios when available
- Source material listed by the brief

Stop unless the brief metadata is `ready-for-authoring`, its human approval is `approved`, and required predecessor metadata is consistent.

## Process

1. Confirm the proposed path and type match repository conventions.
2. When remediating, read the triggering report and address every required change explicitly.
3. Reuse the nearest scenario's structure and command style.
4. Write explicit prerequisites, ordered commands, expected output, validation, and cleanup required by the selected schema.
5. Distinguish observed results from illustrative expected output.
6. Keep versions, errors, and upstream status aligned with cited evidence.
7. Use safe placeholders and local/disposable defaults.
8. Keep supporting scripts defensive and dependency-light.
9. Set the first implementation revision to `"1"`; increment the brief revision before every subsequent scenario or supporting-file change. In a maintenance workflow, copy the new revision into `maintenance-report.md`.
10. If implementation disproves the brief or requires broader scope, stop and return the triggering evidence to the planner.

## Output

- Create or update the scenario at the path in `scenario-brief.md`.
- Add only supporting files required by the brief.
- Do not update `README.md`.
- Do not claim validation; the validator records that independently.

The scenario files, `scenario-brief.md`, and any remediation report are the validator handoff. Their scenario identity and revision must match.

