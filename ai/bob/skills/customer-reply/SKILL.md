---
name: customer-reply
description: Draft a short Vault support reply for a customer-facing ticket update. This file should be placed in .bob/skills/customer-reply/SKILL.md within your repo.
---

# Customer Reply

Use this skill when the user wants a customer-facing reply for a HashiCorp Vault support case.

## Steps

1. Identify the reply type such as acknowledgement, follow-up, request for logs, bug filed, or closure.
2. Gather the required facts before drafting. Do not invent Vault version, storage backend, or exact error text.
3. Write a concise reply focused on the next action the customer should take.
4. Keep the response plain, professional, and easy to paste into a ticket.

## Output

- Output only the reply body.
- Prefer short paragraphs over long explanations.
- Avoid architectural guidance, ETAs, or speculative statements.
