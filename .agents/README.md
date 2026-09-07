# Vault Scenario Agent Workflow

This directory is the durable interface for AI-assisted work in this repository. Agents hand multi-stage scenario work to one another through files under `drafts/<scenario-slug>/`; prior chat context is optional and must not be the only source of requirements or evidence.

Root [AGENTS.md](../AGENTS.md) remains authoritative for repository-wide rules. This file is the navigation hub for AI workflows, skills, templates, and OpenCode entry points.

## Quick navigation

| Goal | Start here |
| --- | --- |
| Create a new scenario | [workflows/scenario-authoring.md](workflows/scenario-authoring.md) → [scenario-review.md](workflows/scenario-review.md) → [release-index.md](workflows/release-index.md) |
| Maintain a published scenario | [workflows/scenario-maintenance.md](workflows/scenario-maintenance.md) |
| Diagnose / bug-hunt / reply / unit-test | [workflows/support-workflows.md](workflows/support-workflows.md) |
| Bug triage orchestrator (WIP) | [workflows/bug-triage.md](workflows/bug-triage.md) |
| Contract status / next_action rules | [shared/contract-metadata.md](shared/contract-metadata.md) |
| OpenCode slash commands | [../.opencode/commands/](../.opencode/commands/) |

## Workflow trees

### Creation

```text
source-notes.md + links.md
            |
            v
     scenario-brief.md -> human approval
            |
            v
 scenario implementation  (vault-scenario-author)
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
      topic-folder README / KNOWN_BUGS or close  (scenario-index-curator)
```

Skills in order: `vault-scenario-planner` → `vault-scenario-author` → `vault-scenario-validator` → `vault-scenario-reviewer` → `scenario-index-curator`.

### Maintenance

```text
published scenario + new evidence
            |
            v
   maintenance-report.md --no-change--> close
            |
       update or replan
            v
   validation -> review -> re-index or close
```

Skills: `scenario-maintainer`, then validator / reviewer / index curator as required. Material scope change returns to `vault-scenario-planner`.

### Support and investigation (non-scenario)

```text
ticket / error / suspected bug
            |
   +--------+------------------+
   |        |                  |
   v        v                  v
 docs    bug hunt        bug triage
 (document-reference)  (find-vault-bugs)  (bug-triage)
   |        |                  |
   +----+---+                  |
        |                      |
        v                      v
  optional scenario create   human sends reply
  or vault-unit-tests
```

Full trees, handoffs, and OpenCode mapping: [workflows/support-workflows.md](workflows/support-workflows.md).

## Skill and command matrix

| Skill | Role | Workflow | OpenCode command |
| --- | --- | --- | --- |
| `vault-scenario-planner` | Bound a scenario brief | create / replan | via `vault-workflow` |
| `vault-scenario-author` | Implement approved brief | create / remediate | via `vault-workflow` |
| `vault-scenario-validator` | Execute and record evidence | create / maintain | via `vault-workflow` |
| `vault-scenario-reviewer` | Quality and release gate | create / maintain | via `vault-workflow` |
| `scenario-index-curator` | Update topic-folder README and `KNOWN_BUGS.md` | release-index | via `vault-workflow` |
| `scenario-maintainer` | Assess / update drift | maintain | via `vault-workflow` |
| `document-reference` | Docs-based diagnosis | support | `document-reference` |
| `find-vault-bugs` | Source / issue / version hunt | support | `find-vault-bugs` |
| `vault-unit-tests` | Enterprise unit test work | support | `vault-unit-tests` |
| (WIP) | Bug triage orchestrator | support | `bug-triage` |

Support skills may feed evidence into scenario intake. They do not replace contract handoffs.

## Directory layout

```text
.agents/
├── README.md                 # this file — workflow navigation hub
├── shared/
│   ├── contract-metadata.md  # YAML status, revision, next_action, approval
│   ├── repo-conventions.md
│   ├── scenario-schema.md
│   ├── safety-rules.md
│   └── quality-rubric.md
├── workflows/
│   ├── scenario-authoring.md
│   ├── scenario-review.md
│   ├── scenario-maintenance.md
│   ├── release-index.md
│   ├── support-workflows.md  # docs / bugs / reply / unit-tests trees
│   └── bug-triage.md         # WIP orchestrator stub
├── templates/
│   ├── source-notes.md
│   ├── links.md
│   ├── scenario-brief.md
│   ├── validation-report.md
│   ├── review-report.md
│   └── maintenance-report.md
└── skills/
    ├── vault-scenario-planner/
    ├── vault-scenario-author/
    ├── vault-scenario-validator/
    ├── vault-scenario-reviewer/
    ├── scenario-index-curator/
    ├── scenario-maintainer/
    ├── document-reference/
    ├── find-vault-bugs/
    └── vault-unit-tests/

.opencode/commands/           # OpenCode adapters (repo root, not under .agents/)
├── vault-workflow.md
├── document-reference.md
├── find-vault-bugs.md
├── vault-unit-tests.md
└── bug-triage.md             # WIP template

.agents/instructions/         # local-only; gitignored
└── internal-tools.md         # expected local guidance for ~/repos/ selection
```

- `shared/` defines contract metadata, conventions, the scenario schema, safety rules, and the quality rubric.
- `workflows/` defines stage order, entry criteria, outputs, and human gates.
- `templates/` defines the files passed between stages.
- `skills/` assigns one bounded responsibility to each specialist.
- `.opencode/commands/` exposes OpenCode slash-command entry points into skills and the scenario pipeline.
- `.agents/instructions/` holds machine-local internal tooling notes and is not committed.

## Specialist roles

Scenario pipeline:

- `vault-scenario-planner` turns source material into `scenario-brief.md`.
- `vault-scenario-author` implements only the approved brief.
- `vault-scenario-validator` executes checks and writes `validation-report.md`.
- `vault-scenario-reviewer` applies the quality gate and writes `review-report.md`.
- `scenario-index-curator` updates the topic-folder `README.md` and `KNOWN_BUGS.md` after approval.
- `scenario-maintainer` assesses drift and writes `maintenance-report.md`.

Support specialists:

- `document-reference` produces a structured docs/evidence report.
- `find-vault-bugs` maps behavior to code, issues, fixes, and versions.
- `vault-unit-tests` writes or reviews tests in `~/repos/vault-enterprise`.

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

For support work without publishing a scenario:

1. Follow [support workflows](workflows/support-workflows.md).
2. If the outcome should become repo content, open a draft directory and enter create or maintain.

OpenCode users can start the scenario pipelines with `/vault-workflow`.

## Model routing

Model choice is an operational optimization, not evidence:

- Use a stronger reasoning model (e.g. Sonnet 5) for ambiguous planning, source-level diagnosis, safety-sensitive changes, and final review.
- Use a faster or lower-cost model (e.g. GPT 5.6 Luna) for bounded formatting, mechanical authoring from an approved brief, link checks, and index updates.
- Escalate when the evidence contradicts the brief or a safety gate is reached.
- Pass only the relevant contracts and files to each specialist instead of replaying the full conversation.
- Apply the same validation and review gates regardless of model cost.
