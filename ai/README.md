# AI Tools

Guides for IBM Bob, the Vault MCP server, and the scenario-agent workflow used in this repository.

Lab prerequisites are in the [root README](../README.md). Confirmed version-specific defects are in [KNOWN_BUGS.md](../KNOWN_BUGS.md).

Legend: `runbook` = procedural, `kb` = break-fix analysis, `repro` = focused behavior demo, `guide` = broader walkthrough, `script` = executable is the primary deliverable.

## Vault MCP Server

- [Vault MCP Server Guide](vault-mcp-server/vault-mcp-server-guide.md)
  `guide` `ai` `vault-mcp-server` `integration`
  <details>
  <summary>Details</summary>

  - Connects `vault-mcp-server` to an existing Kubernetes Vault cluster via port-forward.
  - Covers binary install, policy and token creation, and VS Code / Claude Desktop MCP client configuration.
  - Includes a policy file scoped to KV v2, mount management, and PKI operations.
  </details>

## IBM Bob

- [IBM Bob Getting Started Guide](bob/00-ibm-bob-getting-started.md)
  `guide` `ai` `bob`
  <details>
  <summary>Details</summary>

  - Learning-path overview for new IBM Bob users, with links to the first three recommended guides.
  - Covers installation, project instructions, and skills as a progressive onboarding flow.
  </details>

- [IBM Bob Guide #1 - Install Bob, Bobshell, and Open Your First Repository](bob/01-install-ibm-bob-guide.md)
  `guide` `ai` `bob`
  <details>
  <summary>Details</summary>

  - Step-by-step setup guide for downloading Bob, installing bobshell, opening a repository, and reviewing usage analytics.
  - Includes references for Bob IDE quickstart, Bob Shell docs, and Bob token guidance.
  </details>

- [IBM Bob Guide #2 - Create AGENTS.md and Project Rules](bob/02-create-agents-guide.md)
  `guide` `ai` `bob`
  <details>
  <summary>Details</summary>

  - Beginner guide for creating a repo-level `AGENTS.md` file and teaching Bob how to work in a project.
  - Covers starter examples, project-specific rules, `/init`, and mode-specific instruction files.
  </details>

- [IBM Bob Guide #3 - Skills and Templates Guide](bob/03-create-skills-guide.md)
  `guide` `ai` `bob`
  <details>
  <summary>Details</summary>

  - Beginner-friendly guide for understanding Bob skills, including layout, minimum file format, and sample templates.
  - Serves as Guide #3 in the Bob learning path after installation and project instruction setup.
  </details>