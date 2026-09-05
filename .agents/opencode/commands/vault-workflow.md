---
description: Run the Vault AI-native workflow with Markdown handoff artifacts.
---

Use `.agents/README.md` as the durable workflow interface.

Request:

$ARGUMENTS

## Operating instructions

1. Read `.agents/shared/contract-metadata.md` and determine whether this is a `create` or `maintain` workflow. Ask when the request is ambiguous.
2. Create or locate `drafts/<scenario-slug>/`. Copy missing `source-notes.md` and `links.md` from `.agents/templates/`.
3. Preserve only sanitized request evidence in `source-notes.md`; preserve references in `links.md`.
4. For `create`, follow `.agents/workflows/scenario-authoring.md` using the planner, author, and validator skills.
5. For `maintain`, follow `.agents/workflows/scenario-maintenance.md` using the maintainer and required downstream skills.
6. Follow `.agents/workflows/scenario-review.md` only after validation is `passed` for the current scenario revision.
7. Follow `.agents/workflows/release-index.md` only when review is `ready`, `next_action` is `index`, and required human approval is complete.
8. Follow `remediate` and `replan` by passing the triggering report to the named specialist. Stop when metadata requires `collect-input`, `human-approve`, `close`, or `none`. Do not skip a stop by relying on chat history.

Keep contract files concise and current. Each stage must be able to continue from the files without relying on chat history.

