---
name: document-reference
description: Answer HashiCorp product questions with a structured, cited documentation report, primarily for Vault and cross-product integrations. Use when asked to "find the official docs", "explain this documented behavior", "check whether this configuration is supported", or "answer this using HashiCorp documentation". Supports Terraform, Consul, Nomad, Boundary, Packer, and Waypoint documentation when relevant.
---

# Document Reference

Produce a concise documentation-based answer to a HashiCorp product question, with citations and explicit limits on what the evidence establishes.

## Quick Start

1. Identify the product, question, and evidence already supplied.
2. Ask only for missing information that materially affects the answer.
3. Search relevant local documentation first; use official web sources when local evidence is unavailable or insufficient.
4. Check source applicability and separate documented behavior from observations and inference.
5. Return the Markdown report defined below, citing the sources actually consulted.

## When to Use

Use this skill when:

- The user needs official documentation for a product feature, API, configuration, or error.
- The user wants observed behavior compared with documented behavior.
- The question spans HashiCorp products or the HashiCorp Terraform Vault provider.

Do not use this skill as the primary workflow when:

- The task requires Vault source-code analysis, bug confirmation, fix commits, or affected/fixed release mapping; use `find-vault-bugs`. This skill can supply supporting documentation.
- The user wants a new reproduction, runbook, KB, or guide; use `vault-scenario-planner` to enter the scenario workflow.
- The user wants architecture design or implementation work rather than a documentation answer.

## Step 1 — Establish the Question and Context

Read the supplied evidence before asking questions. Capture only context relevant to the answer:

- Product name, version, and edition; include provider or plugin versions for integrations.
- Exact error, API path, feature, or configuration in question, with sensitive values redacted.
- Relevant deployment details, such as Vault storage backend, HA, replication, or performance standby use.
- Recent changes and reproducibility when diagnosing a symptom.

Use existing version output when supplied (`vault version` or `vault status` for Vault). Do not query a live deployment just to fill report fields. Follow Handling Missing Information below for gaps.

## Step 2 — Locate Authoritative Evidence

Use locally cloned documentation in `~/repos/` before going to the web. If available, read the relevant repository mappings in `.agents/instructions/internal-tools.md`, relative to the project root. This file is machine-local and may be absent in another checkout.

- Prefer `~/repos/web-unified-docs` for official documentation and changelog content when that clone exists.
- Search the relevant product directory for the exact error, endpoint, configuration key, or feature; read the matching section and its prerequisites.
- Record the file path and available version/ref context. Do not treat a local checkout as proof of what is currently published or supported in every release.
- If the local guidance or docs are missing, use a supplied repository path or proceed to official web sources. Do not require internal repositories to answer the question.

### Web Research Policy

When local evidence is unavailable or insufficient, use the available web-fetch tool to read the relevant official pages. If search is available, use it to locate those pages; read the pages before citing their claims.

Allowed domains:

- `developer.hashicorp.com` — primary docs, API docs, tutorials, changelogs
- `support.hashicorp.com` — KB articles (need authentication to view)
- `registry.terraform.io/providers/hashicorp/` — official HashiCorp provider documentation
- `github.com/hashicorp/vault` (and all github.com/hashicorp/* repos) — issues, changelog, source — only to confirm a known bug or behavior, never as the sole source for a fix

Do not cite public blogs, Stack Overflow, Reddit, Medium, or third-party sites. If the fetch tool reports a redirect, check that the destination remains within the allowed sources before following it. If fetching is unavailable or fails, use verified local evidence or user-provided excerpts, state the limitation, and request the relevant excerpt if needed. Do not imply an inaccessible page was checked.

### Useful Starting URLs

Open only the pages relevant to the question.

Vault docs:

- Vault docs: https://developer.hashicorp.com/vault/docs
- Vault API: https://developer.hashicorp.com/vault/api-docs
- Vault troubleshooting: https://developer.hashicorp.com/vault/tutorials/monitoring/troubleshooting-vault
- Vault changelog: https://github.com/hashicorp/vault/blob/main/CHANGELOG.md

Other product docs:

- Terraform Vault provider: https://registry.terraform.io/providers/hashicorp/vault/latest/docs
- Terraform docs: https://developer.hashicorp.com/terraform/docs
- Boundary docs: https://developer.hashicorp.com/boundary/docs
- Nomad docs: https://developer.hashicorp.com/nomad/docs
- Consul docs: https://developer.hashicorp.com/consul/docs
- Support KB: https://support.hashicorp.com/hc/en-us

## Step 3 — Verify and Synthesize

1. Check whether each source applies to the product version, edition, provider, and deployment in question. Prefer version-matched documentation when available; identify when only current documentation was consulted.
2. Separate user-reported observations, documented behavior, and your inference. A documented default does not establish the user's configuration.
3. Support each material conclusion with a citation to the relevant section. Prefer public documentation URLs when verified; otherwise cite the local path and available version/ref, or identify the supplied excerpt. Do not fabricate public URLs from local paths.
4. If sources conflict or do not establish the answer, describe the discrepancy and what remains unknown. Route source-level bug or release questions to `find-vault-bugs` rather than asserting a root cause or fix.

## Step 4 — Produce the Report

Return one Markdown report in the response. Save it to a file only when requested. Keep the headings below; omit irrelevant evidence bullets and add product-specific ones only when needed. Use `unknown` for missing relevant facts and `none reported` only to describe what the user has reported.

```markdown
## Question
<one or two sentences paraphrasing the original question>

## Evidence on hand
- Product(s), version(s), edition(s): <values or "unknown">
- Relevant deployment/configuration: <values or "unknown">
- Reported symptom or exact error: <sanitized observation or string>
- Recent changes: <list or "none reported">
- Reproducibility: <value or "unknown">

## Answer
<direct answer, supporting documentation citations, and applicability to the supplied evidence>
<any unresolved facts, source limitations, or targeted follow-up needed>

## References
- <consulted source title and URL, local path with available version/ref, or supplied excerpt identifier>
```

Before returning the report, check that conclusions are supported, assumptions are visible, citations identify consulted sources, and sensitive values are redacted.

## Handling Missing Information

- Proceed with a general documentation answer when missing deployment details do not affect it. Do not turn a simple lookup into an intake questionnaire.
- Ask a targeted question when a missing version, edition, configuration, or symptom changes the conclusion. Continue any independent research while awaiting the answer.
- If the answer remains conditional, explain the condition and mark the relevant facts as `unknown`. Do not assume Raft or any other backend, version, edition, or configuration.
- If no authoritative evidence is accessible, state that the answer is unverified and request a relevant documentation excerpt or repository path. Do not fill gaps from memory and present them as researched findings.

## Example

User request: "What status code does Vault's `/sys/health` return by default when Vault is sealed?"

Research: Read the official health API documentation. Confirm the default sealed status code and the `sealedcode` override. A deployment version is unnecessary for this general lookup; identify the source as current documentation and do not infer a live cluster's state.

Expected report:

```markdown
## Question
What HTTP status code does Vault's `/sys/health` return by default when sealed?

## Evidence on hand
- Product: Vault; deployment version and edition unknown.
- The question concerns the documented default, not an observed cluster response.

## Answer
The current [health API documentation](https://developer.hashicorp.com/vault/api-docs/system/health#read-health-information) lists `503` as the default status code when Vault is sealed. The `sealedcode` parameter can override this code, so a customized request may return a different value. This answers the default-behavior question; no cluster state was checked.

## References
- [Vault health API — Read health information](https://developer.hashicorp.com/vault/api-docs/system/health#read-health-information)
```

## Anti-Patterns to Avoid

| Anti-pattern | Symptom | Fix |
| --- | --- | --- |
| Treating defaults as observations | Reporting Raft or a documented default as the user's configuration | Mark missing facts as `unknown`; distinguish defaults from supplied evidence |
| Over-collecting context | Blocking a simple documentation lookup on deployment details | Ask only for facts that change the answer |
| Ignoring source applicability | Applying current docs or a local branch to an unverified release | Check version/edition scope and state limitations |
| Unsupported conclusions or citations | Declaring a fix from an issue alone or citing an unread page | Cite consulted evidence; route bug/fix investigation to `find-vault-bugs` |
| Environment-dependent dead end | Stopping because local guidance or internal repos are missing | Fall back to official web sources or supplied excerpts |
| Vault-only reporting | Asking for Raft details on a Terraform or Boundary question | Include only relevant product and deployment fields |

## Scope and Constraints

- Reference only; research documentation and supplied evidence rather than changing or testing a live deployment.
- No architectural design suggestions. If the root cause is structural, name it and point to relevant docs.
- Never invent a product version, error string, configuration value, or research result.
- Never include public IPs, hostnames, customer names, tokens, or other sensitive values. Use placeholders such as `<hostname>`, `<token>`, `<namespace>`.
- Prefer Vault CLI examples over API calls unless the question specifically concerns the API.
- Use fenced code blocks with explicit language tags (`bash`, `hcl`, `json`, `text` for log output).
