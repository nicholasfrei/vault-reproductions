# IBM Bob Guide #1 - Install Bob, Bobshell, and Open Your First Repository

## Overview

This guide helps new IBM Bob users get through the first setup steps with enough context to be productive right away. It covers downloading Bob, installing bobshell, opening a repository in the Bob IDE, and understanding where to check usage and token information.

## Prerequisites

- Access to the internal IBM Bob download page
- Access to the Bob IDE docs and Bob Shell docs
- Locally cloned `vault-enterprise` repository

## Step 1: Download Bob

Use the official Bob download link:

- [Download Bob](https://ibm.biz/get-bob)

Here are the official Bob IDE docs: 

- [IBM Bob IDE Docs](https://internal.bob.ibm.com/docs/ide)

After it's downloaded, follow the prompts to login with your credentials. The application should be installed to this path: `/Applications/IBM Bob.app`

## Step 2: Install Bobshell

Install bobshell with the documented bootstrap command:

```bash
curl -fsSL https://s3.us-south.cloud-object-storage.appdomain.cloud/bobshell/install-bobshell.sh | bash && bob
```

This does three things:

1. downloads and installs bobshell
2. starts Bob from the shell so you can verify the installation worked
3. you will be prompted to login with your credentials

If you want more background on shell usage, review the shell docs:

- [IBM Bob Shell Docs](https://internal.bob.ibm.com/docs/shell)

## Step 3: Open the locally cloned Vault-Enterprise Repository in Bob IDE

First, you can add this to your `~/.zshrc` to make sure `bobide` is available in your shell: 

```bash
# -- Bob IDE --
# Open IBM Bob IDE — mirrors `code .` usage.
# Usage: `bobide .`  or  `bobide /path/to/dir`
bobide() {
  "/Applications/IBM Bob.app/Contents/Resources/app/bin/bobide" "${@:-.}"
}
```

Reload the shell with `source ~/.zshrc` and then navigate to your local `vault-enterprise` repo and run `bobide .` to open that directory in the Bob IDE. You should see the Bob IDE open with the repo files visible in the left bar. 

If you run into any issues, here is the official quickstart guide:

- [Bob IDE Quickstart](https://internal.bob.ibm.com/docs/ide/getting-started/quickstart)

## Step 4: Understand Usage Analytics and Bob Tokens

As you start using Bob, it helps to know where to monitor usage and where token guidance lives.

Helpful references:

- [View Usage Analytics](https://bob.ibm.com/admin/bobalytics)
- [Bob Tokens / Bobcoins](https://internal.bob.ibm.com/docs/ide/account/bobcoins)

Key point for new users:

- internal users get 100 tokens/month 

Always check the official Bobcoins page for the current policy, limits, and pricing details rather than relying on older screenshots or team notes.

## Next Step

Continue to [IBM Bob Guide #2 - Create AGENTS.md and Project Rules](./02-create-agents-guide.md) to teach Bob how your repository works.

## References

- [IBM Bob IDE docs](https://internal.bob.ibm.com/docs/ide)
- [IBM Bob Shell docs](https://internal.bob.ibm.com/docs/shell)
- [Bob IDE quickstart](https://internal.bob.ibm.com/docs/ide/getting-started/quickstart)
- [Bob tokens / Bobcoins](https://internal.bob.ibm.com/docs/ide/account/bobcoins)
- [Bob usage analytics](https://bob.ibm.com/admin/bobalytics)
