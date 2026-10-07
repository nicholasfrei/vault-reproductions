# Git Investigation Reference

Use these recipes after identifying the relevant repository and question. Replace quoted placeholders before running commands. Git is required; a shell is used for these examples. Builds and bisect predicates may require additional dependencies from the target repository. Use Git's built-in version sorting rather than assuming `sort -V` is available.

## Establish a Baseline

Run commands against the explicit repository, regardless of the session's working directory:

```bash
repo="$HOME/repos/vault-enterprise"
git -C "$repo" rev-parse --show-toplevel
git -C "$repo" status --short
git -C "$repo" rev-parse HEAD
git -C "$repo" rev-parse --is-shallow-repository
git -C "$repo" tag --list --sort=version:refname
```

Resolve the reported build/tag without checking it out. Do not manufacture an enterprise tag from a version string; identify the available matching ref first.

```bash
ref='<reported-version-ref>'
git -C "$repo" rev-parse --verify "${ref}^{commit}"
git -C "$repo" grep -n -F -e '<exact error string>' "$ref" --
git -C "$repo" show "${ref}:<path/to/file.go>"
```

`git grep` exit `1` means no match, not a failed investigation. Distinguish that from command errors. Ref-based reads use committed content; working-tree search may include local edits.

If a needed remote ref is unavailable, inspect the configured remotes and fetch only the relevant source. Do not print credential-bearing remote URLs into reports. For example, after identifying the remote and tag:

```bash
git -C "$repo" remote
git -C "$repo" fetch '<remote-name>' tag '<tag-name>'
```

A shallow or partial clone, stale remote-tracking branches, or unavailable network can limit negative conclusions. Record that limitation rather than doing an unconditional fetch of every remote and tag.

## Search History

Narrow paths where possible. `--all` searches locally available refs; it does not query the remote server.

```bash
# Literal commit-message match: a candidate-discovery aid, not proof of a fix.
git -C "$repo" log --all --oneline --fixed-strings --grep='<issue-or-PR-marker>'

# Pickaxe: changes in the number of occurrences of a literal string.
git -C "$repo" log --all --oneline -S '<exact error string>' -- '<path/to/file.go>'

# Diff lines matching a regular expression, even if occurrence counts are unchanged.
git -C "$repo" log --all --oneline -G 'someFunc\(.*nil' -- '<path/to/file.go>'

# Follow one file's history from the relevant ref.
git -C "$repo" log --follow -p "$ref" -- '<path/to/file.go>'
git -C "$repo" blame -L 120,160 "$ref" -- '<path/to/file.go>'

# Line history takes one starting revision; do not combine it with --all.
git -C "$repo" log -L ':funcName:path/to/file.go' "$ref"
```

If function-name detection fails (for example, a Go method is not recognized by the configured diff driver), inspect the file and use `-L '120,160:path/to/file.go'` with the correct range at that ref.

Inspect the candidate's metadata and patch, plus its parent implementation and relevant tests:

```bash
fix='<candidate-fix-sha>'
git -C "$repo" show --format=fuller --stat "$fix"
git -C "$repo" show "$fix" -- '<path/to/file.go>'
git -C "$repo" show "${fix}^:<path/to/file.go>"
```

For a merge, inspect the relevant parent diff explicitly; a default merge display may hide the change. Record the full SHA, subject, files, causal change, and any prerequisite commits. A blame result identifies line attribution, not necessarily the root-cause introduction.

## Verify Versions and Backports

List containment candidates:

```bash
git -C "$repo" tag --contains "$fix" --sort=version:refname
git -C "$repo" branch -r --contains "$fix"
```

These lists establish ancestry only. Version sorting is a navigation aid, not a release-status or earliest-fixed-release determination.

Check a particular tag while preserving Git's error distinction:

```bash
release='<release-tag>'
if git -C "$repo" merge-base --is-ancestor "$fix" "$release"; then
  echo 'Fix commit is an ancestor; inspect release code and publication evidence.'
else
  result=$?
  case "$result" in
    1) echo 'Fix commit is not an ancestor; check for an equivalent backport.' ;;
    *) echo "Ancestry check failed (exit $result); containment is unknown." >&2 ;;
  esac
fi
```

For each requested release line:

1. Locate candidate backports using official PR links, commit messages, and changes to the relevant code. Message matches may omit backports or include unrelated changes.
2. Compare each candidate's diff and resulting implementation with the original fix. Account for adapted patches and dependencies. Patch similarity alone does not prove equivalent behavior.
3. Check the backport SHA against that line's release tags. Absence of the original SHA is not evidence that a cherry-picked fix is absent.
4. Inspect release code/tests for the effective fix and any reverts. Confirm edition, build variant, and plugin applicability.
5. Check official release notes or release records to establish publication. A remote branch or tag alone does not establish a shipped stable binary.
6. Check earlier relevant stable releases before calling a release the first fixed version. Otherwise say “verified fixed in” the checked release, with earliest release unconfirmed.
7. Establish affected versions from reproduced behavior or a demonstrated version-specific faulty path. Use an affected range only when its boundaries and continuity are supported.

## Optional Bisect

Use bisect only with a stable symptom predicate and known good/bad revisions. First verify that the predicate distinguishes those endpoints under comparable configuration. A source-only predicate identifies a source change; it does not demonstrate runtime behavior.

Use a dedicated disposable clone or worktree, with a clean working tree, so bisect does not move the user's active checkout. Keep the predicate outside the bisected tree so older revisions do not remove it. Never discard local changes to make bisect run.

For interactive bisection:

```bash
bisect_repo='<absolute-path-to-dedicated-checkout>'
git -C "$bisect_repo" status --short
git -C "$bisect_repo" bisect start '<known-bad-ref>' '<known-good-ref>'
```

Test the selected revision, then run exactly one classification command per iteration:

```bash
git -C "$bisect_repo" bisect good
```

Use `bisect bad` only for the same reproduced symptom and `bisect skip` for an untestable revision. Repeat until complete, capture `git bisect log`, and always run `git bisect reset` afterward, including after interruption or failure.

For automated bisection, define the predicate's exit codes correctly:

| Exit code | Meaning |
|---|---|
| `0` | Good: symptom absent under the validated test |
| `1`–`127`, except `125` | Bad: the specific symptom reproduced |
| `125` | Skip: this revision cannot be tested reliably |
| Other exit codes | Abort: predicate or infrastructure failure |

Shell command-not-found/not-executable failures (`127`/`126`) would count as bad. Check prerequisites explicitly and translate unrelated failures into skip or abort. Do not blindly propagate a build command's exit code as the symptom result.

After provisioning the dedicated checkout and reviewing the predicate, run this as a shell block. The subshell limits directory and trap changes to this operation:

```bash
(
  set -euo pipefail
  cd '<absolute-path-to-dedicated-checkout>'
  trap 'git bisect reset' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  git bisect start '<known-bad-ref>' '<known-good-ref>'
  git bisect run '<absolute-path-to-validated-check.sh>'
  git bisect log
)
```

Preserve the result and predicate details in the investigation report. If skipped revisions leave multiple candidates, report the candidate set rather than claiming one introducing commit. Inspect the resulting change before drawing causal or release conclusions.
