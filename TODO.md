# TODO Runbooks / KBs to Add

- **Sentinel Policies**
  - EGP & RGP governing policies: common examples and understanding
- **Replication (Enterprise)**
  - Secondary stuck behind WAL / replication lag: diagnosis and recovery.
  - Region loss simulation and service restoration timeline.
- **Seal / Unseal**
  - Multi-seal and Seal HA: config patterns, startup order, failure modes.
  - Auto-unseal migration (Shamir → KMS/HSM) with rollback considerations.
- **Raft / Storage**
  - Integrated storage autopilot: dead server cleanup, peer replacement.
  - Snapshot/restore validation (single cluster and cross-cluster).
- **Auth Methods**
  - OIDC auth: groups claim mapping, bound claims, redirect URI issues.
  - AppRole hardening and IR: secret-id rotation, token cleanup, lease explosion (common Enterprise issue).
- **Secrets Engines**
  - KV v2: soft-delete/destroy/undelete behavior and recovery.
- **PKI**
  - Intermediate rotation, CRL/OCSP (tidy, etc.), outage mitigation.
- **Audit / Security**
  - Audit device performance impact and log integrity validation.
- **Kubernetes**
  - Vault injector webhook: cert rotation, startup ordering, mutation failures.
- **Terraform / Vault Provider**
  - Provider setup and auth patterns (token, AppRole, JWT/OIDC, Kubernetes).
  - Troubleshooting: namespaces, token expiry, policy denies, state drift.
- **Golang Custom Plugin Development**
  > *Disclaimer:* These are AI-generated ideas to explore Go and Vault plugins. Some of these ideas will be added to the repository as custom plugins in the future. I will work on these features outside 
of this repository and implement them in my own time.

  - **WASM secret transformer** — Transform/redact secrets at read time via configured WASM module. (Go plugin architecture, wazero, sandboxing; field masking, format conversion, tenant-specific shaping.)
  - **Ephemeral DB credential bridge** — Short-lived creds for Turso/LibSQL/PocketBase-style backends; revoke on lease expiry. (HTTP clients, lease management; edge/serverless DB access.)
  - **Temporal identity auth** — mTLS → validated workload identity → SPIFFE-style doc or scoped token. (X.509, trust chains, custom auth; bridge legacy mTLS to workload identity.)
  - **TOTP + hardware key assertion** — Challenge-response login with local/hardware key + TOTP before token. (Stateful auth, crypto verification; stronger operator/workload login.)
  - **Immutable ledger audit backend** — Hash-chained append-only log / Merkle tree; anchor root to external system. (Concurrency, durable pipelines; tamper-evident audit for regulated envs.)
  - **LLM session broker** — Short-lived agent session bundles; expire/revoke after task or prompt cycle. (Lease-aware issuance, response shaping; controlled secret exposure for AI agents.)