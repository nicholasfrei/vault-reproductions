# Scenario Shell Scripts

Read when creating, changing, or reviewing a shell script or substantial embedded shell sequence.

- Use `#!/usr/bin/env bash` and `set -euo pipefail` for Bash scripts. State purpose, prerequisites, and where the script runs in a short header.
- Prefer linear, explicit commands. Introduce functions or argument parsing only when they improve a genuinely repeated or multi-mode workflow.
- Check required binaries with `command -v` and validate inputs before changes. Check the Vault target/authentication requirements and Kubernetes context when applicable; do not require credentials for operations that do not need them.
- Quote expansions, handle unset optional variables, and report actionable errors with nonzero exit status. Handle documented nonzero command outcomes explicitly rather than masking failures with `|| true`.
- Make rerun behavior intentional: detect existing mounts/resources and distinguish an already-completed step from a failed operation.
- Accept secrets through the environment or secure input. Avoid printing tokens, unseal keys, or other credentials. Refuse to overwrite existing sensitive output; use restrictive permissions before writing secret-bearing files to ignored locations.
- Use temporary directories for disposable material and cleanup traps where appropriate. Keep persistent lab resources long enough to inspect the result; provide explicit teardown scoped to resources created by the script.
- For `kubectl exec`, identify namespace, pod, and container; use `-i` when piping input. State whether commands run locally or in the container.
- Print brief progress for long waits and one useful diagnostic hint on failure. Inspect command results or resulting state before reporting success.
- Use existing scenario dependencies. Run `bash -n` and ShellCheck when available, followed by the smallest relevant behavior check on an authorized disposable target.

Minimal starting shape; replace placeholders with scenario-specific checks and commands:

```bash
#!/usr/bin/env bash
# <Purpose, prerequisites, and execution environment.>
set -euo pipefail

command -v vault >/dev/null 2>&1 || {
  echo "vault CLI is required" >&2
  exit 1
}

# <Validate inputs and target, then run explicit commands and inspect results.>
# <Provide scoped cleanup for resources created here.>
```
