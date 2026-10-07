---
name: vault-scenario-author
description: Creates and updates concise Vault KBs, runbooks, reproductions, guides, and supporting scripts from supplied evidence. Use when asked to "write a KB", "create a runbook", "build a repro", "update this scenario", or "add a helper script". Includes focused verification and related index edits.
---

# Vault Scenario Author

Turn the user's evidence and requested outcome into the smallest useful scenario or maintenance change.

## Quick Start

1. Read the request, relevant source material, and root `AGENTS.md` if not already loaded.
2. Locate existing content and select the document type and path.
3. Read the matching outline in [assets/template.md](assets/template.md), then write or update the scenario.
4. Check the change, update related indexes, and return a short handoff to `vault-scenario-reviewer`.

## When to Use

Use for new scenarios, maintenance, review fixes, and companion scripts.

Do not use for review-only requests: use [vault-scenario-reviewer](../vault-scenario-reviewer/SKILL.md). For a documentation answer or source investigation without a requested artifact, use `document-reference` or `find-vault-bugs`.

Paths beginning `.agents/` and scenario paths are relative to the repository root; bundled links are relative to this skill.

## Step 1 — Establish scope

- Read the supplied evidence and existing scenario before asking questions. Use prior notes or review findings when relevant; no planning contract is required.
- Search the topic-folder `README.md`, relevant neighboring files, and `KNOWN_BUGS.md` for overlap. Prefer a bounded update when existing content already covers the goal.
- Choose one primary type and the narrowest existing topic directory. Inspect one relevant neighbor for command and placement conventions; read more only to resolve a specific uncertainty.
- For maintenance, identify which claims, commands, or versions changed. Make no edit when the evidence supports no change. Confirm a material scope expansion with the user.
- If local tooling matters, read the relevant sections of `.agents/instructions/internal-tools.md` when available. Use supplied paths or documented alternatives when it is absent.

## Step 2 — Write the scenario

Read only the selected type in [assets/template.md](assets/template.md). For shell scripts, also read [references/scripts.md](references/scripts.md).

- Lead with the behavior and operator impact or intended outcome. Include environment and version details only when they affect applicability.
- For KBs, connect symptoms → evidence → reasoning → resolution. Label hypotheses and distinguish a workaround from a confirmed fix.
- For procedures, give explicit prerequisites, ordered commands, and observable results at meaningful checkpoints. Name the terminal, cluster, namespace, or working directory when context could be confused.
- Apply the evidence and execution rules in `AGENTS.md`. Attribute supplied results, label illustrative output, and cite the sources actually used, including a relevant issue key when available.
- Treat the outline as a content guide. Combine overlapping sections, explain each fact once, and omit generic background, inapplicable sections, and repetitive summaries.
- Keep required commands and decisive error/output lines. Add explanation only when it helps execution or interpretation; do not preface every self-explanatory command with a sentence.
- Save at the requested or selected scenario path. Add supporting files only when needed; preserve unrelated content during updates.

## Step 3 — Check and finish

- Use [verification guidance](../vault-scenario-reviewer/references/verification.md) to select checks proportional to the change. Record commands, meaningful results, and blockers; do not claim runtime validation from static checks.
- Update the matching topic-folder `README.md` for new scenarios or changed discovery information using `AGENTS.md` formatting. Update `KNOWN_BUGS.md` only for confirmed defects and evidence-backed version/fix changes. Include these edits in review.
- Check changed relative links, inspect the scoped diff, and run `git diff --check`. Keep deprecation or removal within the user's requested scope and repair affected links.
- Return at most three short bullets: changed paths and purpose, checks/results or blockers, and review status/next step. Do not repeat the document in chat.
- For a cross-session handoff, save concise scope, references, check evidence, and remaining work in `drafts/<scenario-slug>/notes.md` only when needed. Preserve existing notes rather than overwriting them.

## Handling Missing Information

Ask a focused question only when a missing fact changes correctness, scope, or execution safety. Label unresolved relevant facts as unknown; omit irrelevant fields. If the evidence contradicts the requested scenario, explain the conflict before expanding the work.

## Example

Request: "Shorten this runbook; leave the tested commands intact."

Read the runbook and request, use the runbook outline, merge duplicate overview/objective text, and remove repeated success descriptions. Check the diff and links; a prose-only edit needs no lab rerun. Leave index wording alone if discovery information still matches.

Illustrative final response:

```text
- Updated the runbook: combined repeated context and kept commands/checkpoints intact.
- Diff and relative-link checks passed; runtime behavior was unchanged and not rerun.
- Ready for scenario review.
```

## Anti-Patterns to Avoid

| Anti-pattern | Fix |
| --- | --- |
| A small repro grows into a deployment guide | Keep only prerequisites and steps needed to expose the behavior. |
| Every template heading is filled | Omit irrelevant sections and combine repeated facts. |
| Nearby content is treated as authoritative | Reuse style, but verify technical claims against evidence. |
| A success message stands in for a check | Inspect actual state or output and report what was observed. |
