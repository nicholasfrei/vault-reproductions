---
name: vault-scenario-reviewer
description: Reviews Vault scenarios and maintenance changes against repository rules and vault-scenario-author guidance for accuracy, reproducibility, concision, and evidence. Use when asked to "review this runbook", "check this KB", "validate this repro", or "review scenario changes". Returns actionable findings and a readiness decision.
---

# Vault Scenario Reviewer

Evaluate the current scenario and evidence; return the concise review in [assets/template.md](assets/template.md), without a separate narrative recap.

## Quick Start

1. Read the request, current files/diff, and root `AGENTS.md` if not already loaded.
2. Check the content against its reader goal and supporting evidence.
3. Inspect existing check results and perform focused verification where needed.
4. Return a decision, actionable findings, and checks with any limitations.

## When to Use

Use for review-only requests, verification, and review after creation or maintenance, including related index edits.

Do not use to silently rewrite the scenario: send fixes to [vault-scenario-author](../vault-scenario-author/SKILL.md). Use `find-vault-bugs` for a source investigation beyond what the supplied evidence establishes.

Paths beginning `.agents/` and scenario paths are repository-relative; bundled links are relative to this skill.

## Step 1 — Establish the review target

- Read the complete scenario and relevant supporting files, the requested change, and supplied evidence. Inspect the diff when available; distinguish pre-existing problems from changes under review.
- Use prior findings and notes if supplied. Resolve or carry forward actionable findings based on the current files, rather than trusting an earlier readiness label.
- Read the selected type in the author's [outline](../vault-scenario-author/assets/template.md). For script work, also read its [script guidance](../vault-scenario-author/references/scripts.md).
- If local tool context is needed, read the relevant sections of `.agents/instructions/internal-tools.md` when present. Its absence alone does not block review.

## Step 2 — Check quality

- Scope: does this solve the requested reader problem without duplicating an existing scenario or expanding a small fix?
- Accuracy: do commands, policy semantics, versions, and error strings match the cited evidence? Are reported results, observed results, hypotheses, and illustrative output distinguished?
- Reproducibility: are prerequisites, permissions, execution context, and success/failure criteria sufficient? Is a control needed to distinguish the claimed behavior?
- Execution: are targets explicit, sensitive values redacted, risky steps explained, and cleanup/recovery scoped appropriately?
- Concision: does each section add necessary information? Flag repeated explanations, generic background, irrelevant output, and scaffolding that can be removed without losing meaning.
- Repository fit: do path, naming, formatting, and any topic-index/Known Bugs edits follow `AGENTS.md`? Verify changed links and evidence for defect/version claims.

Do not require headings just because a template contains them. State each finding once with its location, consequence, and smallest useful correction.

## Step 3 — Verify and decide

Read [references/verification.md](references/verification.md) and select checks appropriate to the change. Examine the actual evidence behind author check summaries; do not treat an assertion of success as proof or rerun adequate checks without a reason.

- `ready`: no blocking findings, and applicable checks have adequate evidence.
- `needs-changes`: an identified content or script defect can be corrected.
- `blocked`: missing evidence, access, or a user decision prevents a readiness determination.

Use `needs-changes` when concrete fixes are known and list any additional evidence blockers. A static-only review cannot establish an untested runtime claim. Prose-only corrections may be ready after static checks.

## Step 4 — Return the review

Read [assets/template.md](assets/template.md). Return the decision, findings, and checks only; keep routine reviews around 200 words, expanding when needed to include every actionable finding. Separate blocking findings from optional suggestions and report unrun checks plainly.

Save the same review only when requested or needed for a cross-session handoff, using the supplied path or `drafts/<scenario-slug>/review.md`. Identify the reviewed files and evidence; preserve existing notes. A later content change requires revisiting affected findings and checks. Do not edit scenario or index files during review.

## Handling Missing Information

Complete checks supported by available evidence. Ask only for information needed to resolve a concrete blocker, and state what it prevents you from determining. Do not manufacture versions, observations, or a clean review to finish the workflow.

## Example

Input: a new helper ends with `echo "cleanup complete"`; the supplied output contains that message but no teardown or check of remaining resources. Inspect the script and evidence, identify the missing cleanup, and return:

```markdown
## Decision
needs-changes — cleanup is claimed but not implemented.

## Findings
- Blocking — helper script, final step: the message does not remove resources. Add scoped teardown and verify the resources are gone.

## Checks
- Inspected the script and supplied output. Cleanup execution remains unverified.
```

## Anti-Patterns to Avoid

| Anti-pattern | Fix |
| --- | --- |
| Reviewing only the author's summary | Inspect current files and the evidence behind the claims. |
| Treating syntax checks as a successful repro | Require observed behavior for runtime claims. |
| Repeating every passing rubric item | Report the decision, actionable findings, and meaningful checks. |
| Fixing content while declaring it reviewed | Return findings for authoring, then review the resulting change. |
