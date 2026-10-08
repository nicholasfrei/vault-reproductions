---
title: Vault support reply patterns
doc_type: reply_templates
---

# Reply Patterns

Read only the pattern that fits the requested response. These are drafting aids, not evidence that an action occurred. Fill placeholders from supplied facts, remove inapplicable sentences, and apply the output contract in `SKILL.md`. The metadata and headings in this resource are not part of the customer body.

## General Shape

```text
<brief acknowledgement or supported status>

<next action, focused question, or necessary technical steps>

<optional specific customer-accessible reference supporting the advice>
```

Omit optional parts rather than forcing every reply into this shape. Use a greeting or signature only when appropriate to the request; never invent names. For command-containing replies, use the longer outer fence shown in `references/examples.md`.

## Acknowledgement

Use the reported symptom without claiming investigation has already started. Include a question only if needed for the next step.

```text
Thank you for reporting <symptom>. Could you share <specific missing evidence> so we can <next diagnostic purpose>?
```

## Follow-up on a Recommendation

Use only when a recommendation was actually supplied earlier. Do not assume it was attempted.

```text
Were you able to try <previously suggested step>? Please let us know the result and whether <reported symptom> still occurs.
```

## Follow-up Without a Response

Do not invent how long it has been, a closure deadline, or a resolution.

```text
Are you still experiencing <reported symptom>? If so, please share <previously requested evidence still needed>. If the issue has cleared, please confirm whether you need any further help with this case.
```

## Focused Information Request

Request only items relevant to the current question; one item may suffice.

```text
To help determine <diagnostic question>, please share:

- <specific missing detail>
- <additional detail only if needed>

Please redact credentials and sensitive values from any examples.
```

## Log Request

Specify operational or audit logs only when their relevance is established. Request a bounded excerpt rather than a full log archive by default; do not require audit logging to be enabled just to fill this pattern.

```text
Please share a redacted excerpt of <relevant log source> covering <incident window>, along with the incident timestamp and timezone. We need the entries around <specific error or event> to check <diagnostic purpose>.

Remove tokens, credentials, secret values, hostnames, and addresses before sharing.
```

If the customer needs collection instructions, consult the relevant platform-specific documentation. Candidate references to verify before including:
- [Where are my Vault logs and how do I share them with HashiCorp Support?](https://support.hashicorp.com/hc/en-us/articles/360002046068)
- [Troubleshooting Vault](https://developer.hashicorp.com/vault/tutorials/monitoring/troubleshooting-vault)

## Troubleshooting Session

Use when the engineer requested scheduling. Asking for availability does not mean a meeting has been booked.

```text
Could you share a few available times and your timezone for a troubleshooting session focused on <specific issue>?
```

## Confirmed Bug Filing

Use only when supplied evidence confirms that a bug report was filed for this behavior. Filing does not imply engineering acceptance, reproduction, a fix, or a release commitment. Add a workaround or public reference only if independently supported and relevant.

```text
A bug report has been filed for <confirmed behavior>. <supported current status or next step, if available>
```

## Confirmed Known Issue

Use only when the investigation establishes a match for the customer's circumstances. Omit affected/fixed release claims unless version-specific evidence supports them. Use customer-accessible links, not internal trackers.

```text
The investigation identified <confirmed issue> as the cause of <reported symptom>. <verified workaround or next step, if available>

Details: <verified public issue or documentation link>
```

## Closure After Confirmed Resolution

Use only when the customer or supplied evidence confirms resolution. Do not assert that the ticket is already solved, that a reply will automatically reopen it, or that the problem cannot recur.

```text
Thank you for confirming that <verified corrective action or observed recovery> resolved <reported symptom>.
```

For administrative closure without confirmed resolution, use the supplied reason and authorized intended action instead. Do not manufacture a resolution statement from silence.

## Optional Feedback Request

Append only when requested and a feedback channel is supplied. Do not predict that a survey will arrive.

```text
If you would like to share feedback on this case, please use <confirmed feedback channel>.
```
