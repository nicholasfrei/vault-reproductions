# Jira style examples

These notes summarize three reference ticket descriptions reviewed on 2026-10-07. They illustrate writing style, not current issue status, independently verified behavior, or evidence for a new bug. Customer information and environment identifiers are omitted.

## Patterns from the reference tickets

| Reference | Useful pattern | How to apply it |
| --- | --- | --- |
| [VAULT-51195](https://hashicorp.atlassian.net/browse/VAULT-51195) — LDAP static-role manual rotation | Contrasts the API-reported next rotation with the original schedule; a minute-2/minute-10/minute-12 example makes the discrepancy concrete. | Explain a timing mismatch with one short timeline. Only claim a second active job if current evidence supports that cause. |
| [VAULT-46717](https://hashicorp.atlassian.net/browse/VAULT-46717) — database UI omits `rsa_private_key` credentials | Identifies the affected UI pages, the empty result from reveal/copy actions, ordered navigation steps, and CLI/API workaround. | Name the affected credential field and separate the UI symptom from backend credential retrieval. Distinguish a reproduced version from speculation about when the bug began. |
| [VAULT-49661](https://hashicorp.atlassian.net/browse/VAULT-49661) — `vault recover` panics without a path | Contrasts a handled invalid-path error with a missing-path panic and provides the decisive error. | Lead with the input condition and failure; keep only the relevant error/frame rather than a full stack trace. |

Use their specificity and brevity. Normalize formatting to repository conventions: language-tagged blocks, separate commands/output, no bold text, and no customer details or environment identifiers.

## End-to-end example: CLI panic

### Supplied evidence

Sanitized excerpt adapted from VAULT-49661:

- The report says `vault recover` returns an API error for an invalid path but panics when no positional path is supplied.
- The supplied description does not state the Vault version.
- The broader reproduction loads a Raft snapshot, obtains its snapshot ID, and invokes recovery without a path.
- Decisive command:

```bash
vault recover -snapshot-id "<snapshot_id>"
```

- Reported output:

```text
panic: runtime error: index out of range [0] with length 0
```

### Draft output

## Title

Vault recover command panics when no path is provided

## Description

The supplied report shows that `vault recover` panics when the positional path argument is omitted. An invalid path produces a handled API error, but a missing path terminates the CLI with a panic.

Expected behavior: Validate the required path argument and return a CLI usage error instead of panicking.

Vault version: not provided. Not independently reproduced.

Reported reproduction: After loading a Raft snapshot and obtaining its snapshot ID, run recovery without a path:

```bash
vault recover -snapshot-id "<snapshot_id>"
```

Reported output:

```text
panic: runtime error: index out of range [0] with length 0
```

### Why this example works

The title names the command, symptom, and trigger. The description preserves the reported observation without inventing a version or claiming independent validation. It explains the expected outcome and includes only the decisive command and error.
