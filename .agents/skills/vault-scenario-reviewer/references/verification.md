# Focused Verification

Use for author checks and review. Select checks by what changed, not by a fixed lab checklist.

| Change | Applicable checks |
| --- | --- |
| Wording, headings, or links | Inspect the diff for changed meaning, check changed links and formatting, and run `git diff --check`. |
| Version, fix, or explanatory claim | Inspect applicable documentation, source/tag, changelog, or reproduction evidence; distinguish tested versions from release-wide claims. |
| Commands, configuration, or script behavior | Check syntax, prerequisites, and inputs; exercise the affected behavior and cleanup on an authorized disposable target. |
| New repro | Observe the triggering condition, decisive result, and cleanup; include a control or fix comparison when needed to establish the claim. |
| Index or Known Bugs entry | Verify relative paths, topic placement, entry format, duplication, and the supporting scenario/version evidence. |

## Evidence

- Use existing results when they cover the current files, relevant environment/version, and claimed behavior. Check whether intervening edits invalidate them; an old `passed` label alone is insufficient.
- For checks you run, capture the command, exit status, relevant redacted output or resulting state, and cleanup outcome. Keep only decisive excerpts in the handoff; reference longer evidence when available.
- Preserve legitimate nonzero exit codes when a test intentionally exposes an error. Verify the expected error or state rather than treating any failure as a successful repro.
- A script printing expected text does not prove that the underlying operation happened. Inspect actual state or command results.
- For scripts, run `bash -n` and ShellCheck when available. Neither proves runtime behavior.
- For documentation-only work, validate the claims against sources; do not build a lab just to populate a report.
- Repeat checks only when edits, failures, stale evidence, or an unresolved concern justify it. Record skipped relevant checks and why they remain unverified.

## Execution boundaries

Apply `AGENTS.md` execution rules. Confirm the target before commands that change state, and check prerequisites before launching a lab. Do not execute destructive examples against the user's current shell context by assumption. If a required environment or authorization is unavailable, finish safe static checks and name the runtime evidence gap.
