# IBM Bob - How to Create and Use Skills with Templates

## Overview

If you're new to IBM Bob and want to create reusable skills for your project, this KB provides a simple template and recommended pattern to get you started. It is intended as a lightweight reference for sharing example skill files with teammates, not as a deep workflow guide. If you need more information about how to use skills in the IBM Bob IDE, please refer to the official documentation linked at the end of this KB.

A "skill" is a reusable instruction file that can be invoked by the AI to perform a specific task. Skills are defined by a `SKILL.md` file that includes metadata, instructions, and steps for the AI to follow. In a skill, you can reference files, tools, commands, and other helpful context. By creating clear, descriptive, and detailed skills, you improve the AI's chances of successfully completing the task and producing the desired output. Skills can also be shared across projects and teams, especially for common tasks like replying to a customer or diagnosing an issue.

## Introduction

In this KB, I want to introduce skills at a very beginner-friendly level, showing:

- what the minimum `SKILL.md` file should look like
- where the files should live in a repository
- how to keep Bob examples separate from other AI tool adapters

If you're looking for more advanced tips, please feel free to reach out. 

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

In this repo, I've created very basic templates of sample skills and placed them in `ai-tools/ibm-bob-sample/.bob/skills/`. Each skill has a `SKILL.md` file with instructions and steps for the AI to follow. You can use these as a starting point for creating your own skills, or as examples to share with your team.

- [Customer Reply Skill Template](../ai-tools/.bob/skills/customer-reply/SKILL.md)
- [Diagnose Issue Skill Template](../ai-tools/.bob/skills/diagnose-issue/SKILL.md)
- [Find Vault Bugs Skill Template](../ai-tools/.bob/skills/find-vault-bugs/SKILL.md)


For any repo, a practical pattern is:

If you want Bob to discover these automatically in a real repo, place them at the repo root under `.bob/skills/`.

- skills/instructions: `.bob/skills/`
- one folder per skill: `customer-reply/`, `diagnose-issue/`, `find-vault-bugs/`

This keeps the Bob examples easy to browse while making it obvious that they are templates or adapter skins rather than the primary source of truth.

## Where do I go from here?

If you want to go more in-depth on skills, best practices, and what others are doing in the tech community, I recommend checking out the links below:

- [Awesome Copilot](https://github.com/github/awesome-copilot/blob/main/README.md)
- [Make My Repo AI-Ready Skill](https://github.com/github/awesome-copilot/blob/main/skills/ai-ready/SKILL.md)
- [Learning Hub: What Are Agents, Skills, and Instructions?](https://awesome-copilot.github.com/learning-hub/what-are-agents-skills-instructions/)

## References

- IBM Bob IDE docs: `https://internal.bob.ibm.com/docs/ide/features/skills`
