# Scenario Outlines

Choose the section matching the primary reader goal. These are starting shapes, not mandatory headings. Combine or omit sections when their content is already covered; retain necessary prerequisites, decisive evidence, success criteria, and scoped cleanup. Do not add workflow frontmatter to published scenarios.

## KB — understand and diagnose

Use symptom → evidence → reasoning → recommendation. Include architecture only when it explains the failure or prevents misdiagnosis. Add triage commands and a way to confirm the resolution when useful; a KB need not become a full lab.

```markdown
# <Recognizable symptom or behavior>

## Symptoms
<Brief impact, exact error, and relevant environment/version constraints.>

## Cause and diagnosis
<Evidence-backed explanation or labeled hypothesis; useful diagnostic checks.>

## Resolution
<Fix or mitigation, its limits, and how to confirm the outcome.>

## References
<Sources supporting the explanation and relevant companion scenarios.>
```

## Runbook — execute a procedure

Keep the execution context clear. For Kubernetes, identify context, namespace, pod/container, and where Vault commands run when relevant. For cloud/IaC, identify the working directory, variables, and credentials handling. Put checkpoints within steps; add a final validation section only if it checks something additional.

```markdown
# <Operational outcome>

## Objective
<Outcome and applicability in one short paragraph.>

## Prerequisites
<Tools, permissions, target environment, and required inputs.>

## Steps
1. <Action and explicit commands.>
2. <Next action; expected output or success criteria at meaningful checkpoints.>

## Cleanup
<Remove only resources this procedure creates; include recovery where relevant.>

## References
<Official documentation and supporting scenarios.>
```

## Repro — expose one behavior

Use the smallest setup that demonstrates the issue. Distinguish the tested version from a supported affected/fixed range. Include a control, workaround, or fixed-version comparison when it meaningfully distinguishes the behavior.

```markdown
# <Behavior and triggering condition>

## Objective
<Behavior being demonstrated and relevant tested/affected versions.>

## Prerequisites
<Minimal disposable environment and required permissions.>

## Reproduce
1. <Set up the condition.>
2. <Trigger the behavior with explicit commands.>

## Result
<Expected behavior versus observed/reported evidence, or labeled illustrative output.>
<Control or fix comparison when supported by evidence.>

## Cleanup
<Scoped teardown and confirmation that scenario resources were removed.>

## References
<Evidence for behavior and any version/fix claims.>
```

## Guide — learn or integrate across phases

Start from the runbook outline. Identify the audience and scope in the objective, add only necessary conceptual context, and organize steps into phases with checkpoints. Split out a KB or repro only when it serves a distinct reader goal and is within scope.

## Script — automate a repeatable task

Read [script guidance](../references/scripts.md). Use a script when repetition or error-prone setup justifies automation; keep short teaching procedures as explicit commands. Place helpers beside the scenario with lowercase kebab-case `.sh` names. Document usage, environment variables, expected results, and cleanup in the header or companion scenario.
