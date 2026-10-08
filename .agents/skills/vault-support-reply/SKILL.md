---
name: vault-support-reply
description: Draft concise, evidence-based customer-facing responses for HashiCorp Vault support engineers. Use when asked to "draft a customer reply", "write a support acknowledgement", "request Vault logs", "follow up with the customer", "write a bug-status update", or "draft a case closure". Covers technical next steps and support correspondence using supplied evidence; optional communication alongside troubleshooting and fix work.
---

# Vault Support Reply

Turn supplied case context into a copyable customer-facing reply with a clear status and next step.

## Quick Start

1. Read the user's request, case excerpts, and any supplied investigation or documentation findings.
2. Identify the reply's purpose and the facts that support it; separate reported symptoms from confirmed findings.
3. Read the relevant pattern in [assets/template.md](assets/template.md). Adapt it rather than copying unsupported claims.
4. Draft the shortest useful response, retaining necessary technical steps and targeted questions.
5. Check claims, commands, redaction, and fence formatting; return only the copyable reply body.

## When to Use

Use this skill when:
- Drafting or revising customer-facing Vault break-fix correspondence.
- Acknowledging an issue, requesting evidence, following up, arranging a troubleshooting session, communicating established findings, or closing a case.
- Translating an existing investigation into a customer update at the user's request.

Do not use this skill when:
- The request is only to diagnose behavior, locate a fix, or determine affected versions; use `find-vault-bugs`.
- The request is only for official documentation or a supported-configuration answer; use `document-reference`.
- The request is for an internal implementation plan, bug draft, or unit tests; use `create-implementation-doc`, `vault-jira-bug`, or `vault-unit-tests` as appropriate.
- The request is to design an architecture or write a scenario. Keep any requested customer response focused on the case; use the relevant documentation or scenario skill for the substantive work.

This is an optional communication step. Do not add a customer reply to every investigation or fix workflow. Drafting does not authorize sending a message, updating a ticket, or changing a Vault environment.

## Step 1 — Establish the Supported Message

Read the context already supplied before requesting anything else. Identify:
- The requested reply type, symptom or exact error, and what the customer needs next.
- Confirmed environment details and findings relevant to that next step.
- Actions actually completed, actions merely proposed, and unresolved questions.

Attribute observations accurately: use “You reported…” for a customer report and “The provided logs show…” only when those logs support the statement. Do not turn a suspected cause into a confirmed defect.

Use only evidenced details. Do not assume Integrated Storage (Raft), edition, version, namespace, auth method, deployment platform, customer identity, or support engineer identity. Preserve relevant exact errors while redacting credentials, hostnames, addresses, and personal information with placeholders such as `<hostname>`, `<ip_addr>`, `<email>`, and `<token>`.

Confirm that the evidence supports any claim about a filed bug, reproduction, escalation, engineering ownership, workaround, resolution, affected version range, or released fix. A requested “bug-filed update” does not itself prove that a bug was filed. A patch or passing test does not establish a shipped fix. Do not invent completed actions, commitments, fix dates, release dates, or ETAs; omit unsupported status and timing claims.

## Step 2 — Select the Next Step and Draft

Read the matching pattern in [assets/template.md](assets/template.md) before drafting. Read [references/examples.md](references/examples.md) when handling sparse context, an unconfirmed bug, command formatting, or closure wording.

1. Lead with the supported status or a brief acknowledgement. Omit a named greeting when no name is supplied.
2. Give the next action, a focused question, or a concise explanation of the established finding. Ask only for information needed for this step, and do not request evidence already provided.
3. Use short paragraphs and lists for multiple questions or ordered technical steps. Keep necessary prerequisites, validation, and caveats even when this takes more than two paragraphs. Explain why only when it helps the customer act.
4. Include a specific, verified customer-accessible documentation or public issue link when it supports the advice. Use supplied sources; if a material technical claim still needs research, use the relevant investigation or documentation skill when in scope. Otherwise qualify or omit it and request the missing evidence. Do not substitute a generic docs homepage for evidence or expose internal Jira links and investigation notes.

For technical instructions:
- Prefer explicit Vault CLI commands over API or UI instructions. Use the known version, namespace, mount path, and backend; ask before giving a backend-specific remediation when these are unknown.
- For KV v2, distinguish CLI secret paths from API and policy paths, including the relevant `data/` and `metadata/` operations. Check the actual operation and policy before suggesting a permissions change.
- Use `bash` or `shell` fences for commands, `text` for output/logs, and the matching language such as `hcl`, `json`, or `yaml` for configuration. Keep command and output blocks separate. Do not present expected output as observed output.
- Mark values the customer must substitute with clear placeholders. Do not include real credentials, unseal/recovery keys, or secret values. Request only the relevant redacted configuration or bounded log window, with timestamp/timezone when correlation matters.
- For disruptive or destructive remediation, include the impact and evidence-supported recovery path beside the steps. If target, prerequisites, or recovery are unclear, draft a targeted clarification instead of inventing an executable fix. Do not execute commands as part of drafting.

## Step 3 — Check and Deliver the Reply

Before returning the reply:
- Check each factual claim against the supplied evidence and any sources actually consulted.
- Remove stock promises to investigate, reproduce, escalate, follow up, close, reopen, or send a survey unless the user supplied that action or commitment. Do not imply a ticket status changed just because a closure was requested.
- Resolve template placeholders from evidence or remove the optional sentence. Keep only deliberate redaction or command-substitution placeholders; do not leave editorial prompts for the customer.
- Keep the tone direct, professional, and helpful. Remove blame, excessive apologies, repeated thanks, boilerplate offers, and unnecessary background.
- Check that the entire body is copyable and its inner command fences do not close the outer block.

### Output Contract

Return only the customer reply inside one outer fenced block labeled `text`, with no preface or analysis. Use four backticks for the outer fence when the body contains ordinary triple-backtick snippets; in all cases use an outer delimiter longer than any backtick run inside the body. Close it with the same delimiter. Use explicit language tags for every inner fence.

Write the body as plain prose with short lists where helpful. Do not include Markdown headings, bold text, frontmatter, internal evidence tables, or review notes. Use inline backticks for literal commands, paths, versions, and errors. Include no subject or signature unless requested. Do not save or send the draft unless asked.

If an essential ambiguity prevents even a qualified reply, ask the user one focused clarification instead of producing a misleading customer body. Otherwise include any useful customer-facing information request directly in the draft.

## Handling Missing Information

- Missing optional details: omit them. A missing customer name or Vault version does not prevent a simple acknowledgement or scheduling request.
- Sparse technical context: draft an acknowledgement plus the smallest useful request, such as the exact error and failing operation. Ask for version/backend only when they affect the next diagnostic or remediation step.
- Unconfirmed bug filing, fix, or resolution: omit the unsupported assertion and draft an evidence-limited status or confirmation request. Ask the engineer to confirm only when the requested message cannot be made accurate without that fact.
- Conflicting evidence: state only the common supported facts and ask which environment or observation applies before recommending a change.
- Missing scheduling or closure policy: request availability and timezone if scheduling was requested; do not invent invitations, SLA timing, automatic reopening rules, or survey delivery.

## Anti-Patterns to Avoid

| Anti-pattern | Failure | Correction |
| --- | --- | --- |
| Raft by default | Gives storage-specific advice without evidence | Use the supplied backend or ask when it matters |
| Template as evidence | Claims “I reproduced/filed/fixed it” from the requested reply type | Confirm the action or omit the claim |
| Intake before every draft | Blocks acknowledgements on a full environment questionnaire | Draft from available facts and ask only for the next needed detail |
| Two-paragraph ceiling | Removes prerequisites or validation from technical steps | Keep the shortest complete procedure |
| Identical inner and outer fences | Splits the copyable body or loses syntax tags | Use a longer outer `text` fence and tagged inner snippets |
| Known issue by resemblance | Converts similar symptoms or one test into a confirmed match or release range | Use qualified wording until investigation supports the claim |
| Closure means resolved | Treats silence or a closure request as proof of recovery | Use confirmed resolution or the supplied administrative closure reason |
| Reassuring promises | Invents updates, release timing, ticket actions, or reopening behavior | Include only supplied commitments and verified status |
