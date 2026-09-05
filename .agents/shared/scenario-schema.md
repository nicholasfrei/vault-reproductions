# Scenario Schema

Choose one primary scenario type before authoring.

## `repro`

Use for a focused bug, regression, or behavioral quirk.

Required content:

- Objective and affected/tested versions
- Minimal prerequisites
- Known-good or control case when practical
- Steps that expose the behavior
- Expected and observed results
- Validation, workaround or fix comparison, and cleanup

## `runbook`

Use for an ordered operational or lab procedure.

Required content:

- Objective and applicability
- Preconditions, permissions, and risk
- Ordered steps with checkpoints
- Expected output or success criteria
- Rollback or recovery guidance when relevant
- Final validation and cleanup

## `kb`

Use for symptom-led diagnosis, incident learning, or root-cause explanation.

Required content:

- Symptoms and exact errors
- Environment and affected versions
- Cause or evidence-backed hypothesis
- Diagnostic path
- Resolution, mitigation, or recommendations
- Caveats and references

## `guide`

Use for a broader integration, learning path, or multi-phase walkthrough.

Required content:

- Audience, objective, and scope
- Architecture or conceptual context
- Phased instructions
- Validation at meaningful boundaries
- Cleanup and references

## `script`

Use only when the executable is the primary deliverable.

Required qualities:

- `set -euo pipefail` for Bash
- Prerequisite and input checks
- Safe defaults and clear errors
- No embedded credentials or public infrastructure identifiers
- Usage, expected result, and cleanup documented nearby

If content spans types, select the primary user intent or split it into linked scenarios.

