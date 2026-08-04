---
name: customer-reply
description: Draft a Zendesk-ready support reply for a HashiCorp Vault customer ticket. Use this when the user asks to write, draft, or compose a customer-facing response, acknowledgement, follow-up, log request, bug-filed notice, or ticket closure for Vault support. Enforces extreme brevity, plain text (no markdown headers or bold), break-fix-only scope, and clipboard-safe code blocks. Includes nine reusable templates (acknowledgement, follow-up, no-response follow-up, request for info, request logs, schedule session, bug filed, known issue, closing, closing with feedback request).
---

# Customer Reply Skill

Draft a customer-facing reply to a HashiCorp Vault support ticket. Output must be safe to paste directly into Zendesk.

## When to use

Use this skill when the user asks for any of:

- "Draft a reply", "respond to the customer", "write a Zendesk response"
- An acknowledgement, follow-up, request for logs / info, schedule of a session
- A bug-filed update, known-issue update, or ticket closure
- Any other customer-facing technical reply for a Vault break-fix issue

## How to draft a reply

1. Confirm the situation: what is the symptom, what does the customer need next, and which template (below) is the closest fit.
2. If important context is missing (Vault version, storage backend, exact error string, recent changes), ask for it before drafting — do not invent details.
3. Pick the matching template, fill in placeholders, and apply the rules below.
4. Output only the reply body, inside a single fenced code block with no language tag, so the user can copy/paste cleanly.

## Tone and style

- Extreme brevity. Prioritize concise, actionable steps over long explanations. If a reply exceeds two short paragraphs, look for ways to trim.
- Action-oriented. Focus on "how to fix," not "why it works."
- Direct and professional. Avoid conversational filler, excessive pleasantries, or fluff.
- Confident and technical. Precise without being academic.

## Formatting (critical)

- No markdown headers (`#`, `##`) and no bold (`**`) in the customer-facing body.
- Plain paragraph text. Use lists only for multi-step technical procedures.
- Use `inline code` for short paths or single variables.
- Use triple backticks for commands, but omit the language identifier (use ``` not ```bash) so it pastes cleanly into Zendesk.
- Wrap the entire generated reply in one outer ``` block so the user can copy it as a unit.

## Scope and constraints

- Break-fix only. Resolve errors, crashes, or specific misconfigurations.
- No architectural guidance. Do not advise on "well-architected" patterns, infra design, or long-term strategy. If the customer asks for design advice, point them to documentation or their account manager.
- No ETAs. Never promise specific dates for bug fixes or releases.
- Do not blame the customer. Do not over-apologize.

## Vault-specific context

- Product: HashiCorp Vault.
- Docs: https://developer.hashicorp.com/vault/docs
- API docs: https://developer.hashicorp.com/vault/api-docs
- Assume Integrated Storage (Raft) unless logs say otherwise.
- Use HCL for configuration snippets.
- For KVv2, get `/data/` and `/metadata/` prefixes correct in policy examples to avoid permission denied errors.
- Reference docs at the end of a sentence using the form: [docs](https://developer.hashicorp.com/vault/docs).

## What to avoid

- Phrases like "in a production environment, you should..." or "we recommend this architecture for scalability."
- Excessive theory. Keep the "why" minimal unless it is required for the fix.

## Reply structure

1. Status: brief acknowledgement of the issue.
2. Action: the specific command, configuration fix, next step, or log request.
3. Reference: relevant documentation links when applicable.
4. Closing: a short offer for further technical help.

## Templates

### General ticket acknowledgement

```
Hello [Customer Name],

Thank you for contacting Vault Support. I've received your ticket and I'm beginning my investigation. My initial step will be to [review the logs / attempt to replicate the issue / research the behavior].

I will get back to you as soon as I have an update.
```

### Follow up

```
Hello [Customer Name],

Thank you for reaching out to Vault Support Team. I am reaching out to see if you've been able to review my suggestion regarding the error you are facing. If you need more information or would like to schedule a troubleshooting session, please let me know.

Please feel free to reach out if you have any questions or concerns.
```

### Follow up (no response)

```
Hello [Customer Name],

I wanted to follow up regarding your support ticket, as I have not heard back from you in several days. If you are still experiencing the issue or need further assistance, please let me know. I am here to help and can provide additional troubleshooting or schedule a session if needed.

If your issue has been resolved, please confirm so I can close out the ticket. Otherwise, I look forward to your reply.
```

### Request for more information

```
Hello [Customer Name],

To help me better understand the issue, could you please provide some more information? Specifically, it would be helpful to have:

* [List specific information needed, e.g., Vault version, configuration files, OS, etc.]
* Steps to reproduce the issue.
* Any recent changes to the environment.

This information will help me to investigate further.
```

### Request Vault log files

```
Please review the knowledge article [Where are My Vault Logs and How do I Share Them with HashiCorp Support?](https://support.hashicorp.com/hc/en-us/articles/360002046068) for details on Vault operational and audit device logging, and how to share the logs with us.

Let us know if you have further questions regarding gathering and sharing the requested logs.

Additional Resource on Finding and Packaging the Logs:
https://developer.hashicorp.com/vault/tutorials/monitoring/troubleshooting-vault?in=vault%2Fmonitoring#finding-server-logs-on-linux-systems
```

### Schedule a troubleshooting session

```
Hello [Customer Name],

To help resolve this issue, I'd like to schedule a troubleshooting session with you. This will allow us to investigate the environment and behavior together in real-time.

Please let me know what days and times work best for you in the coming days. Providing a few options would be very helpful.
```

### Bug report filed

```
Hello [Customer Name],

Thank you for your patience while I investigated this issue. I have been able to confirm the behavior you are seeing and have filed a bug report with our engineering team.

I will let you know as soon as I have an update from the team. Please let me know if you have any questions in the meantime.
```

### Known issue

```
Hello [Customer Name],

Thank you for reaching out. The issue you are describing is a known issue that our team is aware of. You can track the progress of the fix here: [Link to public bug tracker or KB article]

I will also update you as soon as a fix is available. Please let me know if you have any other questions.
```

### Closing - general

```
Hello [Customer Name],

I'm glad we were able to resolve the issue. I'm marking this ticket as solved for now, but you can always reopen it by replying to this email if the issue persists.

It was a pleasure working with you.
```

### Closing - with feedback request

```
Hello [Customer Name],

As agreed, I'm marking this ticket as solved. If there are still any questions related to this case, reply to this thread and the ticket will be reopened and I'll strive my best to answer them. If there are any new issues, please open a new ticket so we can assist you as best as possible.

Your feedback is valuable to us. If you have a moment, we would be grateful if you could complete the customer satisfaction survey that will be sent to your email.
```
