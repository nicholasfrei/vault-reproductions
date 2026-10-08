# Conditional UI and Replication Guidance

Read this reference only when a request sequence or node-local readiness affects the issue. Verify all topology and response details at the relevant source revision; these checks do not establish that a particular deployment has a replication race.

## Trace the operation boundary

1. Inspect the initiating action and state-changing request, including the component, route, or adapter where applicable.
2. Inspect immediate follow-up reads, capability checks, route loading, or navigation. Identify which response actually produces the user-visible failure.
3. Distinguish a successful authoritative mutation from a follow-up request that encounters local replication, initialization, or route readiness delay.
4. Separate unrelated failures in the same trace, such as an optional plugin-pin lookup returning `404`, when the evidence shows they are independent. A shared browser session does not prove causality.

If forwarding matters, establish the actual node roles and resource scope. Check primary performance-standby forwarding to its active node, performance-secondary shared-write forwarding, possible two-hop forwarding from a secondary standby, and local-resource handling only as relevant. Do not assume the same path for every operation.

## Evaluate retry handling only after proving a transient condition

If the evidence supports a UI retry for post-create readiness:

- Preserve successful creation. Retry only the safe follow-up loading/navigation operation; do not repeat a successful mutation because a later read failed.
- Match the established transient condition and exact response semantics in the immediate post-create flow. A generic `400`, `403`, `404`, or `5xx` status is not sufficient evidence of retryability.
- Justify finite attempt, delay, and elapsed-time bounds from existing conventions or requirements. If no bounds are established, record that decision as open rather than inventing constants.
- Preserve terminal handling for unrelated errors, permission failures, and exhausted retries. Account for navigation away or cancellation if retries outlive their owner.
- Prefer an existing route transition/reload mechanism over a full browser reload when it preserves the required behavior.

Treat UI handling as one candidate. Confirm that it satisfies the requested contract; a server-side correctness defect affecting all clients may require a different fix.

## Describe user-visible outcomes and validation

State waiting, success, timeout, and safe retry behavior if they change. When creation is known to have succeeded, communicate that availability is pending rather than reporting a failed create. Keep forwarding topology in diagnostic context unless it changes the user's next action.

Propose deterministic tests using the existing mocks, handlers, stubs, or timer controls. Cover immediate success, the recognized transient response followed by success, exhaustion, unrelated terminal errors, and cancellation where applicable. Assert that the successful mutation occurs only once. Use a scoped replication scenario only when needed to validate a property the isolated test cannot prove.
