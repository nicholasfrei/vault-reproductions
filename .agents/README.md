# Vault Scenario and Support Skills

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
| [escalation-canvas](skills/escalation-canvas/SKILL.md) | Living escalation record: environment, affected workflow, timestamped investigations, working theories, and regional handoff | invoke the skill |
| [create-implementation-doc](skills/create-implementation-doc/SKILL.md) | Evidence-based engineering handoff with issue context, candidate fixes, implementation steps, and validation | invoke the skill |
| [vault-jira-bug](skills/vault-jira-bug/SKILL.md) | Concise Vault bug titles and descriptions | invoke the skill |
| [vault-unit-tests](skills/vault-unit-tests/SKILL.md) | Go regression-test work using Vault's native `go-test` skill; routes UI work to native `ui` guidance | `/vault-unit-tests` |
| [vault-support-reply](skills/vault-support-reply/SKILL.md) | Evidence-based customer reply drafts for Vault support engineers | invoke the skill |

## CE troubleshooting and fix workflow

Use [`/bug-triage`](../.opencode/commands/bug-triage.md) to follow the [triage and fix workflow](workflows/bug-triage.md), or invoke a specialist directly for a narrow request:

1. Establish documented expectations with `document-reference` and trace implementation with `find-vault-bugs` as needed.
2. Reproduce at the appropriate layer: a focused Go/UI test or a scenario through the author/reviewer workflow.
3. Use `create-implementation-doc` for a requested plan or durable engineering handoff.
4. For a requested fix, follow the owning source repository's implementation guidance and verify with native Go/UI tests.
5. Use `vault-jira-bug` or `vault-support-reply` when the requested outcome includes a ticket or customer update.

Carry source revisions, evidence, actual test outcomes, and unresolved questions between stages. Load only the relevant skills and finish at the requested outcome. `vault-support-reply` replaces the former `customer-reply` skill.

For an ongoing escalation spanning engineers or regions, use `escalation-canvas` to maintain the shared investigation record. Feed established findings into `create-implementation-doc` when a bounded fix plan is needed.
