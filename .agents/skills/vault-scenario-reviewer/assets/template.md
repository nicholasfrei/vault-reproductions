# Review Output

Use this shape in chat. Save it only when requested or needed for a handoff. Replace placeholders; use `None.` when there are no findings. Name reviewed paths in the decision and check evidence without repeating the scenario. Do not add scoring tables or workflow metadata.

```markdown
## Decision
<ready | needs-changes | blocked> — <reviewed paths and brief reason>.

## Findings
- <Blocking or optional> — <path:line or section>: <issue, consequence, and correction>.

## Checks
- <Check performed or evidence inspected and result.>
- <Unrun required check and specific blocker, when applicable.>
```
