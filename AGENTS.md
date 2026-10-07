# Vault Reproductions Agents.md

## Project Overview

This repository is a support and troubleshooting library for HashiCorp Vault. It contains reproducible runbooks, KBs, and helper scripts that can be used to learn, diagnose, or troubleshoot various Vault issues.

For lab prerequisites and the category map, see [README.md](./README.md). Each top-level topic folder has its own `README.md` scenario index. Confirmed version-specific defects live in [KNOWN_BUGS.md](./KNOWN_BUGS.md).

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
- Use the outline that fits the document type; combine sections when that reads more clearly.
- Include exact error strings when documenting failures so users can search logs quickly.
- State each fact once. Keep background relevant to execution or diagnosis, and show only decisive output lines.
- Omit inapplicable sections and generic conclusions. Preserve the detail needed to reproduce or understand the behavior.

## Evidence and execution

- Cite the documentation, source, or supplied evidence that supports important claims. Distinguish reported observations, results you actually observed, and illustrative expected output.
- Keep tested versions separate from affected/fixed ranges. Do not infer release coverage or a shipped fix from one test or an unmerged change.
- Default to local, disposable resources. Confirm the target and obtain explicit authorization before using shared/non-local infrastructure or taking destructive actions outside the requested scope.
- State the impact and available recovery path beside destructive commands. Scope cleanup to resources created by the scenario.
- Record checks actually performed and relevant blockers. Syntax checks and printed success messages are not proof of runtime behavior.
- Keep raw customer evidence and credentials out of tracked files; retain only sanitized excerpts needed to explain the result.

## Scenario index formatting

- Keep the root `README.md` as the front door: intro, Start Here, prerequisites, category map, and a pointer to Known Bugs. Do not put the full scenario catalog or a directory tree in the root README.
- Keep each top-level topic folder's `README.md` as the scenario index for that domain (`auth/README.md`, `secrets/README.md`, `sys/README.md`, and so on).
- Keep `KNOWN_BUGS.md` as the version matrix for confirmed Vault, provider, or wrapping-library defects. Include the `VAULT-XXXXX` key when the scenario records one.
- In each folder index, keep the legend line for content type terms (`runbook`, `kb`, `repro`, `guide`, `script`).
- For each scenario item, use this structure:
	1. Link line (the scenario title and path, relative to that folder)
	2. Inline backtick tags (for example: ``runbook`` ``sys`` ``seal``)
	3. Collapsible details block:
	   - `<details>`
	   - `<summary>Details</summary>`
	   - Original description bullets
	   - `</details>`
- Preserve the existing section hierarchy inside the folder README and do not flatten categories.
- Keep content changes minimal when reformatting: prefer structural changes for readability, not rewriting scenario meaning.
- When adding new scenarios, follow the same index entry pattern and place them in the correct topic-folder README.
	- As this project grows, it's important to make sure we don't have overlapping content. 

## Scope guardrails

- Keep edits small and logically grouped.
- Do not modify unrelated files.
- Do not rename files or restructure folders unless explicitly requested.
- Do not run `git commit` or `git push`. 
- Do not append "coauthored by: AI" to commits; I'm only using AI to help with editing/formatting, not to generate original content.

## AI tooling layout

- `AGENTS.md` (this file) - authoritative repository rules.
- `.agents/README.md` - skill selection and the author/review workflow.
- `.agents/skills/` - scenario and support skills, with their own templates and conditional references.
- `.opencode/commands/` - OpenCode slash-command adapters.
- `.agents/instructions/internal-tools.md` - optional, gitignored context for local repositories and tools. Read the relevant sections when the task uses those tools; allow for this file to be absent in other checkouts.

## Scenario workflow

Use two skills for new and existing scenarios:

1. `vault-scenario-author`: scope the requested work, create or update the scenario, perform focused checks, and include relevant topic-index and Known Bugs edits in the proposed change.
2. `vault-scenario-reviewer`: review the current files, diff, and evidence; report actionable findings and whether the change is ready.

- Use the request and supplied evidence as the starting point. Ask only for missing information that changes correctness, scope, or execution safety.
- Keep maintenance proportional to the change. Repeat checks affected by edits; do not rebuild a lab for prose-only corrections.
- Review index edits with the scenario. A review decision applies only to the files and evidence examined; revisit affected findings and checks after changes.
- Use existing draft notes and reports as evidence when relevant. New planning contracts, approval metadata, and revision counters are not required.
- Save concise notes under `drafts/<scenario-slug>/` only when needed for a handoff or requested by the user. This directory is gitignored; required reader-facing evidence belongs in the scenario or its references.

OpenCode entry: `/vault-workflow`. For review-only requests, use the reviewer directly.

For documentation answers, source investigations, bug drafts, and unit tests, select the relevant support skill from [`.agents/README.md`](.agents/README.md#support-skills).
