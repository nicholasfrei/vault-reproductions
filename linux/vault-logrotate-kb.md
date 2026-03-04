# Vault Logrotate Guidance for Systemd Deployments

## Overview

This KB explains practical logrotate guidance for Vault environments where Vault writes to files under `/var/log/vault` and runs as a `systemd` service.

It is intended to help teams prevent outages caused by log partitions filling up, and to clarify what each common logrotate parameter does in real-world Vault scenarios.

## Problem Pattern

A frequent failure mode looks like this:

- Vault remains `active (running)` in `systemd`.
- `/var/log/vault` reaches 100% usage.
- Vault API and UI stop responding due to failed log writes.
- Rotation either does not run as expected or fails during rotation.

This is commonly tied to one or more of the following:

- Rotation schedule assumptions do not match how `logrotate` is actually invoked.
- Conflicting or misunderstood directives (`daily`, `size`, `minsize`).
- `copytruncate` behavior on very large active logs and constrained disk.
- Missing reload signaling for Vault after a rename-based rotation.

## Scope Disclaimer

Logrotate is an operating system facility, not a Vault-managed feature. Validate final configuration choices with your Linux platform team, and test in non-production first.

## How Logrotate Actually Runs

`logrotate` is typically executed by cron or a systemd timer once per day on many distributions.

Important implication:

- If you expect "near real-time" rotation on size thresholds, ensure `logrotate` is scheduled frequently enough (for example hourly), or large files may exceed your expected size for part of the day.

Also note:

- `logrotate` is not a real-time daemon watching file growth.
- Rotation decisions occur only when the utility is invoked.

## Directive Reference (What Each Parameter Does)

Below are the most relevant directives seen in Vault deployments.

### Frequency and trigger directives

- `daily` / `weekly` / `monthly`
  - Time-based trigger window.
  - Rotation is considered when logrotate runs during that period.

- `size <value>`
  - Rotate when file size is greater than the specified threshold.
  - This option is mutually exclusive with time interval directives (`daily`, `weekly`, `monthly`, `yearly`).
  - If both are present, the last specified option takes precedence; debug output commonly shows warnings such as `'size' overrides previously specified 'daily'`.

- `minsize <value>`
  - Requires both conditions: file must be at least this size and the configured time interval condition must also be met.
  - Useful to avoid rotating tiny low-signal logs.

- `maxsize <value>`
  - Rotates when file exceeds this threshold even before the next time interval boundary.
  - Still subject to invocation cadence (see "How Logrotate Actually Runs").
  - Good protection against runaway growth when paired with frequent invocation.

### Retention and naming directives

- `rotate <count>`
  - Number of archived files to keep before oldest is removed.

- `dateext`
  - Uses date-based suffixes instead of numeric suffixes.
  - Helpful for forensic clarity and incident timelines.

- `compress` / `delaycompress`
  - `compress` gzip-compresses rotated logs.
  - `delaycompress` waits one cycle before compressing newest rotated file, useful for tools that still read the most recent rotated file.

- `missingok`
  - Skip missing logs without failing the whole run.

- `notifempty`
  - Do not rotate empty files.

- `create <mode> <user> <group>`
  - Create a new file after rotation with explicit permissions and ownership.
  - Critical for services that cannot recreate files correctly on their own.

### Rotation method directives

- `copytruncate`
  - Copies current file, then truncates the original in place.
  - Pros: process does not need to reopen file descriptors.
  - Note: when this option is used, `create` has no effect because the active file remains in place.
  - Risks:
    - Requires temporary extra disk roughly equal to active file size.
    - Can stress I/O for large files.
    - Can lose log lines in the small copy/truncate race window.

- `postrotate` + service reload
  - Preferred for many service logs when supported operationally.
  - Typical pattern: rotate by rename, then signal service to reopen logs.
  - For systemd Vault deployments, commonly:
    - `systemctl reload vault` (or equivalent service reload action)
  - Benefit: avoids double-space copy step and minimizes data-loss window compared to `copytruncate`.

## Systemd Reload Caveat

In some environments, Vault is launched through a shell wrapper in `ExecStart` (instead of executing Vault directly as PID 1 for the service process). In that pattern, reload handling may target the shell process rather than the Vault process.

Operational impact:

- Rename + reload rotation can be unreliable if Vault does not actually receive the expected signal/reload event.
- Teams may fall back to `copytruncate` in this specific service layout.

Recommendation:

- Review your Vault unit file with the Linux team.
- Prefer direct Vault execution in `ExecStart` where possible, then validate reload behavior before relying on `postrotate`.

## Practical Recommendations for Vault Logs

1. Choose one clear trigger model and avoid accidental precedence conflicts.
2. Do not combine `size` with `daily`/`weekly` unless last-option precedence is intentional.
3. Prefer rename-based rotation with `postrotate` service reload where possible.
4. If you must use `copytruncate`, reserve enough disk headroom for temporary duplication.
5. Treat audit and operational logs separately when growth profiles differ.
6. Validate with debug mode before rollout: `sudo logrotate -d /etc/logrotate.d/vault`.
7. Verify the scheduler (cron or systemd timer) is enabled and running at the expected cadence.
8. Use one of these trigger patterns:
  - Time + minimum-size: `daily` + sensible `minsize`.
  - Size-guarded: `size` alone, or `maxsize` with a time interval (and frequent scheduler cadence).

## Example Configuration (Reload-Based Rotation)

The example below is a starting point pattern for Linux teams to adapt:

```conf
/var/log/vault/vault.log /var/log/vault/vault_audit.log {
    daily
    rotate 7
    minsize 10M
    maxsize 1G
    missingok
    notifempty
    compress
    delaycompress
    dateext
    create 0640 vault vault
    sharedscripts
    postrotate
        /usr/bin/systemctl reload vault >/dev/null 2>&1 || true
    endscript
}
```

Notes:

- Adjust `minsize`, `maxsize`, and `rotate` to your growth and retention requirements.
- Confirm the Vault service name (`vault`) and systemd path (`/usr/bin/systemctl`) for your OS.
- If reload semantics differ in your environment, update `postrotate` accordingly.

## Troubleshooting Checklist

1. Confirm logrotate run path:
  - cron job or systemd timer exists, is active, and matches expected cadence.
2. Run dry-run debug:
   - `sudo logrotate -d /etc/logrotate.d/vault`
   - Watch for precedence warnings like `'size' overrides previously specified 'daily'`.
3. Run forced test in non-prod:
   - `sudo logrotate -f /etc/logrotate.d/vault`
4. Check status and recent runs:
   - `sudo journalctl -u logrotate --since "24 hours ago"`
   - or distribution-specific cron logs.
5. Confirm permissions and ownership:
   - Vault can write new files after rotation.
6. Confirm free space headroom:
   - Especially required when `copytruncate` is still in use.
7. Inspect rotation state metadata:
   - `/var/lib/logrotate/logrotate.status`
8. Ask whether any manual forced rotations (`-f`) were run during incident windows.

## Expected vs Observed Behavior Framework

Use this quick structure during incident reviews:

- Expected: logs rotate on configured cadence/thresholds, retention is maintained, and Vault stays responsive.
- Observed: rotation skipped/delayed/failed, files exceeded thresholds, or disk pressure caused Vault impact.
- Next validation: `logrotate -d` output, scheduler evidence, disk/permission checks, and `postrotate` reload verification.

## References

- [Vault audit file logging and rotation notes](https://developer.hashicorp.com/vault/docs/audit/file#log-file-rotation)
- [logrotate(8) Linux manual](https://linux.die.net/man/8/logrotate)
- [HashiCorp Terraform AWS Vault Enterprise example logrotate template](https://github.com/hashicorp/terraform-aws-vault-enterprise-hvd/blob/8cbb0394184006e3c5142010f3e6348123d45fdb/templates/install-vault.sh.tpl#L293)
