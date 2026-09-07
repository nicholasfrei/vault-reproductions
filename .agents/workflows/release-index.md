# Release Index Workflow

Use this workflow to add or update the topic-folder `README.md` entry after review, and `KNOWN_BUGS.md` when the review requires it.

## Entry criteria

- `review-report.md` metadata status is `ready` and `next_action` is `index`.
- The report recommends inclusion in the topic-folder `README.md`.
- `scenario_id` and `scenario_revision` match the brief and passed validation report.
- Human approval is `not-required` or `approved`; a required `pending` or `rejected` approval stops indexing.
- The final scenario path exists.

## Index update

Run the `scenario-index-curator` skill.

The curator must:

1. Read the complete topic-folder README for the published path before editing.
2. Check for duplicate or overlapping entries in that folder index and in `KNOWN_BUGS.md`.
3. Use the section, title, tags, summary, and Known Bugs action approved in `review-report.md`.
4. Preserve the existing hierarchy and `<details>` entry format. Use paths relative to the topic folder.
5. Update `KNOWN_BUGS.md` only when the review report explicitly selects `add`, `update`, or `remove` and the evidence supports version, fix, and ticket claims.
6. Avoid rewriting unrelated entries.
7. Do not put the full catalog back into the root `README.md`.

## Verification

- Confirm every new relative link resolves.
- Confirm tags and description match the published scenario.
- Confirm no existing entry was removed or moved accidentally.
- Run `git diff --check`.

If indexing reveals overlap or a classification mismatch, return to review instead of deciding silently.
