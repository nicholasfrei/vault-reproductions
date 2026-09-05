# Vault Scenario Agent Workflow

This directory is the durable interface for AI-assisted scenario work. Agents hand work to one another through files under `drafts/<scenario-slug>/`; prior chat context is optional and must not be the only source of requirements or evidence.

## Workflow map

```text
Creation:

source-notes.md + links.md
            |
            v
     scenario-brief.md -> human approval
            |
            v
 scenario implementation
            |
            v
   validation-report.md --failed/partial--> author or planner
            |
          passed
            v
      review-report.md --needs-changes--> author -> validation
            |
          ready
            v
      README index or close

Maintenance:

published scenario + new evidence
            |
            v
   maintenance-report.md --no-change--> close
            |
       update or replan
            v
   validation -> review -> re-index or close
```

## Directory layout

```text
.agents/
├── README.md
├── shared/
│   ├── contract-metadata.md
│   ├── repo-conventions.md
│   ├── scenario-schema.md
│   ├── safety-rules.md
│   └── quality-rubric.md
├── workflows/
│   ├── scenario-authoring.md
│   ├── scenario-review.md
│   ├── scenario-maintenance.md
│   └── release-index.md
├── templates/
│   ├── source-notes.md
│   ├── links.md
│   ├── scenario-brief.md
│   ├── validation-report.md
│   ├── review-report.md
│   └── maintenance-report.md
├── skills/
│   ├── vault-scenario-planner/
│   ├── vault-scenario-author/
│   ├── vault-scenario-validator/
│   ├── vault-scenario-reviewer/
│   ├── scenario-index-curator/
│   └── scenario-maintainer/
└── opencode/commands/
```

- `shared/` defines contract metadata, conventions, the scenario schema, safety rules, and the quality rubric.
- `workflows/` defines stage order, entry criteria, outputs, and human gates.
- `templates/` defines the files passed between stages.
- `skills/` assigns one bounded responsibility to each specialist.
- `opencode/commands/` exposes convenient workflow entry points.

## Specialist roles

- `vault-scenario-planner` turns source material into `scenario-brief.md`.
- `vault-scenario-author` implements only the approved brief.
- `vault-scenario-validator` executes checks and writes `validation-report.md`.
- `vault-scenario-reviewer` applies the quality gate and writes `review-report.md`.
- `scenario-index-curator` updates `README.md` after approval.
- `scenario-maintainer` assesses drift and writes `maintenance-report.md`.

Existing support skills such as `document-reference`, `find-vault-bugs`, `customer-reply`, and `vault-unit-tests` may supply evidence or specialized work inside these boundaries. They do not replace the contract handoffs.

## Contract rules

1. Begin in `drafts/<scenario-slug>/`.
2. Copy `source-notes.md` and `links.md` from `.agents/templates/`. Commit only sanitized evidence summaries; keep raw evidence outside the repository.
3. Copy the required template into the draft directory before filling it in.
4. Follow `.agents/shared/contract-metadata.md`; YAML frontmatter is the machine-readable source of status, ownership, revision, predecessors, next action, and approval.
5. Use one stable `scenario_id` matching the draft directory. Increment `scenario_revision` whenever scenario or supporting files change.
6. Read every predecessor named in the metadata; do not silently reinterpret or omit it.
7. Record unknown facts as `unknown`. Never manufacture Vault versions, results, or upstream status.
8. Write observed commands and outcomes into a report before handing off.
9. If evidence changes the scope, return to the planner and revise `scenario-brief.md`.
10. Agents must not approve their own artifacts. Stop while required human approval is pending.
11. Do not publish or index until `review-report.md` is `ready` for the same scenario revision.

Contract Markdown files are intentionally trackable even though other files under `drafts/` remain ignored. This provides an audit trail without committing temporary binaries, credentials, logs, or infrastructure state.

## Standard workflow

For a new scenario:

1. Follow [scenario authoring](workflows/scenario-authoring.md).
2. Follow [scenario review](workflows/scenario-review.md).
3. Follow [release index](workflows/release-index.md).

For an existing scenario:

1. Follow [scenario maintenance](workflows/scenario-maintenance.md).
2. Re-run validation when behavior or commands change.
3. Re-run review and release indexing when published content or discovery metadata changes.

The root [AGENTS.md](../AGENTS.md) remains authoritative for repository-wide rules.

## Model routing

Model choice is an operational optimization, not evidence:

- Use a stronger reasoning model for ambiguous planning, source-level diagnosis, safety-sensitive changes, and final review.
- Use a faster or lower-cost model for bounded formatting, mechanical authoring from an approved brief, link checks, and index updates.
- Escalate when the evidence contradicts the brief or a safety gate is reached.
- Pass only the relevant contracts and files to each specialist instead of replaying the full conversation.
- Apply the same validation and review gates regardless of model cost.
