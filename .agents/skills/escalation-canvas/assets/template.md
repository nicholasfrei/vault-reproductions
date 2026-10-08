---
title: Escalation canvas template
doc_type: escalation_canvas_template
---

# Canvas Template

Use the body below for a new canvas. The metadata and these instructions are not part of the output. For updates, preserve an existing useful structure and stable evidence/theory labels. Keep the core topics, but omit irrelevant subfields, remove editorial placeholders, and state material missing facts concisely. Use as many investigation/theory entries as the evidence requires, not a fixed number.

```markdown
# <Escalation: concise symptom or operation>

## Current status

- As of: <actual known timestamp with timezone, or update time not provided>; latest evidence: <time/source incorporated>
- Impact and operational state: <reported or verified impact; distinguish recovery from investigation status>
- Current focus: <leading question or evidenced finding, with source; do not imply confirmed root cause>
- Tracking: <relevant case/issue/change references, sanitized for the destination>

## Environment

- Product/build: <reported version, edition, custom build provenance; material unknowns>
- Affected environment: <production or reproduction; relevant topology and node roles>
- Relevant configuration/integrations: <storage, seal, plugin, or dependency details actually supplied>
- Scale: <value, unit, scope, source, and time if known; preserve unresolved conflicting reports>
- Reproduction differences: <known differences from the affected environment or limits on equivalence>

## Affected workflow and observed behavior

<Who or what performs the operation and the relevant prerequisites, if known.>

1. <Supported initiating action>
2. <Supported next action; omit if unknown>

- Expected: <intended outcome and its basis, or expectation requiring confirmation>
- Observed: <reported or reviewed result, incident timestamps/timezone, and source>
- Unresolved sequence: <missing trigger, ordering, or reproducibility facts that affect interpretation; omit when resolved>

## Investigation and evidence

### I1 — <Check, artifact review, or attempted mitigation>

- Action/review status: <proposed, in progress, completed, or blocked; received/partially reviewed/reviewed for artifacts>
- Source and coverage: <artifact label or reference, environment/node, covered time window/timezone; distinguish collection time when known>
- Reviewed/attempted: <time/timezone and owner if known; identify supplied findings versus work performed here>
- Scope and result: <what was actually examined or changed, decisive result, source pointer, and limitations>

## Working theories

### H1 — <Specific testable explanation>

- Status: <unassessed, under investigation, supported, weakened, or ruled out>
- Supports: <evidence references and what they establish, or no supporting evidence yet>
- Contrary evidence / gaps: <references, unknowns, and limits on applicability>
- Next check: <discriminating check and how possible outcomes affect this theory>
- Status change: <time/source and reason if updating an existing theory; omit for a new theory>

## Next actions and regional handoff

1. <Next action and related theory/gap> — <status>; owner: <known owner/region or unassigned>; blocker/checkpoint: <only if supplied or consequential>
2. <Next necessary action, with the same compact fields; omit if unnecessary>

- Next meeting/checkpoint: <agreed date/time/timezone and objective; distinguish planned work from completed actions; omit if none is supplied>
```
