# <Issue ID if known: concise issue title>

## Issue and current behavior

<Reported or reproduced operation, exact sanitized failure/result, impact, and relevant conditions. Identify the evidence rather than presenting a report as independently observed.>

- Reported version/edition: <known values or consequential unknowns; add dependency/platform context only if relevant>
- Investigation assessment: <supported conclusion and confidence, including non-defect explanations where established>

## Expected behavior

<Desired outcome and its basis: cited contract, test, or explicit proposed requirement. Include constraints that affect the fix.>

## Evidence and code paths

Source baseline: <repository, ref, resolved commit SHA; identify dirty-tree changes and differences from the incident or implementation target if applicable>

- `<path>:<line range>` — `<symbol>`: <causal responsibility and what inspection establishes at this revision>
- <Decisive reproduction, documentation, or supplied evidence reference; distinguish observations from inference>

## Options and recommendation

<Conditional section: omit unless a meaningful tradeoff exists. Compare viable approaches, their decisive costs/risks, and the reason to choose one or defer the decision.>

## Minimal implementation plan

<State the causal gap and recommended scope. If no code change is justified, state the remedy or next investigation step here. If evidence is incomplete, label the proposal conditional.>

1. <Candidate file/symbol, behavior to change, and evidence-based rationale>
2. <Next necessary step; remove unused steps>

<Include externally visible behavior, compatibility or migration implications, and exclusions only when they affect this change.>

## Validation

- Regression: <trigger, intended assertion, and why it exposes the pre-change failure>
- Control/boundary: <valid or unaffected behavior to protect; relevant error or edge cases>
- Test location and method: <inspected existing patterns, candidate test area, and focused proposed command when known>
- Checks performed: <actual command/context/result or inspected evidence; explicitly state when no runtime checks were run>

## Unknowns and next steps

<Each consequential unknown, the decision it blocks, and the next check. Use a short "No blocking unknowns identified from the supplied evidence" only if justified.>

## References

- <Consulted source at its revision, official documentation/issue/PR link, or identifiable supplied evidence; omit duplicate entries already fully cited above>
