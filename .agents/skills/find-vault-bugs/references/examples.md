# Investigation Examples

These are fictional training examples, not Vault bug reports or release claims. Paths, symbols, error text, and ref labels below belong to an imagined fixture. In a real investigation, resolve refs to actual SHAs and cite real files and official sources.

## Example 1 — Narrow Source Lookup

User request: “Where does the sample backend validate a role name?”

Investigation:

1. No release was requested. Identify the checkout ref and resolve its SHA.
2. Search the route registration, then follow its callback to the validation helper.
3. Read the helper and its call sites. No symptom or release question requires history research.

Example response:

```text
At the inspected fixture ref LOOKUP_BASE, role-name validation is in
builtin/logical/sample/path_roles.go:42, validateRoleName. The roles/:name
route invokes writeRole, which calls this helper before persisting the role.
An empty name returns "sample role name is required".

This describes the inspected fixture baseline; applicability to another
release has not been checked. Tests were inspected, not executed.
```

The real response would include the resolved SHA alongside `LOOKUP_BASE`. A full bug/version report is unnecessary for this request.

## Example 2 — Diagnosis with a Verified Source Backport

User request: “Updating a sample role without `labels` clears existing labels. Is that a bug, and is it fixed on our release line?”

Fixture evidence supplied for this example:

- The user reports the symptom at `INCIDENT_REF` on line A. Its exact source commit is available.
- The applicable fixture API contract states that omitted fields preserve stored values.
- At `INCIDENT_REF`, `updateRole` unconditionally assigns a decoded empty `labels` value before storage.
- At `FIX_REF`, the handler checks field presence before assigning labels; an explicit empty value still clears labels.
- A separate commit `BACKPORT_REF` on line A contains an adapted equivalent change. Both its patch and resulting handler were inspected.
- Tag `LINE_A_CHECKED` contains `BACKPORT_REF`, and its handler retains the field-presence check. Earlier tags and publication records were not checked.

Investigation sequence:

1. Distinguish omission from an explicit empty list in the user's request. Confirm the server baseline, endpoint, and stored-value observation.
2. Read the route, request decoding, update callback, and persistence path at `INCIDENT_REF`.
3. Compare the assignment with the applicable preservation contract. The demonstrated assignment explains the reported data loss; successful authorization does not explain this particular state change.
4. Use path-scoped history to find `FIX_REF`. Inspect its parent and patch, then inspect the adapted backport separately.
5. Verify `BACKPORT_REF` containment and resulting behavior in source at `LINE_A_CHECKED`. Do not infer publication or an earliest fixed version.
6. Inspect the omitted-field regression test. Record that it was not executed.

Example report (symbolic refs stand in for resolved SHAs only in this fictional example):

```markdown
---
title: Sample role update clears omitted labels
doc_type: vault_investigation
created: 2026-10-07
---

## Conclusion

The fixture's incident implementation violates its documented omitted-field behavior. An equivalent fix is verified in source on line A; release availability remains unconfirmed.

- Assessment: confirmed bug
- Upstream status: not checked
- Fix availability: verified in source; release unconfirmed
- Basis: the incident handler unconditionally overwrites stored labels, while the applicable API contract requires preserving omitted fields.

## Question and Observations

- Question: diagnose label loss and check the fix on line A.
- Environment: fixture Enterprise server at INCIDENT_REF; built-in sample backend.
- Expected: omitted labels preserve their stored value under the fixture API contract.
- Observed: user reports that a successful update omitting labels clears them; not reproduced locally.

## Search Scope

- Repository: local fictional fixture.
- Inspected refs: INCIDENT_REF, FIX_REF and its parent, BACKPORT_REF, LINE_A_CHECKED; symbolic commit labels for this example.
- Areas searched: sample route, labels decoding, updateRole, persistence, and omitted-field test.
- External sources: fixture API contract; upstream issue and publication records not checked.

## Evidence and Reasoning

| Finding | Evidence | Interpretation / limitation |
|---|---|---|
| Omitted labels become empty before storage | INCIDENT_REF, builtin/logical/sample/path_roles.go, updateRole | Demonstrates a path violating the supplied preservation contract |
| Fix checks field presence | FIX_REF, same handler and regression test | Distinguishes omission from explicit clearing; test inspected only |
| Equivalent backport remains in checked tag | BACKPORT_REF and LINE_A_CHECKED, same handler | Source fix verified; publication and earlier tags not checked |

Request-field omission explains this assignment path. An explicitly empty labels value would be intentional clearing instead; incident applicability depends on the reported omission being accurate.

## Fix and Version Evidence

| Release line / edition | Affected evidence | Fixed evidence | Backport / release verification |
|---|---|---|---|
| Line A / fixture Enterprise | INCIDENT_REF: faulty assignment established in source | LINE_A_CHECKED: field-presence guard verified in source | BACKPORT_REF independently inspected; publication unconfirmed |

The earliest fixed release and affected version range are unconfirmed. Only the listed baselines were checked.

### Relevant Changes and Upstream References

- FIX_REF: original functional fix; parent and patch inspected.
- BACKPORT_REF: adapted equivalent fix for line A; resulting handler inspected.
- Fixture API contract: omitted labels must preserve stored values.
- Official issue and release URLs: not checked in this example.

## Validation

- Inspected: regression assertion that omission preserves labels and explicit empty labels clear them.
- Executed: no tests or runtime reproduction.
- Applicability: source explains the reported incident conditions; no local runtime confirmation.

## Gaps

- Publication status, earlier line-A tags, and other release lines were not checked.
- Incident request omission is user-reported rather than locally observed.

## Recommended Next Step

Check the official release record for LINE_A_CHECKED to determine whether the verified source fix is available in a published line-A release.
```
