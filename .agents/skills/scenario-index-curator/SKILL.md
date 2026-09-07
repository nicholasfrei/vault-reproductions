---
name: scenario-index-curator
description: Adds or updates reviewed Vault scenarios in the canonical README index without disturbing unrelated entries. Use only after a review report marks a scenario ready.
---

# Scenario Index Curator

Update repository discovery metadata after scenario approval.

## Required inputs

Read:

- Root `AGENTS.md`, especially README index formatting
- `.agents/shared/contract-metadata.md`
- Complete `README.md`
- The published scenario
- `drafts/<scenario-slug>/scenario-brief.md`
- `drafts/<scenario-slug>/validation-report.md`
- `drafts/<scenario-slug>/review-report.md`
- `drafts/<scenario-slug>/maintenance-report.md` when `workflow` is `maintain`

Stop unless the review metadata is `ready` with `next_action: index`, inclusion is recommended, every contract uses the same scenario revision, and aggregate human approval is `not-required` or `approved`.

## Process

1. Verify the final scenario path exists.
2. Search the index for duplicates, related entries, and the correct hierarchy.
3. Apply the approved title, tags, summary, and Known Bugs action from the review report.
4. Preserve the link/tags/`<details>` structure.
5. Modify Known Bugs & Regressions only when the review selects `add`, `update`, or `remove` and explicitly approves supported version and fix claims.
6. Preserve all unrelated entries and their wording.
7. Verify relative links and run `git diff --check`.

## Output

- Update only the required `README.md` entry or entries.
- Report any overlap or classification conflict instead of resolving it silently.
- Do not alter scenario content during indexing.

