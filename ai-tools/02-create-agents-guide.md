# IBM Bob Guide #2 - Create AGENTS.md and Project Rules

## Overview

Once Bob is installed and pointed at a repository, the next step is giving it clear project instructions. In Bob, `AGENTS.md` acts as a source of truth for how the AI should behave in a codebase. A good `AGENTS.md` file helps Bob follow the right workflow, respect repo conventions, and avoid unnecessary mistakes. It often includes repo structure, style guidance, and other project rules so the AI can work with better context.

## Prerequisites

- Bob is installed and working
- You have a repository open in Bob IDE or available in bobshell
- You completed [IBM Bob Guide #1 - Install Bob, Bobshell, and Open Your First Repository](./01-install-ibm-bob-guide.md)

## What `AGENTS.md` Is

`AGENTS.md` is a repository-level instruction file that tells Bob how to behave for that project. Think of it as the project's AI operating guide.

Common things to include:

- coding conventions
- testing expectations
- folder ownership or boundaries
- documentation rules
- git and review preferences
- environment-specific warnings or limitations

Bob uses this file as durable context, which is why it is often described as a source of truth for the project.

Official reference:

- [Explore `AGENTS.md` files](https://internal.bob.ibm.com/docs/ide/getting-started/tutorials/start-a-project#explore-agentsmd-files)

## Step 1: Add a Starter `AGENTS.md` File

Create an `AGENTS.md` file at the repository root.

Minimal example:

```md
# Project Instructions

## Overview

This repository contains internal tooling and documentation.


## Structure
. 
├── docs/
├── scripts/
├── runbooks/
└── README.md

## Working Rules

- Prefer small, focused changes.
- Do not modify unrelated files.
- Follow the existing file and folder structure.
- Keep documentation examples copy/paste friendly.

## Validation

- Run the relevant tests before finishing.
- Call out anything that could not be validated locally.

## Safety

- Do not commit secrets.
- Do not run destructive commands unless explicitly requested.
```

This is only a starting point. The best `AGENTS.md` files are specific to the repo and reflect the real standards your team cares about.

## Step 2: Use `/init` to Generate More Detailed Instructions

Bob can help bootstrap instructions for a project. When you run `/init`, Bob can create additional instruction files and scaffold more specific guidance.

Official references:

- [Start a project tutorial](https://internal.bob.ibm.com/docs/ide/getting-started/tutorials/start-a-project)
- [Mode-specific `AGENTS.md` files](https://internal.bob.ibm.com/docs/ide/getting-started/tutorials/start-a-project#mode-specific-agentsmd-files)

This is useful when you want to move beyond a single top-level instruction file and tailor behavior for different modes or workflows. (There are also options to create custom modes. This will be covered in a later guide.)

## Step 3: Review the Generated Instructions

If you use `/init`, do not assume the generated content is perfect. Review it like any other project artifact. Make sure it reflects the real project structure and goals of your repository. What works for a SWE repo may not fit a TSE repo, so keep the instructions aligned to the actual work being done there.

## Step 4: Test the Results with a Small Task

After creating `AGENTS.md`, try a simple prompt in the repo.

Example:

- ask Bob to summarize the repository structure

Bob will use your `AGENTS.md` instructions to understand how the repo is organized and generate a response. This is a good way to validate that the instructions are clear and that Bob is following them.

## Next Step

Continue to [IBM Bob Guide #3 - Skills and Templates Guide](./03-create-skills-guide.md) to learn how to create reusable Bob skills.

## References

- [Explore `AGENTS.md` files](https://internal.bob.ibm.com/docs/ide/getting-started/tutorials/start-a-project#explore-agentsmd-files)
- [Start a project tutorial](https://internal.bob.ibm.com/docs/ide/getting-started/tutorials/start-a-project)
- [Mode-specific `AGENTS.md` files](https://internal.bob.ibm.com/docs/ide/getting-started/tutorials/start-a-project#mode-specific-agentsmd-files)
- [IBM Bob IDE docs](https://internal.bob.ibm.com/docs/ide)
