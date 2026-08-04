---
name: find-vault-bugs
description: Investigate suspected Vault Enterprise bugs using the local enterprise repo, official docs, issues, and git history.
---

Investigate whether a Vault Enterprise behavior is a known bug or code-path issue by searching the local vault-enterprise repo, official docs, GitHub issues/PRs, and git history to identify root code locations, candidate fixes, and the versions that contain them.

## When to use

Use this skill when the request involves any of:

- Confirmation that a Vault or Vault Enterprise behavior is a bug
- Evidence from the official code for a suspected issue in a specific subsystem or path
- A search of `vault-enterprise` for a feature, function, package, error string, or behavior
- Git history research to find the commit or PR that fixed an issue
- Version mapping: which releases are affected, which release first contains a fix, whether a fix was backported
- Correlation between an observed issue and official GitHub issues, PRs, changelog notes, or docs

Do not use for general troubleshooting from runtime evidence alone. Use `diagnose-issue` first unless the user explicitly wants source-level confirmation.

## Inputs to gather

Before concluding something is a bug, gather:

1. Vault version and edition involved.
2. Exact error string, panic, log line, API path, or behavior description.
3. The suspected feature area or subsystem (e.g. Raft, namespaces, replication, identity, JWT auth, PKI, seal, UI, plugin runtime).
4. Whether the user wants source confirmation only, or also issue/PR/version tracking.
5. If available, likely file/function names, package paths, or a narrow reproduction description.

If the exact version or symptom is missing, continue with code search if the request is still actionable, but label conclusions as provisional.

## Local repository requirements

- Primary vault-enterprise repo: `~/repos/vault-enterprise`
- Primary docs repo: `~/repos/web-unified-docs`

Use the local clone as the source of truth for implementation and git history. If the repo is missing, ask the user to confirm the correct path before making source-level claims.

## Research sources (in priority order)

1. Local `vault-enterprise` code and git history.
2. Official HashiCorp docs on `developer.hashicorp.com` and public KBs on `support.hashicorp.com`.
3. Official GitHub issues, PRs, and changelog entries in HashiCorp repositories.

Do not rely on third-party blogs, forum posts, Reddit, or Stack Overflow as proof of bug status.

## Search method

### 1. Anchor the symptom

Start with the most specific artifact available: exact error string, package/function name, endpoint, feature flag, panic text, or behavior description. Prefer exact-string search first, then broaden.

### 2. Search the local enterprise repo

Use repository search to identify the relevant implementation path. Prioritize:

- Exact string matches for errors and log lines
- Package and directory matches for the feature area
- Surrounding call sites, guards, feature flags, and version gates
- Tests that mention the same path or behavior
- TODO/FIXME comments, defensive checks added later, and enterprise-only vs OSS code paths

### 3. Search git history for fixes

Once the likely files or strings are known:

```bash
git fetch --all --tags --quiet

# Find merge commits / messages mentioning a PR or issue
git log --oneline --decorate --all --grep '#11488' -n 20

# Find every commit that added or removed an exact error string (pickaxe)
git log --oneline --all -S 'exact error string here'

# Match a regex instead of a literal string
git log --oneline --all -G 'someFunc\(.*nil'

# Show full diff of a candidate fix commit
git show <fix_sha>

# History for one file including renames with patches
git log --follow -p -- path/to/file.go

# Find when a guard/check was introduced
git blame -L 120,160 path/to/file.go

# Find commits touching a function by name
git log --oneline --all -L ':funcName:path/to/file.go'
```

When a likely fix is found, capture: commit SHA, commit subject, affected files, what changed, and whether the change is a bug fix, regression fix, guardrail, or test-only change.

### 3b. Bisect to find the introducing commit

Use `git bisect` when you know a good version and a bad version but do not yet have a candidate commit or string to search for.

```bash
git bisect start
git bisect bad <bad_ref>   # e.g. v1.17.0+ent or a SHA known to be broken
git bisect good <good_ref> # e.g. v1.14.0+ent or a SHA known to be working

# Git checks out the midpoint commit; test or inspect, then mark it:
git bisect good  # or: git bisect bad

# Repeat until git reports the first bad commit.
git bisect reset # always reset when done
```

If you can express the failure as a script that exits 0 for good and non-zero for bad, you can automate the entire run:

```bash
git bisect start <bad_ref> <good_ref>
git bisect run ./check.sh
git bisect reset
```

After bisect identifies the commit, feed its SHA into step 3 (`git show`, `git blame`, `git tag --contains`) to continue the investigation.

### 4. Map fixes to versions

Do not guess release versions. Use evidence from tags, release branches, changelog, or explicit backport PRs.

```bash
# Release tags that contain the fix commit (first few = earliest fixed releases)
git tag --contains <fix_sha> | sort -V

# Restrict to enterprise release tags only
git tag --contains <fix_sha> | grep '+ent' | sort -V

# Remote release branches that contain the fix commit
git branch -r --contains <fix_sha>

# Hard check: is the fix an ancestor of a given tag/branch?
git merge-base --is-ancestor <fix_sha> v1.21.2+ent && echo "contained" || echo "missing"

# Union tags across every commit that mentions the PR (backports are separate cherry-picks)
git log --all --format='%H' --grep '#11488' | sort -u | xargs -n1 git tag --contains | sort -u -V
```

Report versions in this order of confidence: exact fixed version confirmed → exact affected version range confirmed → candidate fixed branches only → unable to confirm.

### 5. Search official issues and docs

Check `~/repos/web-unified-docs` and official GitHub issues/PRs to confirm whether the behavior is already reported, acknowledged, documented as expected, fixed but unreleased, or fixed and released.

## Output format

Produce a single Markdown report using this structure:

```
## Question
<what you investigated>

## Search scope
- Local repo searched: `<path>`
- Code areas searched: <packages/files/terms>
- Upstream sources checked: <docs/issues/prs/changelog>

## Code evidence
- <key finding with file/function references>

## Upstream references
- <issue/pr/doc/changelog item and why it matters>

## Fix status
- Status: confirmed bug | likely bug | expected behavior | no upstream evidence yet | fix found but unreleased | fix released
- Basis: <short explanation>

## Versions
- Affected: <exact versions/ranges if proven, otherwise "unconfirmed">
- Fixed: <exact versions/ranges if proven, otherwise "unconfirmed">
- Backports: <list or "none confirmed">

## Most relevant commits
- `<sha>` - <subject> - <why it matters>

## Gaps / caveats
- <what could not be proven>

## Recommended next step
<single best next action>

## References
- `<path>:line`
- <GitHub issue/PR/changelog/doc URL>
```

## Working rules

- Prefer precise file and function references over broad summaries.
- Use fenced code blocks with explicit language tags for commands or snippets.
- Redact sensitive values with placeholders such as `<token>`, `<hostname>`, `<namespace>`.
- Never invent versions, issue numbers, PR numbers, or backport status.
- If the fixed version cannot be proven, say `unconfirmed` and explain what evidence is missing.
- If the user later wants a customer-facing response, hand off to `customer-reply`.