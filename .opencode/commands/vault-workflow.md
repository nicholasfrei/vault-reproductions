---
description: Author or update a Vault scenario and review it, or review existing content.
---

Use the two-skill scenario workflow in `.agents/README.md` and follow root `AGENTS.md`.

Request:

$ARGUMENTS

## Operating instructions

1. For create/update requests, use `vault-scenario-author`, then `vault-scenario-reviewer` as a separate review pass over the resulting files and evidence.
2. For review-only requests, use `vault-scenario-reviewer` directly. For an explicit draft-only request, finish with the author handoff.
3. Address in-scope review findings through the author skill and recheck affected content. Ask only when missing information, authorization, or a scope decision blocks progress.
4. Return the concise review result, or the author handoff for draft-only work. Use optional draft notes only when a durable handoff is needed.
