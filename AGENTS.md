# Vault Reproductions Agents.md

## Project Overview

This repository is a support and troubleshooting library for HashiCorp Vault. It contains reproducible runbooks, KBs, and helper scripts that can be used to learn, diagnose, or troubleshoot various Vault issues.

For the canonical scenario list and lab prerequisites, see [README.md](./README.md). That file is the source of truth for how content is grouped and what baseline tools or clusters are expected, so this document does not duplicate a folder tree.

## Document naming conventions

New Markdown writeups should live under the existing topic directory (for example `auth/jwt/`, `sys/seal/awskms/`, `secrets/kv/`). Use one of these filename suffixes so readers know what kind of document they are opening:

- `*-kb.md` (knowledge base): Post-incident or post-mortem style context, symptoms, root-cause reasoning, architecture notes, and recommendations. May include triage commands or references, but the emphasis is on understanding and searchability (including exact error strings), not a single linear procedure from start to finish.

- `*-runbook.md` (runbook): A repeatable, ordered procedure—prerequisites, steps, validation, and cleanup when applicable. Use when someone should follow the file like a checklist during maintenance, recovery, or a hands-on lab.

- `*-repro.md` (reproduction): A minimal, focused scenario that demonstrates a specific bug, regression, or behavioral quirk. Use when the goal is “do these steps and observe this outcome,” often to confirm a fix or teach edge-case behavior.

- `*-guide.md` (guide): Longer-form material that does not fit the three shapes above—exam preparation, platform or lab setup narratives, or end-to-end integration walkthroughs that blend explanation with multiple phases.

If a document spans types (for example both theory and a long procedure), pick the primary intent for the filename, or split into a KB plus a runbook and cross-link them.

## AI tooling layout

This repo is consumed by multiple AI coding tools. To avoid drift, instructions are stored once and referenced by each tool's adapter:

- `AGENTS.md` (this file) — canonical project rules. Read by opencode, Cursor, modern IBM agents, and any tool that follows the AGENTS.md convention.
- `.ai/instructions/` — task-scoped authoring rules (one source of truth):
    - `create-kb.md` — KB articles (`*-kb.md`).
    - `create-runbook.md` — runbooks (`*-runbook.md`).
    - `create-script.md` — reproduction shell scripts.
- `.ai/skills/` — reusable agent skills (Anthropic Agent Skills format with `name` + `description` frontmatter):
    - `customer-reply/SKILL.md` — drafting Zendesk-ready Vault support replies.
- `.github/copilot-instructions.md` — always-on Copilot context for VS Code; summarizes this file.
- `.github/instructions/*.instructions.md` — Copilot per-file rules with `applyTo` glob; thin mirrors of `.ai/instructions/`.
- `.github/prompts/customer-reply.prompt.md` — Copilot Chat slash prompt that loads the customer-reply skill.
- `.cursor/rules/*.mdc` — Cursor adapters; `project.mdc` is `alwaysApply: true`, others reference `.ai/` files via `@`-includes.
- `.opencode/commands/customer-reply.md` — opencode slash command for the customer-reply skill.
- `.opencode/skills/` — symlink to `.ai/skills/` so opencode auto-discovers them.

When updating authoring rules, edit the file under `.ai/` (or this `AGENTS.md` for project-wide rules). The thin adapter files under `.github/`, `.cursor/`, and `.opencode/` should remain pointers and not accumulate drift.

## Repository intent
- Build reproducible Vault scenarios with instructions and commands.
	- Keep instructions explicit, copy/paste friendly, and easy to validate.
- This repo should be designed to be used by engineers of all levels, and is not for explicit internal use only, so keep instructions clear and actionable for a wide audience.

## Authoring rules
1. Prefer explicit commands over abstractions (no aliases, no hidden helper wrappers).
2. Vault is primarily installed on Linux or Kubernetes, so keep everything relevant to the scenario environment.
3. Keep scripts safe by default (`set -euo pipefail`, clear prereq checks, clear errors).
4. Do not add dependencies unless there is no practical built-in alternative.
5. Never include public IP addresses, hostnames, or sensitive information in scripts, runbooks, examples, or logs.
6. Redact sensitive values using placeholders such as `<hostname>`, `<ip_addr>`, `<email>`, `<token>`.
7. Prefer Vault CLI examples (`vault read|write|list|auth|secrets`) over API calls or UI-only instructions.

## Markdown and output formatting conventions
- Use fenced code blocks with explicit language tags:
	- `bash` or `shell` for commands
	- `text` for command output/logs
	- `json`/`yaml` when exact structured content is shown
- Keep command and output blocks separate (do not mix output into command blocks).
- For mock Vault CLI tabular output, use Vault-like column output (`Key` / `Value`) without `key="value"` formatting.
- Use backticks for literal command names, flags, paths, versions, and error strings.
- Avoid bold text unless truly necessary. Prefer headings, lists, and normal prose for emphasis. Do not bold individual words or phrases throughout a document for decoration; if bold is used at all, keep it rare (for example one short callout, not scattered keywords).
- Follow a rough outline: Overview, Objective, Prerequisites, Steps, Validation, Cleanup, References.
- Include exact error strings when documenting failures so users can search logs quickly.

## README scenario index formatting
- Keep `README.md` as the canonical scenario index and preserve all existing entries unless explicitly asked to remove content.
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