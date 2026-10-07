# Jira draft template

Use the two top-level fields below. Replace placeholders with supported facts or explicit unknowns. Remove these instructions from the output.

Keep the description order: observed behavior/impact, expected behavior, then supporting evidence. Combine short sections into paragraphs when that reads better. Omit optional sections without evidence. This template maps directly to Jira fields; do not add YAML frontmatter to the ticket.

## Title

<component or command> <observable failure> <triggering condition, if known>

## Description

<Observed behavior and practical impact.>

Expected behavior: <What should happen under the same conditions.>

Vault version: <tested version/edition, or not provided>.

### Reproduction or observation

<Minimal supported steps and relevant configuration, or the reported observation if steps are unavailable. Identify whether this was reported or independently reproduced.>

<Include commands and decisive output in separate language-tagged blocks when available.>

### Workaround (optional)

<Supported workaround and limitations; qualify any untested proposal.>

### Additional evidence (optional)

<Relevant source references or supporting links. Distinguish confirmed findings from suspected causes.>
