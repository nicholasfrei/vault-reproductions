---
name: document-reference
description: Reference HashiCorp Vault documentation. Supports cross-product issues (Terraform, Consul, Nomad, Boundary).
---

Produce a structured documentation report for a HashiCorp Vault question. Vault is the primary subject; pull from other HashiCorp product docs (Terraform, Boundary, Nomad, Consul, Packer, Waypoint) only when the issue spans products.

## Required evidence (ask if missing)

Before replying, confirm you have:

1. Vault version (`vault status` / `vault version`) and edition (CE vs Enterprise).
2. Storage backend (assume Integrated Storage / Raft unless stated otherwise).
3. Deployment shape (single node, HA cluster, replication, performance standby, DR).
4. Recent changes (upgrades, config changes, policy changes, infra changes, scale events).
5. Reproducibility (always, intermittent, first time, after specific action).
6. For cross-product issues: the other product's version and the relevant resource/config.

Do not invent or assume specific versions, backends, or configurations.

## Starting Point

Use the internally cloned repos in `~/repos/` before going to the web. More info about the internal-tools are including in `.agents/instructions/internal-tools.md` 

## Web research policy

When the internal repos are unavailable or insufficient, use the WebFetch tool to consult official HashiCorp documentation:

Allowed domains:

- `developer.hashicorp.com` — primary docs, API docs, tutorials, changelogs
- `support.hashicorp.com` — public KB articles
- `github.com/hashicorp/vault` (and sibling repos) — issues, changelog, source — only to confirm a known bug or behavior, never as the sole source for a fix

Do not cite blogs, Stack Overflow, Reddit, Medium, or third-party sites. If WebFetch returns a redirect, retry with the redirect URL.

### Useful starting URLs

Vault docs:

- Vault docs: https://developer.hashicorp.com/vault/docs
- Vault API: https://developer.hashicorp.com/vault/api-docs
- Vault troubleshooting: https://developer.hashicorp.com/vault/tutorials/monitoring/troubleshooting-vault
- Vault changelog: https://github.com/hashicorp/vault/blob/main/CHANGELOG.md

Other product docs: 

- Terraform Vault provider: https://registry.terraform.io/providers/hashicorp/vault/latest/docs
- Terraform docs: https://developer.hashicorp.com/terraform/docs
- Boundary docs: https://developer.hashicorp.com/boundary/docs
- Nomad docs: https://developer.hashicorp.com/nomad/docs
- Consul docs: https://developer.hashicorp.com/consul/docs
- Support KB: https://support.hashicorp.com/hc/en-us

## Output format

Produce a single Markdown report using this structure:

```
## Question
<one or two sentences paraphrasing the original question>

## Evidence on hand
- Vault version/edition: <value or "unknown">
- Storage backend: <value or "assumed Raft">
- Deployment Info: <value or "unknown">
- Error or Question: `<string>`
- Recent changes: <list or "none reported">
- Reproducibility: <value or "unknown">

## Body
<Info about the question, docs, conclusion, etc.>

## References
- [Title](https://developer.hashicorp.com/...)
```

## Scope and constraints

- Reference only.
- No architectural design suggestions. If the root cause is structural, name it and point to relevant docs.
- Never invent a Vault version, error string, or config value. If unknown, ask or mark as "unconfirmed."
- Never include public IPs, hostnames, customer names, tokens, or other sensitive values. Use placeholders such as `<hostname>`, `<token>`, `<namespace>`.
- No ETAs for fixes or releases.
- Use fenced code blocks with explicit language tags (`bash`, `hcl`, `json`, `text` for log output).
