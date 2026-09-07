---
name: scenario-index-curator
description: Adds or updates reviewed Vault scenarios in the matching topic-folder README and KNOWN_BUGS.md without disturbing unrelated entries. Use only after a review report marks a scenario ready.
---

# Scenario Index Curator

Update repository discovery metadata after scenario approval.

## Required inputs

Read:

- Root `AGENTS.md`, especially scenario index formatting
- `.agents/shared/contract-metadata.md`
- The topic-folder `README.md` for the published path (`auth/README.md`, `secrets/README.md`, `sys/README.md`, and so on)
- Root `README.md` only to confirm the category map still points at that folder
- `KNOWN_BUGS.md` when the review Known Bugs action is not `none`
- The published scenario
- `drafts/<scenario-slug>/scenario-brief.md`
- `drafts/<scenario-slug>/validation-report.md`
- `drafts/<scenario-slug>/review-report.md`
- `drafts/<scenario-slug>/maintenance-report.md` when `workflow` is `maintain`

Stop unless the review metadata is `ready` with `next_action: index`, inclusion is recommended, every contract uses the same scenario revision, and aggregate human approval is `not-required` or `approved`.

## Process

1. Verify the final scenario path exists.
2. Search the matching topic-folder README and `KNOWN_BUGS.md` for duplicates, related entries, and the correct hierarchy.
3. Apply the approved title, tags, summary, and Known Bugs action from the review report.
4. Preserve the link/tags/`<details>` structure. Use paths relative to the topic folder.
5. Modify `KNOWN_BUGS.md` only when the review selects `add`, `update`, or `remove` and explicitly approves supported version, fix, and `VAULT-XXXXX` claims.
6. Do not reintroduce a full scenario catalog or directory tree on the root `README.md`.
7. Preserve all unrelated entries and their wording.
8. Verify relative links and run `git diff --check`.

## Output

- Update only the required topic-folder `README.md` entry or entries, and `KNOWN_BUGS.md` when the review action requires it.
- Report any overlap or classification conflict instead of resolving it silently.
- Do not alter scenario content during indexing.
