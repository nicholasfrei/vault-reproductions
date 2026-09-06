# Vault Reproductions Agents.md

## Project Overview

This repository is a support and troubleshooting library for HashiCorp Vault. It contains reproducible runbooks, KBs, and helper scripts that can be used to learn, diagnose, or troubleshoot various Vault issues.

For the scenario list and lab prerequisites, see [README.md](./README.md). The README is the source of truth for how content is grouped.

## Document naming conventions

New documents should following the existing schema (for example `auth/jwt/`, `sys/seal/awskms/`, `secrets/kv/`). Use one of these filename suffixes so readers know what kind of document they are opening:

- `*-kb.md` (knowledge base): Post-incident or post-mortem style context, symptoms, root-cause reasoning, architecture notes, and recommendations. May include triage commands or references, but the emphasis is on understanding and searchability (including exact error strings), not a single linear procedure from start to finish.
- `*-runbook.md` (runbook): A repeatable, ordered procedure—prerequisites, steps, validation, and cleanup when applicable. Use when someone should follow the file like a checklist during maintenance, recovery, or a hands-on lab.
- `*-repro.md` (reproduction): A minimal, focused scenario that demonstrates a specific bug, regression, or behavioral quirk. Use when the goal is “do these steps and observe this outcome,” often to confirm a fix or teach edge-case behavior.
- `*-guide.md` (guide): Longer-form material that does not fit the three shapes above—exam preparation, platform or lab setup narratives, or end-to-end integration walkthroughs that blend explanation with multiple phases.

## Repository intent

This repository is designed to be a living library of support and troubleshooting content for HashiCorp Vault. It is not for explicit internal use only, and should be designed to be used by engineers of all levels.

## Authoring rules

1. Prefer explicit commands over abstractions (no aliases or hidden helper wrappers).
2. Keep scripts safe by default (`set -euo pipefail`, clear prereq checks, clear errors).
3. Do not add dependencies unless there is no practical built-in alternative.
4. Never include public IP addresses, hostnames, or sensitive information in scripts, runbooks, examples, or logs.
5. Redact sensitive values using placeholders such as `<hostname>`, `<ip_addr>`, `<email>`, `<token>`.
6. Prefer Vault CLI examples (`vault read|write|list|auth|secrets`) over API calls or UI-only instructions.

## Formatting conventions

- Use fenced code blocks with explicit language tags:
	- `bash` or `shell` for commands
	- `text` for command output/logs
	- `json`/`yaml` when exact structured content is shown
- Keep command and output blocks separate (do not mix output into command blocks).
- Use backticks for literal command names, flags, paths, versions, and error strings.
- Avoid bold text. Do not bold individual words or phrases.
- Prefer headings, lists, and normal prose for emphasis.
- Follow a rough outline: Overview/Objective, Prerequisites, Steps, References.
- Include exact error strings when documenting failures so users can search logs quickly.

## README scenario index formatting

- Keep `README.md` as the scenario index
- In `## Scenario Index`, keep the legend line for content type terms (`runbook`, `kb`, `repro`, `guide`).
- For each scenario item, use this structure:
	1. Link line (the scenario title and path)
	2. Inline backtick tags (for example: ``runbook`` ``sys`` ``seal``)
	3. Collapsible details block:
	   - `<details>`
	   - `<summary>Details</summary>`
	   - Original description bullets
	   - `</details>`
- Preserve the existing section hierarchy (for example `###`, `####`, `#####`) and do not flatten categories.
- Keep content changes minimal when reformatting: prefer structural changes for readability, not rewriting scenario meaning.
- When adding new scenarios, follow the same index entry pattern and place them in the correct existing section.
	- As this project grows, it's important to make sure we don't have overlapping content. 

## Scope guardrails

- Keep edits small and logically grouped.
- Do not modify unrelated files.
- Do not rename files or restructure folders unless explicitly requested.
- Do not run `git commit` or `git push`. 
- Do not append "coauthored by: AI" to commits; I'm only using AI to help with editing/formatting, not to generate original content.

## AI tooling layout

- `AGENTS.md` (this file) - authoritative repository rules.
- `.agents/README.md` - AI workflow navigation hub (trees, skill matrix, layout).
- `.agents/shared/` - contract metadata, repository conventions, scenario schema, safety rules, and quality rubric.
- `.agents/workflows/` - stage definitions for create, review, maintain, release-index, and support investigation.
- `.agents/templates/` - standardized intake, brief, validation, review, and maintenance contracts.
- `.agents/skills/` - specialist scenario and support task instructions (source of truth for skills).
- `.opencode/commands/` - OpenCode slash-command adapters.
- `.agents/instructions/internal-tools.md` - Vault tooling selection guidance.

## AI workflow map

Read [`.agents/README.md`](.agents/README.md) first when choosing a path. Use the matching workflow file; do not invent a parallel process.

### Scenario create

1. Intake: `drafts/<scenario-slug>/source-notes.md` + `links.md`
2. Plan: `vault-scenario-planner` → `scenario-brief.md` → human approval
3. Author: `vault-scenario-author` (brief must be `ready-for-authoring`)
4. Validate: `vault-scenario-validator` → `validation-report.md`
5. Review: `vault-scenario-reviewer` → `review-report.md`
6. Index: `scenario-index-curator` updates `README.md` only when review is `ready` and `next_action` is `index`

Workflow docs: `.agents/workflows/scenario-authoring.md` → `scenario-review.md` → `release-index.md`

OpenCode entry: `/vault-workflow`

### Scenario maintain

1. Intake with `workflow: maintain`
2. Assess: `scenario-maintainer` → `maintenance-report.md`
3. Bounded update, replan, validate-only, deprecate, or close per report status
4. Revalidate and review when published content changes
5. Re-index when discovery metadata or Known Bugs status changes

Workflow doc: `.agents/workflows/scenario-maintenance.md`

OpenCode entry: `/vault-workflow`

### Support and investigation (no scenario required)

| Intent | Skill | OpenCode |
| --- | --- | --- |
| Docs / evidence diagnosis | `document-reference` | `/document-reference` |
| Source bug / fix / version mapping | `find-vault-bugs` | `/find-vault-bugs` |
| Vault Enterprise unit tests | `vault-unit-tests` | `/vault-unit-tests` |
| Bug triage orchestrator (WIP) | (to be defined) | `/bug-triage` |

Full trees and handoffs into create/maintain: `.agents/workflows/support-workflows.md`

## AI workflow handoffs

- Store multi-stage work under `drafts/<scenario-slug>/`.
- Agents communicate through the Markdown contracts, not prior chat context.
- Preserve sanitized source material in `source-notes.md` and references in `links.md`.
- Apply `.agents/shared/contract-metadata.md` to every contract and read every declared predecessor before continuing.
- Keep one stable `scenario_id`; increment `scenario_revision` whenever scenario or supporting files change.
- Agents must not approve their own artifacts or continue while required human approval is pending.
- Do not author before the scenario brief is `ready-for-authoring`.
- Do not update the README index before the review report is `ready` for the current scenario revision.
- Keep non-contract draft artifacts ignored; the Markdown contracts remain trackable for provenance.