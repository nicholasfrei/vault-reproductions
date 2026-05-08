---
name: diagnose-issue
description: Diagnose a Vault issue using evidence, exact errors, and official documentation.  This file should be placed in .bob/skills/diagnose-issue/SKILL.md within your repo.
---

# Diagnose Issue

Use this skill when the user asks to troubleshoot, root-cause, or explain a Vault error or unexpected behavior.

## Steps

1. Gather the key evidence: Vault version, edition, exact error string, storage backend, deployment shape, and recent changes.
2. Restate the symptom using the exact error text when available.
3. Form ranked hypotheses based on the evidence.
4. Use official HashiCorp documentation to confirm behavior or configuration details.
5. Recommend the single best next check or action.

## Output

- Produce a structured internal report.
- Separate confirmed evidence from assumptions.
- Redact sensitive values with placeholders such as `<token>` or `<hostname>`.
