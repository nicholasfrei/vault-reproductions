# Repository Conventions

The root `AGENTS.md` is authoritative. This file identifies the conventions that scenario agents must actively apply.

## Placement and naming

- Search `README.md` and neighboring topic directories before adding content.
- Place the scenario under the narrowest existing domain, such as `auth/jwt/`, `secrets/kv/`, or `sys/raft/`.
- Use `*-repro.md`, `*-runbook.md`, `*-kb.md`, or `*-guide.md` according to the primary intent.
- Treat scripts as supporting files unless the script itself is the indexed scenario.
- Do not rename or reorganize unrelated content.

## Content

- Write for engineers of varied Vault experience.
- Prefer explicit, copy/paste-friendly Vault CLI commands.
- Separate command blocks from expected output blocks.
- Include exact searchable errors when documenting failures.
- State version, edition, deployment, storage, and namespace assumptions.
- Include validation and cleanup whenever the scenario changes state.
- Link official documentation and upstream issues used as evidence.

## Change discipline

- Keep changes small and limited to the accepted `scenario-brief.md`.
- Require approved brief metadata before authoring and keep all handoff artifacts on the same scenario revision.
- Increment `scenario_revision` before changing scenario or supporting files.
- Match nearby file patterns before introducing a new pattern or dependency.
- Update `README.md` only after validation and review are complete.
- Preserve every existing index entry unless removal was explicitly requested.
- Do not commit, push, or add AI coauthor attribution.

