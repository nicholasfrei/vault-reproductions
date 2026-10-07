---
title: <short investigation title>
doc_type: vault_investigation
created: <YYYY-MM-DD>
---

## Conclusion

<Direct answer, confidence, and applicability to the reported environment.>

- Assessment: <confirmed bug | likely bug | expected behavior | configuration/environment cause | inconclusive>
- Upstream status: <reported | acknowledged | no matching evidence found | not checked>
- Fix availability: <released | verified in source; release unconfirmed | candidate fix | no fix confirmed | not applicable>
- Basis: <decisive evidence and any qualification>

## Question and Observations

- Question: <requested scope>
- Environment: <server version/build, edition, relevant plugin versions and topology; unknown where missing>
- Expected: <behavior and applicable contract>
- Observed: <sanitized symptom and provenance; distinguish user reports from locally observed results>

## Search Scope

- Repository: <path>
- Inspected refs: <ref and resolved SHA for each baseline; note working-tree modifications if used>
- Areas searched: <paths, symbols, search terms>
- External sources: <sources checked and access/history limitations>

## Evidence and Reasoning

| Finding | Evidence | Interpretation / limitation |
|---|---|---|
| <observation or source finding> | <ref/SHA, path:line, function, test, or official URL> | <what it establishes and what remains unproven> |

<Explain the causal path and the relevant alternative explanations supported, ruled out, or unresolved.>

## Fix and Version Evidence

| Release line / edition | Affected evidence | Fixed evidence | Backport / release verification |
|---|---|---|---|
| <line and edition, or not applicable with reason> | <verified versions and basis, or unconfirmed> | <verified fixed versions and basis, or unconfirmed> | <backport SHA and publication evidence, or none confirmed> |

<State whether the earliest fixed release is established and whether any affected range is proven. Separate source containment from published release status.>

### Relevant Changes and Upstream References

- <commit SHA / issue / PR / docs / release URL, its role, and what was verified; use none confirmed where appropriate>

## Validation

- Inspected: <tests, fixtures, and assertions read, or none>
- Executed: <commands, environment/ref, and outcomes, or not run>
- Applicability: <what the evidence demonstrates about the reported incident>

## Gaps

- <missing evidence and its effect on the conclusion, or none identified within the stated scope>

## Recommended Next Step

<The single most useful next action and the evidence it should produce.>
