# Reply Examples and Prompt Walkthroughs

These illustrative inputs and outputs demonstrate drafting decisions, not observed customer incidents or executed commands. The outer `text` fence is the copyable reply wrapper. Triple-backtick snippets inside it remain part of the body.

## Sparse Context: Draft Instead of Blocking

Prompt: “Draft an acknowledgement. The customer says a Vault request returns permission denied. We have no other details.”

Decision: Acknowledge the reported error and request the failing operation. A storage backend, full configuration, and version questionnaire are unnecessary for this reply.

````text
Thank you for reporting the `permission denied` error. Could you share the failing command or request path and the complete error response, with tokens, secret values, hostnames, and addresses redacted?
````

## Read-only Diagnostic Command: Safe Nested Fences

Prompt: “Draft a reply asking for the sealed state, Vault server version, and storage type. The customer already has their CLI connection settings configured for the affected server.”

Decision: Request a supported status command without assuming the storage backend or embedding credentials. Limit the returned fields to the question being answered.

````text
Please run this against the affected Vault server using your existing CLI connection settings:

```bash
vault status
```

Share the `Sealed`, `Version`, and `Storage Type` fields from the output. If the command cannot connect, please share the error with hostnames and addresses redacted.
````

Check: The outer fence has four backticks and the inner command fence has three. Both opening fences have language tags. The command is a request for the customer, not an action performed by the drafting agent.

## Bug Requested, Filing Unconfirmed

Prompt: “Write a bug update. Our notes only say the behavior may be a defect; reproduction and filing are not confirmed.”

Decision: Communicate uncertainty. Do not select the confirmed-filing pattern or promise engineering action or a release.

````text
The behavior may indicate a defect, but the cause has not been confirmed. Could you share the steps that trigger it and the complete error response, with sensitive values redacted?
````

## Confirmed Filing, No Verified Fix

Prompt: “We filed a bug for the failed update operation. Draft an update. There is no verified workaround or released fix in the case evidence.”

Decision: Report only the supplied filing status. Absence of evidence for a fix is not proof that no fix exists; omit fix and ETA claims.

````text
A bug report has been filed for the failed update operation you reported.
````

## Resolution and Closure Are Different Facts

Prompt: “Draft a closure reply. The customer confirmed that the corrected policy resolved the permission denied error. Do not include a signature.”

Decision: Acknowledge confirmed recovery. A request for closure wording does not establish an actual ticket status change or reopening policy.

````text
Thank you for confirming that the corrected policy resolved the `permission denied` error.
````

## Missing Facts That Change Remediation

Prompt: “Draft the commands to recover the customer's sealed Vault cluster. We do not know its seal configuration or have a recovery plan.”

Decision: Draft a focused customer-facing question instead of guessing an unseal or recovery procedure. Do not request unseal keys or recovery keys.

````text
Before recommending recovery steps, could you confirm whether Vault uses Shamir sealing or auto-unseal and share the relevant startup error with sensitive values redacted? Please do not send unseal keys, recovery keys, or credentials.
````

## Negative Trigger

Prompt: “Find the function that causes this Vault error and identify the fix and affected releases.”

Decision: Use `find-vault-bugs`; do not produce a customer reply. If the user later asks for a customer update, draft it from the resulting evidence and preserve any version uncertainty.
