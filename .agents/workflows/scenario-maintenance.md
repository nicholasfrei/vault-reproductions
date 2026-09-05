# Scenario Maintenance Workflow

Use this workflow when a published scenario may be stale, incomplete, broken, or superseded.

## Triggers

- A new Vault release changes behavior
- A fix or backport becomes available
- A documentation or upstream issue changes status
- A user reports that commands or validation no longer work
- Repository conventions change

## 1. Assess

Create or update:

- `drafts/<scenario-slug>/source-notes.md` from `.agents/templates/source-notes.md`
- `drafts/<scenario-slug>/links.md` from `.agents/templates/links.md`

Set `workflow: maintain` in both artifacts. When intake is sufficient, set them to `ready`, use the current scenario revision, and set `next_action: maintain`.

For a published scenario without prior contracts, first create a baseline `scenario-brief.md` from the published file and README entry. Set `workflow: maintain`, use revision `"1"`, mark unknown facts `unknown`, and record the published path. This baseline is descriptive and does not invent past validation.

When a prior brief exists, set its current workflow to `maintain` while retaining its stable ID and scenario revision. Reset brief approval to `pending` only when maintenance changes approved scope.

Run the `scenario-maintainer` skill to produce:

- `drafts/<scenario-slug>/maintenance-report.md`

Maintenance status controls the next step:

- `no-change`: set `next_action: close`, retain the evidence, and stop.
- `needs-input`: set `next_action: collect-input` or `human-approve` and stop.
- `ready-for-update`: continue with a bounded correction.
- `ready-for-validation`: skip directly to validation when no content change is needed.
- `deprecate`: obtain human approval, then review the retirement and index changes.
- A material scope change: set `next_action: replan` and return to planning.

## 2. Update

For a bounded correction, the maintainer may update the scenario according to the report.

Increment `scenario_revision` in the brief and maintenance report before changing the scenario or supporting files. Prior validation and review reports no longer apply.

After recording the completed changes, set maintenance status to `ready-for-validation` and `next_action: validate`.

If the purpose, classification, affected versions, or reproduction path changes materially:

1. Run the planner again.
2. Replace or revise `scenario-brief.md`.
3. Include `maintenance-report.md` as a predecessor.
4. Obtain human approval of the revised brief.
5. Use the full authoring workflow.

## 3. Revalidate and review

Run the validator for every published content change. Behavioral checks are required for behavior or command changes; documentation-only changes still receive applicable static validation. Then run the reviewer.

The validator and reviewer must read `maintenance-report.md` and use the same `scenario_id` and `scenario_revision`.

After validation passes, record `validation-report.md` in the maintenance report, set maintenance status to `ready-for-review`, and set `next_action: review`.

Required outputs:

- Updated `validation-report.md`
- Updated `review-report.md`

## 4. Re-index

Run the release index workflow when the title, location, tags, description, affected versions, fixed versions, or known-bug status changed.

For deprecation, supersession, or rename, the review report must explicitly approve the README and Known Bugs action before indexing.

