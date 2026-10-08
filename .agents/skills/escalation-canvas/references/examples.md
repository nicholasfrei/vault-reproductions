# Escalation Canvas Examples

These are fictional, sanitized training examples. Times, counts, environment details, and findings are illustrative, not evidence from an actual customer or proof of Vault behavior.

## Create a canvas from incomplete notes

Request: “Create a canvas for the next region from these notes.”

Supplied fixture notes:
- Vault Enterprise, three-node Raft environment, version/build not provided. The affected system uses an external auth plugin. A sandbox is available, but equivalence to production is unverified.
- The operator reports issuing a broad plugin reload and seeing high memory and a leadership change around `2026-09-21 08:15 UTC`. They also report lost quorum; no membership or server-log evidence has been reviewed. Request timing and ordering are unknown.
- An earlier note says 120 plugin mounts; a later inventory says 240 enabled mounts. The inventory scope is not supplied.
- Package `debug-a` covers `08:10–08:20 UTC` on `<node-a>` and was collected at `09:00 UTC`. The outgoing engineer reviewed only the process-memory samples at `10:00 UTC`; they show a peak at `08:17 UTC`. Server logs and other nodes remain unreviewed.
- The team proposes testing a narrower reload scope after checking available controls. This has not been tried. No next-shift owner or meeting time is supplied.

Expected canvas:

```markdown
# Escalation: memory pressure and leadership change during reported plugin reload

## Current status

- As of: update time not provided; latest supplied review: 2026-09-21 10:00 UTC.
- Impact and operational state: the operator reports high memory, a leadership change, and lost quorum. Current availability and quorum loss are not independently verified.
- Current focus: establish reload/event ordering and whether the memory increase contributed to the leadership change (I1).

## Environment

- Product/build: Vault Enterprise; exact version and build not supplied.
- Affected environment: reported three-node Raft deployment with an external auth plugin.
- Scale: earlier note reports 120 plugin mounts; later inventory reports 240 enabled mounts. Scope and collection times are unknown; these are not established as counts of the same thing.
- Reproduction environment: a sandbox is available; its relevant differences from production have not been verified.

## Affected workflow and observed behavior

1. The operator reports issuing a broad reload of the external auth plugin. The exact request, scope, and timestamp are not yet supplied.

- Expected: complete the operation while retaining service availability; applicable behavior and prerequisites still need verification.
- Observed: the operator reports high memory and a leadership change around 2026-09-21 08:15 UTC. The memory samples reviewed in I1 peak at 08:17 UTC.
- Unresolved sequence: request timing, event ordering, and the report of lost quorum need correlated evidence. These notes do not establish a reproducible trigger.

## Investigation and evidence

### I1 — Partial review of debug-a

- Action/review status: received; partially reviewed.
- Source and coverage: debug-a, <node-a>, 2026-09-21 08:10–08:20 UTC; collected at 09:00 UTC that day.
- Reviewed: outgoing engineer's supplied findings, 2026-09-21 10:00 UTC. No independent review was performed while drafting this canvas.
- Scope and result: only process-memory samples were examined; peak at 08:17 UTC. Server logs, plugin-level resource use, other nodes, and quorum state remain unchecked. A process-memory peak alone does not establish the cause or event ordering.

## Working theories

### H1 — Reload-related resource pressure contributed to the leadership change

- Status: under investigation.
- Supports: the operator associates the reload with the incident; I1 establishes a memory peak within the reported incident window.
- Contrary evidence / gaps: exact reload/election ordering is unknown. Plugin-level consumption, resource limits, and the reported quorum loss have not been checked. The mount counts have different or unknown scopes.
- Next check: correlate the reload request, memory samples, and leadership logs across relevant nodes. Pressure preceding the first leadership event would support further testing; leadership changes before the reload would weaken this explanation for that event. Neither ordering alone proves causality.

## Next actions and regional handoff

1. Obtain the reload request details and review the event sequence across nodes (H1) — proposed; owner: unassigned. Confirm whether quorum was actually lost.
2. Reconcile plugin-specific versus total enabled-mount counts and their collection scope — proposed; owner: unassigned.
3. Evaluate a narrower reload experiment in the sandbox (H1) — proposed, not attempted; owner: unassigned. Blocked on documented scope controls, sandbox equivalence, and the experiment's impact/recovery plan. A successful mitigation would not by itself confirm the cause.
```

## Update a theory without erasing history

New fixture input: “At 11:00 UTC, the outgoing engineer reviewed server logs in debug-a and a supplied request record. The first leadership event is at 08:14 UTC; the reload request is at 08:16 UTC. Both sources use UTC. Other nodes are still unchecked.”

Update the complete canvas while retaining I1 and H1. Relevant changed sections would include:

```markdown
### I2 — Correlate the first leadership event with the reload request

- Action/review status: completed for the supplied records; cross-node review remains incomplete.
- Source and coverage: debug-a server logs for <node-a> and the supplied reload request record, 2026-09-21 08:10–08:20 UTC.
- Reviewed: outgoing engineer's supplied findings, 2026-09-21 11:00 UTC.
- Scope and result: first leadership event at 08:14 UTC; reload request at 08:16 UTC. This ordering weakens H1 as an explanation for the first event. It does not establish why leadership changed or explain other nodes.

### H1 — Reload-related resource pressure contributed to the leadership change

- Status: weakened for the first leadership event.
- Supports: I1 still establishes a later memory peak; the reload may be relevant to that later pressure.
- Contrary evidence / gaps: I2 places the first leadership event before the recorded reload request. Cross-node timing and any earlier requests remain unchecked.
- Next check: examine the other nodes and earlier request history. A verified earlier reload could reopen this explanation; otherwise investigate causes preceding the first event separately from the later memory peak.
- Status change: weakened following I2, reviewed 2026-09-21 11:00 UTC. Previously under investigation because event ordering was unknown.
```

Also refresh the top summary and handoff actions: identify I2 as the newest supplied review, carry forward unreviewed nodes, and replace the completed single-node timing task with the remaining cross-node check. Keep the narrower reload experiment proposed unless its status actually changes. Do not mark the entire package reviewed or H1 globally ruled out.

## Additional decision checks

- “We received a new debug zip” with no review result: record it as received and unreviewed; collection time and coverage are unknown unless supplied.
- “The test is planned for Monday” without date/timezone: retain it as planned and flag the schedule ambiguity; do not put it in completed investigation history.
- “Memory is normal after the change”: attribute that observation and its interval; do not infer that the cause is proven, service recovered everywhere, or a permanent fix shipped.
- “Update the canvas” with new logs but no prior canvas: request the current document; offer a clearly bounded summary of the new evidence without claiming to preserve unseen history.
- “Write the code change for the established defect”: use the source-repository workflow and relevant testing guidance; use the canvas as evidence rather than treating document organization as implementation.
