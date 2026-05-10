# Run Security Checks Requirements

## Scope

Applies to `03_run_security_checks.sh`.

R001  Statement: Run in strict fail-fast shell mode from repository root.
Design: Use `set -euo pipefail`, resolve the script directory from `${BASH_SOURCE[0]}`, and `cd` to that directory before running scanners.
Tests:
- Invoke script from a non-repo working directory and verify reports are still emitted under repo-relative paths.

R005  Statement: Support configurable report destination and per-lane toggles.
Design: Resolve `SECURITY_REPORT_DIR`, `RUN_SHELLCHECK`, `RUN_SEMGREP`, `RUN_GITLEAKS`, `RUN_DETECT_SECRETS`,
`RUN_SWIFTLINT`, and `SECURITY_FAIL_ON_FINDINGS` from environment variables with safe defaults and always create the
report directory.
Tests:
- Run with all lanes disabled and a custom report directory and verify script exits successfully while creating that directory.

R010  Statement: Fail clearly when an enabled lane is missing required tooling.
Design: Validate required commands with a dedicated checker and return actionable tool-specific error output.
Tests:
- Enable one lane with its command missing from `PATH` and verify explicit missing-command failure output.

R015  Statement: Run ShellCheck across repository shell automation, persist JSON output, and print findings.
Design: Discover shell targets from top-level numbered scripts and `Tests/sh/*.bats`, run `shellcheck -f json`, write `shellcheck.json`, and treat exit code `1` as findings while `>1` is execution failure. When findings are present, print a readable findings section with file, line, rule ID, and message.
Tests:
- Stub ShellCheck success output and verify `shellcheck.json` exists.
- Stub ShellCheck with findings (exit `1`) and verify findings are counted in security summary and echoed in terminal output.

R020  Statement: Run Semgrep in JSON mode and persist report artifacts.
Design: Execute `semgrep scan` with JSON output into `semgrep.json`, treat exit `1` as findings, and fail immediately only for execution errors (`>1`).
Tests:
- Stub Semgrep findings output and verify report is created and findings are summarized.
- Stub Semgrep execution failure and verify script exits with explicit Semgrep execution-failure output.

R025  Statement: Run Gitleaks and persist report artifacts.
Design: Execute `gitleaks detect` with JSON report output and treat exit `1` as findings while treating `>1` as execution failure.
Tests:
- Stub Gitleaks findings output and verify report is created and findings are summarized.
- Stub Gitleaks execution failure and verify script exits with explicit Gitleaks execution-failure output.

R035  Statement: Run detect-secrets and persist report artifacts.
Design: Execute `detect-secrets scan --all-files`, write `detect-secrets.json`, and fail when command execution fails. When findings exist in `results`, print a readable detect-secrets findings section immediately after the detect-secrets lane output and before any next tool header; for each finding, print file/line/type and the matched source line directly beneath it.
Tests:
- Stub detect-secrets success output and verify report is created and findings are summarized from `results`.
- Stub detect-secrets findings output and verify each finding prints with its source line directly below it before the next tool header.
- Stub detect-secrets execution failure and verify script exits with explicit detect-secrets execution-failure output.

R040  Statement: Run SwiftLint in JSON mode and persist report artifacts.
Design: Execute `swiftlint lint --reporter json` and write `swiftlint.json`. When SwiftLint exits non-zero, treat it as findings
if `swiftlint.json` contains a valid JSON list payload; treat it as execution failure only when non-zero exit is accompanied by
an invalid or missing JSON report.
Tests:
- Stub SwiftLint findings output with non-zero exit and valid JSON and verify findings are summarized.
- Stub SwiftLint execution failure with non-zero exit and invalid/missing report and verify explicit execution-failure output.

R045  Statement: Print a manifold-style tool explainer header before each enabled tool lane executes.
Design: Emit the boxed manifold-style header with `Security Tool: <name>`, two explainer lines, and `URL: <tool-doc-url>`
before each enabled tool command; print report path as a separate line immediately after the header.
Tests:
- Enable all lanes with stubs and verify output contains one boxed header for each tool with `Security Tool:` and `URL:`
  fields before execution output.

R030  Statement: Produce consolidated security summary and enforce fail-on-findings policy.
Design: Aggregate ShellCheck, Semgrep, Gitleaks, detect-secrets, and SwiftLint finding counts into
`security-summary.json`; when `SECURITY_FAIL_ON_FINDINGS=true`, exit non-zero if total findings is non-zero.
Tests:
- Seed at least one finding and verify script fails when fail-on-findings is enabled.
- Seed at least one finding and verify script passes when fail-on-findings is disabled.

## Changelog

- 2026-05-10: Added tool explainer-header requirement for each enabled security lane.
- 2026-05-10: Added detect-secrets and SwiftLint lanes with report and summary requirements.
- 2026-05-09: Updated traceability-tag test pattern to use a ShellCheck-safe always-pass assertion (`true`) instead of SC2050 tautologies.
- 2026-05-09: Initial requirements for `03_run_security_checks.sh` modeled after teller security-check stage with piston-appropriate tools.
