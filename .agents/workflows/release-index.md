# Release Index Workflow

Use this workflow to add or update the canonical `README.md` entry after review.

## Entry criteria

- `review-report.md` metadata status is `ready` and `next_action` is `index`.
- The report recommends inclusion in `README.md`.
- `scenario_id` and `scenario_revision` match the brief and passed validation report.
- Human approval is `not-required` or `approved`; a required `pending` or `rejected` approval stops indexing.
- The final scenario path exists.

## Index update

Run the `scenario-index-curator` skill.

The curator must:

1. Read the complete Scenario Index before editing.
2. Check for duplicate or overlapping entries.
3. Use the section, title, tags, summary, and Known Bugs action approved in `review-report.md`.
4. Preserve the existing hierarchy and `<details>` entry format.
5. Update Known Bugs & Regressions only when the review report explicitly selects `add`, `update`, or `remove` and the evidence supports it.
6. Avoid rewriting unrelated entries.

## Verification

- Confirm every new relative link resolves.
- Confirm tags and description match the published scenario.
- Confirm no existing entry was removed or moved accidentally.
- Run `git diff --check`.

If indexing reveals overlap or a classification mismatch, return to review instead of deciding silently.

