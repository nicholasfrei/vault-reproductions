---
name: find-vault-bugs
description: Investigate whether a Vault Enterprise behavior maps to a known bug, fix, or backport.  This file should be placed in .bob/skills/find-vault-bugs/SKILL.md within your repo.
---

# Find Vault Bugs

Use this skill when the user wants source-level confirmation that a Vault Enterprise behavior is a bug or wants help mapping a fix to versions.

## Steps

1. Start with the most specific symptom available: exact error, panic, API path, subsystem, function, or behavior description.
2. Search the local `vault-enterprise` clone to find the relevant code path, tests, and commit history.
3. Look for candidate fixes, related PRs, backports, and release-line evidence.
4. Confirm version coverage using tags, branches, changelog entries, or explicit upstream references.
5. Mark version status as unconfirmed when the evidence is incomplete.

## Output

- Produce a Markdown report with code evidence, upstream references, fix status, and versions.
- Do not guess affected or fixed versions.
- Prefer exact file paths, commit SHAs, and official references.
