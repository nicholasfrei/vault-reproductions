# IBM Bob Guide #3 - Skills and Templates Guide

## Overview

A "skill" is a reusable instruction file that can be invoked by the AI to perform a specific task. Skills are defined by a `SKILL.md` file that includes metadata, instructions, and steps for the AI to follow. In a skill, you can reference files, tools, commands, and other helpful context. By creating clear, descriptive, and detailed skills, you improve the AI's chances of successfully completing the task and producing the desired output. 

Skills can also be shared across projects and teams, especially for common tasks like replying to a customer or diagnosing an issue. By making the skill more detailed, you are preventing the AI from giving inaccurate or unhelpful responses that come from vague prompts. It also helps prevent unncessary "course correction" prompts.

## Prerequisites

- Bob is installed and working
- You have reviewed [IBM Bob Guide #2 - Create AGENTS.md and Project Rules](./02-create-agents-guide.md)
- You understand the basics of how Bob uses repository instructions

## Layout and Minimum File Format

IBM Bob project skills are stored under a repo-local `.bob/skills/` directory, with one folder per skill and a `SKILL.md` file inside each skill directory.

Minimal layout:

```text
<repo>/
└── .bob/
    └── skills/
        └── <skill-name>/
            └── SKILL.md
```

Minimal skill file format:

```md
---
name: example-skill
description: Short sentence explaining when Bob should use this skill.
---

# Example Skill

Use this skill when the user asks for <task type>.

## Steps

1. Gather the required context.
2. Follow the workflow for the task.
3. Produce the expected output format.
```

## Sample Skills to Reference

In this repo, I've created very basic templates of sample skills and placed them in `ai-tools/.bob/skills/`. Each skill has a `SKILL.md` file with instructions and steps for the AI to follow. You can use these as a starting point for creating your own skills, or as examples to share with your team.

- [Customer Reply Skill Template](../ai-tools/.bob/skills/customer-reply/SKILL.md)
- [Diagnose Issue Skill Template](../ai-tools/.bob/skills/diagnose-issue/SKILL.md)
- [Find Vault Bugs Skill Template](../ai-tools/.bob/skills/find-vault-bugs/SKILL.md)

If you want Bob to discover these automatically in a real repo, place them at the repo root under `.bob/skills/`.

- skills/instructions: `.bob/skills/`
- one folder per skill: `customer-reply/`, `diagnose-issue/`, `find-vault-bugs/`
- a `SKILL.md` file in each skill folder with the instructions and steps for that skill

This keeps the Bob examples easy to browse while making it obvious that they are templates or adapter skins rather than the primary source of truth.

## How to Create Your First Skill

Use this simple workflow when creating a new skill:

1. Pick a repeatable task Bob should handle well.
2. Create a folder under `.bob/skills/<skill-name>/`.
3. Add a `SKILL.md` file with a clear `name` and `description`.
4. Write short instructions that tell Bob when to use the skill and what output to produce.
5. Test the skill in a repository and refine the instructions if Bob's behavior is too vague.

Good beginner skill ideas include:

- draft a customer reply
- summarize logs or errors
- create a documentation outline
- review a pull request for a specific type of risk

The best skills are narrow enough to be reliable and specific enough to drive consistent results.

## Validation

You have completed Guide #3 when you can do all of the following:

- explain the purpose of a Bob skill
- identify the `.bob/skills/` directory structure
- create a simple `SKILL.md` file
- point to sample skill templates for future reuse

## Where do I go from here?

If you want to go more in-depth on skills, best practices, and what others are doing in the tech community, I recommend checking out the links below:

- [Awesome Copilot](https://github.com/github/awesome-copilot/blob/main/README.md)
- [Make My Repo AI-Ready Skill](https://github.com/github/awesome-copilot/blob/main/skills/ai-ready/SKILL.md)
- [Learning Hub: What Are Agents, Skills, and Instructions?](https://awesome-copilot.github.com/learning-hub/what-are-agents-skills-instructions/)

## References

- [IBM Bob IDE docs](https://internal.bob.ibm.com/docs/ide/features/skills)
- [#1 - IBM Bob - Getting Started Guide](./01-install-ibm-bob-guide.md)
- [#2 - IBM Bob - Create AGENTS.md and Project Rules](./02-create-agents-guide.md)
