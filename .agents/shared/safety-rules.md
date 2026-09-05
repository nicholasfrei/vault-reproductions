# Safety Rules

These checks apply at planning, authoring, validation, review, and maintenance.

## Sensitive data

- Never commit tokens, licenses, private keys, cloud credentials, customer names, public IP addresses, or real hostnames.
- Use placeholders such as `<token>`, `<hostname>`, `<ip_addr>`, `<namespace>`, and `<email>`.
- Treat copied logs and command history as sensitive until reviewed and redacted.
- Do not place sensitive values in command-line examples where they can enter shell history.

## Execution safety

- Default to local, disposable, or explicitly identified test infrastructure.
- Do not run destructive Vault, Kubernetes, cloud, database, or filesystem commands against an unspecified target.
- State the target context before commands that delete, revoke, rotate, rekey, restore, fail over, or replace resources.
- Include cleanup, but keep cleanup commands scoped to resources created by the scenario.
- Use least-privilege test policies and credentials where practical.

## Evidence safety

- Never claim a command passed unless it was executed and its result observed.
- Distinguish captured output from illustrative expected output.
- Do not infer affected or fixed versions without source, tag, changelog, or reproduction evidence.
- Preserve uncertainty as `unknown`, `unconfirmed`, or `not tested`.

## Human gates

Require human confirmation before:

- Running commands against non-local or shared infrastructure
- Publishing customer-derived evidence
- Recommending destructive recovery actions
- Declaring security impact
- Publishing affected/fixed version ranges
- Sending customer-facing content

Record required confirmation in the contract metadata with the approver, UTC timestamp, and approved scope. Agents must not approve their own work.

