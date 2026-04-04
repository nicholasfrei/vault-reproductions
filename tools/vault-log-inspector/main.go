// vault-log-inspector scans a Vault operational or audit log file and reports
// known error patterns with actionable resolution steps.
//
// Usage:
//
//	vault-log-inspector -log <path> [-type operational|audit|auto]
//
// Build:
//
//	go build -o vault-log-inspector .
package main

import (
	"bufio"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"regexp"
	"strings"
)

// ── Data types ────────────────────────────────────────────────────────────────

// Rule describes a single detectable error condition: the regex pattern to
// match, a plain-English summary, and an ordered list of resolution steps.
type Rule struct {
	Name       string
	Pattern    *regexp.Regexp
	Summary    string
	Resolution []string
}

// Finding records one matched line and the rule that triggered it.
type Finding struct {
	Line     int
	Raw      string
	RuleName string
	Rule     Rule
}

// ── Rules ─────────────────────────────────────────────────────────────────────

// rules is the ordered list of patterns the inspector evaluates.
// Add new rules here to extend coverage without touching scan logic.
var rules = []Rule{
	{
		Name:    "vault-sealed",
		Pattern: regexp.MustCompile(`(?i)(vault is sealed|core: vault is sealed|ErrSealed)`),
		Summary: "Vault is sealed — all API requests are rejected until the seal is cleared.",
		Resolution: []string{
			"Run `vault status` to confirm sealed state and the active seal type.",
			"Shamir seal: run `vault operator unseal` with enough key shares to meet the threshold.",
			"Auto-unseal (Transit / KMS): verify the unseal key provider is reachable and credentials are valid.",
			"Check pod or systemd logs for repeated `core: vault is sealed` entries that indicate the unseal loop is failing.",
			"Docs: https://developer.hashicorp.com/vault/docs/concepts/seal",
		},
	},
	{
		Name:    "permission-denied",
		Pattern: regexp.MustCompile(`(?i)(permission denied)`),
		Summary: "Permission denied — the token's attached policies do not grant the requested capability on the target path.",
		Resolution: []string{
			"Run `vault token capabilities <token> <path>` to see effective capabilities at the exact path.",
			"Run `vault token lookup <token>` to inspect which policies are attached to the token.",
			"For KV v2 mounts, policies must reference `/data/` (read/write) and `/metadata/` (list) sub-paths — bare mount paths are not sufficient.",
			"If using namespaces, confirm the policy is written and applied in the correct namespace context.",
			"Docs: https://developer.hashicorp.com/vault/docs/concepts/policies",
		},
	},
	{
		Name:    "token-expired",
		Pattern: regexp.MustCompile(`(?i)(token not found|token is expired|bad token|invalid token|token lookup failed)`),
		Summary: "Token expired or invalid — the token no longer exists in Vault's token store or has exceeded its TTL.",
		Resolution: []string{
			"Re-authenticate to obtain a fresh token: `vault login -method=<method>`.",
			"Check the token's configured TTL with `vault token lookup` and compare against `ttl` / `max_ttl` on the auth role.",
			"If using Vault Agent, verify the auto-auth sink and renewal settings are correct in the agent config.",
			"If using VSO, confirm the VaultAuth resource is binding to a valid role with an appropriate token TTL.",
			"Docs: https://developer.hashicorp.com/vault/docs/concepts/tokens",
		},
	},
}

// ── Log parsing ───────────────────────────────────────────────────────────────

// scan reads f line by line and returns all findings. logType controls whether
// JSON audit-log extraction is attempted ("audit", "operational", or "auto").
func scan(f *os.File, logType string) []Finding {
	var findings []Finding
	scanner := bufio.NewScanner(f)

	// Increase the scanner buffer for very long audit-log JSON lines.
	const maxLine = 512 * 1024
	scanner.Buffer(make([]byte, maxLine), maxLine)

	lineNum := 0
	for scanner.Scan() {
		lineNum++
		raw := scanner.Text()

		// Decide which string to match against.
		target := raw
		if logType == "audit" || (logType == "auto" && looksLikeJSON(raw)) {
			if extracted := extractAuditError(raw); extracted != "" {
				target = extracted
			}
		}

		for _, rule := range rules {
			if rule.Pattern.MatchString(target) {
				findings = append(findings, Finding{
					Line:     lineNum,
					Raw:      raw,
					RuleName: rule.Name,
					Rule:     rule,
				})
				break // one finding per line; first rule wins
			}
		}
	}

	if err := scanner.Err(); err != nil {
		fmt.Fprintf(os.Stderr, "warn: error reading log: %v\n", err)
	}
	return findings
}

// looksLikeJSON returns true when the line looks like a JSON object, which is
// the format used by Vault's audit log devices.
func looksLikeJSON(line string) bool {
	return strings.HasPrefix(strings.TrimSpace(line), "{")
}

// extractAuditError attempts to pull a meaningful error string from a single
// Vault audit log JSON line. Vault audit entries carry errors in two places:
//
//   - top-level "error" field (auth failures, seal errors)
//   - "response" → "data" → "errors" array (API-level errors)
func extractAuditError(line string) string {
	var entry map[string]interface{}
	if err := json.Unmarshal([]byte(line), &entry); err != nil {
		return ""
	}

	// Top-level error field.
	if v, ok := entry["error"]; ok {
		return fmt.Sprintf("%v", v)
	}

	// Nested response errors array.
	if resp, ok := entry["response"].(map[string]interface{}); ok {
		if data, ok := resp["data"].(map[string]interface{}); ok {
			if errs, ok := data["errors"]; ok {
				return fmt.Sprintf("%v", errs)
			}
		}
	}

	return ""
}

// ── Reporting ─────────────────────────────────────────────────────────────────

// printReport writes a human-readable summary to stdout. Resolution steps for
// each distinct rule are printed once, regardless of how many lines matched.
func printReport(findings []Finding) {
	if len(findings) == 0 {
		fmt.Println("No known error patterns detected in the provided log file.")
		return
	}

	fmt.Printf("\n=== Vault Log Inspector Report ===\n")
	fmt.Printf("Findings: %d\n", len(findings))
	fmt.Println(strings.Repeat("─", 50))

	// Track which rules have already had their resolution printed.
	printed := make(map[string]bool)

	for i, f := range findings {
		fmt.Printf("\n[%d] Line %-5d  Rule: %s\n", i+1, f.Line, f.RuleName)
		fmt.Printf("     Log:   %s\n", truncate(f.Raw, 120))
		fmt.Printf("     Issue: %s\n", f.Rule.Summary)

		if !printed[f.RuleName] {
			fmt.Println("     Resolution:")
			for j, step := range f.Rule.Resolution {
				fmt.Printf("       %d. %s\n", j+1, step)
			}
			printed[f.RuleName] = true
		} else {
			fmt.Printf("     Resolution: see finding [1] for rule %q above.\n", f.RuleName)
		}
	}

	fmt.Printf("\n%s\n", strings.Repeat("─", 50))
	printSummaryTable(findings)
}

// printSummaryTable renders a compact count-per-rule table at the end of the
// report, useful when a log file contains hundreds of repeated errors.
func printSummaryTable(findings []Finding) {
	counts := make(map[string]int)
	order := []string{}
	for _, f := range findings {
		if counts[f.RuleName] == 0 {
			order = append(order, f.RuleName)
		}
		counts[f.RuleName]++
	}

	fmt.Println("Rule                  | Occurrences")
	fmt.Println("----------------------|------------")
	for _, name := range order {
		fmt.Printf("%-22s| %d\n", name, counts[name])
	}
}

// truncate shortens s to at most n runes, appending "…" if trimmed.
func truncate(s string, n int) string {
	runes := []rune(s)
	if len(runes) <= n {
		return s
	}
	return string(runes[:n]) + "…"
}

// ── Entry point ───────────────────────────────────────────────────────────────

func main() {
	logPath := flag.String("log", "", "Path to a Vault operational or audit log file (required)")
	logType := flag.String("type", "auto", "Log format: 'operational', 'audit', or 'auto' (default: auto)")
	flag.Parse()

	if *logPath == "" {
		fmt.Fprintln(os.Stderr, "error: -log flag is required")
		fmt.Fprintln(os.Stderr, "Usage: vault-log-inspector -log <path> [-type operational|audit|auto]")
		os.Exit(1)
	}

	validTypes := map[string]bool{"auto": true, "operational": true, "audit": true}
	if !validTypes[*logType] {
		fmt.Fprintf(os.Stderr, "error: invalid -type value %q; must be 'operational', 'audit', or 'auto'\n", *logType)
		os.Exit(1)
	}

	f, err := os.Open(*logPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "error: cannot open log file: %v\n", err)
		os.Exit(1)
	}
	defer f.Close()

	fmt.Printf("Scanning: %s  (type=%s)\n", *logPath, *logType)
	findings := scan(f, *logType)
	printReport(findings)
}
