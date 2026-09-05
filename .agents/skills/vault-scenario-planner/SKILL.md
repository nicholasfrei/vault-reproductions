---
name: vault-scenario-planner
description: Converts a rough Vault support issue, incident, upstream issue, or scenario idea into a bounded scenario brief. Use before authoring a new repro, runbook, KB, guide, or script.
---

# Vault Scenario Planner

Produce the durable contract for scenario authoring. Do not create the final scenario or implementation scripts.

## Inputs

Read:

- Root `AGENTS.md`
- `.agents/shared/contract-metadata.md`
- `.agents/shared/repo-conventions.md`
- `.agents/shared/scenario-schema.md`
- `.agents/shared/safety-rules.md`
- `drafts/<scenario-slug>/source-notes.md`
- `drafts/<scenario-slug>/links.md`, when present
- Existing `validation-report.md`, `review-report.md`, or `maintenance-report.md` when one triggered replanning
- Similar entries in `README.md` and neighboring topic files

## Process

1. Confirm intake artifacts are `ready` and use the same `scenario_id`, `workflow`, and scenario revision.
2. Identify the user-visible behavior and desired outcome.
3. Select one primary type: `repro`, `runbook`, `kb`, `guide`, or `script`.
4. Check for overlap with existing scenarios.
5. Record version, edition, deployment, storage, recent changes, and exact errors when known.
6. Define the smallest procedure that can prove or explain the behavior.
7. Add observable validation, a control case when useful, cleanup, and safety constraints.
8. Mark unavailable facts `unknown`.
9. Ask for input only when an unknown changes scope, safety, or the validity of the proposed scenario.
10. Preserve every triggering report in metadata `predecessors`.
11. Keep revision `"0"` for a new, not-yet-authored scenario. When replanning an existing scenario, retain the current implementation revision; the author or maintainer increments it immediately before changing implementation files.

## Output

Copy `.agents/templates/scenario-brief.md` to:

```text
drafts/<scenario-slug>/scenario-brief.md
```

Fill every section and the common metadata. Set metadata status and next action to:

- `awaiting-approval` and `human-approve` when the brief is complete
- `needs-input` and `collect-input` with focused questions
- `rejected` and `none` when the request duplicates existing content or falls outside repository intent

The planner must not mark its own brief approved. After an explicit human acceptance is recorded, the metadata may change to `ready-for-authoring` with `next_action: author`.

Do not rely on chat-only instructions in the handoff.

