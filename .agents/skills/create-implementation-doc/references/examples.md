# Implementation Handoff Examples

The first example is a fictional, self-contained training fixture, not evidence of an actual Vault defect. Repository names, revision, paths, symbols, and observations below are illustrative. A real handoff must cite inspected or supplied evidence.

## Example 1 — Backend validation, no alternatives needed

Request: "Turn the investigation into an implementation doc for the plugin's empty destination panic."

Supplied fixture evidence:

- A sanitized local reproduction note reports that submitting an explicit empty `destination` panics and prevents configuration from being saved. No released plugin version is identified.
- The local `example-plugin` fixture at ref `fixture-empty-destination`, commit `1111111111111111111111111111111111111111`, contains `destination[0]` before a length check in `backend/config.go:40-52`, `validateDestination`.
- `backend/config.go:20-38`, `handleConfig`, passes the decoded field to the helper and persists only after validation succeeds. For this fixture, the request path does not otherwise reject the empty field.
- `docs/config.md:12-16` requires a non-empty destination. `backend/config_test.go:30-65`, `TestConfigDestination`, already covers accepted destinations with table-driven request tests.
- The fixture investigation inspected source but did not execute tests. No API redesign or data migration is requested.

Procedure: reuse the supplied baseline with attribution, connect the unchecked index to the report, propose validation before indexing, and protect the normal request path. No UI, replication, options table, or release range is needed. Save to `drafts/empty-destination/implementation.md` unless another destination is requested.

Completed handoff:

```markdown
# Empty destination causes a configuration panic

## Issue and current behavior

The supplied local reproduction note reports a panic when an explicit empty
`destination` is submitted, preventing configuration from being saved. This
handoff has not independently reproduced the failure. Released plugin version
and release coverage are unknown.

Assessment: the source path in the supplied fixture explains the reported
failure; it indexes the empty string before validating it.

## Expected behavior

Reject an empty destination through the existing invalid-configuration error
path, without panicking or persisting configuration. The fixture contract in
`docs/config.md:12-16` requires a non-empty value. Preserve valid inputs and
the existing API shape.

## Evidence and code paths

Supplied source baseline: `example-plugin`, ref `fixture-empty-destination`,
commit `1111111111111111111111111111111111111111`. Working-tree state was not
recorded; these references describe the supplied committed snapshot.

- `backend/config.go:20-38`, `handleConfig`: calls validation before persistence.
- `backend/config.go:40-52`, `validateDestination`: reads `destination[0]`
  without first rejecting the empty string. This explains the failure under
  the supplied request conditions.
- `backend/config_test.go:30-65`, `TestConfigDestination`: provides the nearby
  table-driven request-test pattern and accepted-input controls.

## Minimal implementation plan

1. In `validateDestination`, reject zero-length input before the first index
   access, using the existing validation error convention. Leave the remaining
   destination checks in their current order.
2. Extend `TestConfigDestination` with an explicit empty-field request case.
   Keep the existing accepted-input cases as controls.

## Validation

- Regression: the explicit empty value must return the invalid-configuration
  error without a panic or stored configuration. It reaches the unguarded
  index on the supplied pre-change path.
- Control: existing valid destination cases must still persist successfully.
- Boundary: inspect request decoding for an omitted field and cover it if it
  reaches a materially different path.
- Proposed focused command:
  `go test -count=1 -v ./backend -run '^TestConfigDestination$'`.
- Checks performed: reviewed the supplied investigation and source excerpts;
  no tests were executed while preparing this handoff.

## Unknowns and next steps

Confirm the implementation target revision before applying this plan. The
proposal is justified for the supplied snapshot; release applicability remains
unverified. Inspect omitted-field decoding to determine whether it needs a
separate regression case.

## References

- Supplied sanitized local reproduction note: explicit empty destination.
- `docs/config.md:12-16` at the source baseline above: non-empty requirement.
```

## Example 2 — Cause remains unresolved

Request: "Document this intermittent `403` and possible fixes." Only a sanitized error and timestamp are available; no request policy context, source revision, or reproducer is supplied.

Expected behavior of the skill:

1. Record the reported denial and impact. Mark the expectation and cause unverified; do not classify the response as transient merely because it is intermittent.
2. Use `find-vault-bugs` for source-level diagnosis or `document-reference` for the applicable authorization contract when useful evidence is accessible.
3. Produce a partial handoff with a conditional plan or a next investigation step. Ask for the sanitized operation and policy/identity context that distinguish intended denial from a defect; do not request credentials.
4. State that no retry or policy-bypass change is justified yet. Record missing source evidence and the blocked decision rather than inventing file paths, test commands, or a fix.

## Example 3 — Evidence supports no code change

Request: "Document the issue and potential fix." The supplied investigation establishes that the operation was rejected under the configured policy and the documentation confirms the required capability.

Expected behavior of the skill: cite that evidence, explain the policy mismatch, and describe the supported configuration correction as the recommendation. Validate the required access while retaining a denied control case. Do not manufacture a server patch, multiple design options, or a claim that a released defect was fixed. Any live policy change remains outside the documentation step.
