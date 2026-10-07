# Vault Scenario Skills

Use two skills to create, maintain, and review Vault troubleshooting content. [AGENTS.md](../AGENTS.md) defines repository-wide rules; each skill owns its procedure and supporting resources.

## Author and review

| Intent | Skill | Responsibility |
| --- | --- | --- |
| Create or update a KB, runbook, repro, guide, or script | [vault-scenario-author](skills/vault-scenario-author/SKILL.md) | Scope, write, check, and update related index entries |
| Review content or verify a scenario | [vault-scenario-reviewer](skills/vault-scenario-reviewer/SKILL.md) | Assess the current change and evidence; return findings and a readiness decision |

Start from the request, source material, and existing files. The same authoring path handles maintenance: compare the new evidence, make the smallest useful change, and check what changed. When evidence supports no change, say so.

The reviewer examines scenario and index edits together. Send actionable findings back to the author, then recheck the affected content. Review-only requests go straight to the reviewer.

OpenCode: [`/vault-workflow`](../.opencode/commands/vault-workflow.md) selects authoring followed by review, or review alone when requested.

## Context and output

- Keep scenarios concise but reproducible. Type-specific outlines live in the author's [template](skills/vault-scenario-author/assets/template.md); load script guidance only for script work.
- Keep review output to a decision, findings, and checks. Save a report only when requested or needed for a handoff.
- Use supplied notes and existing draft reports as evidence. The skills do not require intake forms, approval records, or revision counters.
- For a handoff across sessions, optionally save the scope, source references, checks, and remaining work under `drafts/<scenario-slug>/`. Drafts are gitignored; include evidence readers need in the published content or references.
- Local tool mappings remain in `.agents/instructions/internal-tools.md`. Read them when working with tools such as ENOS or CROKS. The file is gitignored and optional in other checkouts.

## Support skills

Support investigations can feed evidence directly into authoring without a separate intake stage.

| Skill | Purpose | OpenCode command |
| --- | --- | --- |
| [document-reference](skills/document-reference/SKILL.md) | Official documentation and evidence-based answers | `/document-reference` |
| [find-vault-bugs](skills/find-vault-bugs/SKILL.md) | Source investigation, fixes, and version mapping | `/find-vault-bugs` |
| [create-implementation-doc](skills/create-implementation-doc/SKILL.md) | Bounded engineering handoff with customer impact, code paths, and a minimal implementation plan | none |
| [vault-jira-bug](skills/vault-jira-bug/SKILL.md) | Concise Vault bug titles and descriptions | invoke the skill |
| [vault-unit-tests](skills/vault-unit-tests/SKILL.md) | Vault Enterprise unit test work | `/vault-unit-tests` |
| [customer-reply](skills/customer-reply/SKILL.md) | Customer-facing support reply template | `/customer-reply` |

[`/bug-triage`](../.opencode/commands/bug-triage.md) remains a [work-in-progress placeholder](workflows/bug-triage.md).
