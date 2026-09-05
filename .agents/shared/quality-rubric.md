# Scenario Quality Rubric

Review each category as `pass`, `needs-work`, or `not-applicable`. A scenario is publishable only when every applicable category passes and no blocking evidence gap remains.

## Scope

- The scenario has one clear primary purpose and type.
- The implementation matches the accepted `scenario-brief.md`.
- Similar repository content was checked for overlap.

## Technical accuracy

- Vault commands, paths, policies, and version claims are accurate.
- Assumptions and untested claims are labeled.
- Expected and observed behavior are not conflated.
- Official documentation or source evidence supports important claims.

## Reproducibility

- Preconditions and required permissions are explicit.
- Steps are ordered and copy/paste friendly.
- A control case exists when it materially strengthens the result.
- Validation has observable success or failure criteria.
- Cleanup restores resources created by the scenario.

## Safety

- Sensitive and customer-specific data is redacted.
- Risky actions identify their target and consequences.
- Defaults do not operate on shared or production infrastructure.
- Scripts fail safely and check prerequisites.

## Repository fit

- Location, filename, headings, and formatting follow `AGENTS.md`.
- Neighboring scenario conventions are reused.
- Changes are narrowly scoped.
- The `README.md` entry is accurate and correctly placed.
- Contract metadata follows `.agents/shared/contract-metadata.md`.

## Evidence

- `validation-report.md` records commands actually run.
- Failures and skipped checks are visible.
- `review-report.md` gives a justified release decision.
- Brief, validation, review, and maintenance contracts identify the same scenario revision.
- Every declared predecessor exists and was consumed by the next stage.

