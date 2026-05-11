# Run AV Checks Requirements

## Scope

Applies to `04_run_av_checks.sh`.

R001  Statement: Run AV checks in strict fail-fast mode from repository root.
Design: Use strict bash mode (`set -euo pipefail`), resolve script directory from `${BASH_SOURCE[0]}`, and `cd` to that directory before running lanes.
Tests:
- Run from a non-repo working directory and verify report artifacts are still written under script-root `.security-reports`.

R005  Statement: Fail fast with actionable installer guidance when required commands are missing.
Design: Validate required commands per lane and print `./01_install_prerequisites.sh` guidance when a required command is unavailable.
Tests:
- Run with `clamscan` missing and verify non-zero failure plus install guidance output.

R010  Statement: Support explicit ClamAV lane opt-out with deterministic artifacts.
Design: Default `RUN_CLAMAV` to `true`; when `RUN_CLAMAV=false`, emit empty `clamav.log` and write `clamav-summary.json` with `skipped=true`, then exit success.
Tests:
- Run with `RUN_CLAMAV=false` and verify skipped summary output, empty log artifact, and success exit.

R015  Statement: Run recursive ClamAV scanning and persist raw scanner output.
Design: Execute `clamscan --recursive --infected` against `CLAMAV_SCAN_TARGET` (default `.`) with repository-safe excludes and write output to `clamav.log`.
Tests:
- Run with clean `clamscan` stub output and verify `clamav.log` is produced with scanner summary fields.

R020  Statement: Report ClamAV signature freshness before scanning.
Design: Resolve database directory from `CLAMAV_DB_DIR`, Homebrew default, or `/var/lib/clamav`; print freshness details from signature file mtimes with staleness threshold from `CLAMAV_SIGNATURE_MAX_AGE_HOURS`. When signatures are stale (or missing), print explicit guidance to refresh with `freshclam --stdout`.
Tests:
- Run with a scan stub and verify output includes signature freshness status text.
- Run with stale signature files and verify output includes refresh guidance referencing `freshclam --stdout`.

R025  Statement: Emit heartbeat progress during long-running scans.
Design: While waiting for `clamscan`, print periodic "scan in progress" lines using `CLAMAV_HEARTBEAT_SECONDS` and `CLAMAV_POLL_SECONDS`, clamping invalid values to safe minimums.
Tests:
- Run with slow scan stub plus short heartbeat configuration and verify heartbeat output appears.

R030  Statement: Persist machine-readable ClamAV summary and optional gate result.
Design: Parse `clamav.log` into `clamav-summary.json` including `scanned_files`, `infected_files`, `exit_code`, `skipped`, and `gate_failed`; fail when `SECURITY_FAIL_ON_HIGH_CRITICAL=true` and infected files are present.
Tests:
- Run with clean scan output and verify summary fields indicate pass.
- Run with infected scan output and verify gate failure output when fail-on-high is enabled.

R035  Statement: Fail clearly when configured scan target is missing.
Design: Resolve `CLAMAV_SCAN_TARGET` to an absolute path and fail non-zero with explicit "scan target not found" output when target does not exist.
Tests:
- Run with nonexistent `CLAMAV_SCAN_TARGET` and verify explicit non-zero failure.

R040  Statement: Attempt one-time signature refresh and retry when database files are missing.
Design: When `clamscan` exits `>1` and output includes `No supported database files found`, run `freshclam --stdout`, then retry `clamscan` once.
Tests:
- Simulate missing-database error on first scan and clean second scan; verify `freshclam --stdout` is invoked and scan retry succeeds.

R045  Statement: Treat ClamAV execution failures as hard failures.
Design: If `clamscan` exits `>1` after any allowed retry path, write summary artifact and fail with explicit execution-failure output.
Tests:
- Run with `clamscan` stub returning exit `2` and verify script exits non-zero with failure message.

R050  Statement: Emit deterministic completion output including report location.
Design: Print lane completion markers and final success line containing `Reports: <dir>` so automation can find artifacts.
Tests:
- Run successful scan path and verify final completion line contains `Reports:`.

## Changelog

- 2026-05-10: Added step-04 ClamAV AV check requirements for piston, including retry, gating, and deterministic artifacts.
