# Install Prerequisites Requirements

## Scope

Applies to `01_install_prerequisites.sh` and local macOS setup required before running this repository's build/test targets.

R001  Statement: Run with `bash` in strict fail-fast mode.
Design: Use `set -euo pipefail` and exit non-zero on unrecoverable failures.
Tests:
- Force a failing command and verify installer exits non-zero.

R005  Statement: Verify Homebrew exists before Homebrew package actions.
Design: Check `brew` on `PATH`; print install guidance when missing.
Tests:
- Run with `brew` unavailable and verify clear failure guidance.

R010  Statement: Ensure Xcode command-line tooling required by this project is available.
Design: Require `xcodebuild`, `xcrun`, and `clang++` to resolve before continuing.
Tests:
- Simulate missing toolchain command and verify clear failure message.

R015  Statement: Ensure Xcode first-launch and license requirements are satisfied.
Design: Run first-launch initialization only when needed, then re-check readiness and fail when incomplete.
Constraints:
- Use privileged `xcodebuild -runFirstLaunch` when setup is required.
- Accept Xcode license when `xcodebuild -license check` reports incomplete state.
Tests:
- Run on a machine that requires first-launch and verify initialization is attempted.
- Run on an already initialized machine and verify setup phase is skipped.

R020  Statement: Ensure `xcodegen` is installed and available on `PATH`.
Design: Install Homebrew formula `xcodegen` when missing, then verify command resolution.
Tests:
- Run without `xcodegen` and verify installer runs `brew install xcodegen`.
- Rerun with `xcodegen` already installed and verify no reinstall.

R025  Statement: Ensure Swift compiler tooling is available for UI typecheck targets.
Design: Require `swiftc` through `xcrun --find swiftc` and fail with guidance when missing.
Tests:
- Simulate missing Swift compiler and verify installer exits with guidance.

R030  Statement: Print explicit status for each prerequisite phase.
Design: Emit checking/installing/success/failure lines for Homebrew, Xcode toolchain, Xcode first-launch, and `xcodegen`.
Tests:
- Run installer and verify phase status output appears for all major checks.

R035  Statement: Keep installer idempotent across reruns.
Design: Skip install/setup steps when dependencies are already satisfied.
Tests:
- Run installer twice and verify the second run performs no unnecessary installs.

R040  Statement: Print final readiness guidance for local development.
Design: End with success output that references repository commands (`make build`, `make test`, `make ui-test`, `make run`).
Tests:
- On successful run, verify final guidance includes those commands.

R045  Statement: Ensure `1psa` is available for runtime Graph token retrieval.
Design: Validate `1psa` on `PATH`; if missing, clone/build/install from configured source and fail clearly when clone/build/install prerequisites are invalid.
Tests:
- Run without `1psa` and verify clone/build/install flow executes.
- Run with `1psa` already on `PATH` and verify install phase is skipped.

R050  Statement: Keep `1psa` bootstrap rerunnable and explicit.
Design: Print dedicated `1psa` phase status, avoid reinstall when already present, and print default token item/field guidance at completion.
Tests:
- Run installer twice with `1psa` already installed and verify no reinstall is attempted.
- Verify success guidance includes default `outlook_graph_token` item and `password` field values.

R055  Statement: Ensure SAST tools required by `make sast` are available.
Design: Installer verifies/install `shellcheck`, `semgrep`, `clang-tidy`, and `gitleaks` before completion so the SAST lane is runnable after prerequisite setup.
Tests:
- Run installer without those tools and verify each required formula install is attempted.
- Rerun installer and verify already-installed tools are not reinstalled.

R060  Statement: Print explicit status for each SAST prerequisite phase.
Design: Emit clear checking/install/success/failure output for `shellcheck`, `semgrep`, `clang-tidy`, and `gitleaks`.
Tests:
- Run installer and verify each SAST phase emits a status line.
- Simulate a failed install and verify installer exits non-zero with tool-specific guidance.

R065  Statement: Include SAST lane in final readiness guidance.
Design: Success guidance includes `make sast` alongside existing build/test/run commands.
Tests:
- Run installer successfully and verify final readiness guidance lists `make sast`.

R070  Statement: Support Homebrew LLVM `clang-tidy` fallback when command is not on PATH.
Design: When `clang-tidy` is missing, install `llvm` and accept either PATH-discoverable `clang-tidy` or executable at `$(brew --prefix llvm)/bin/clang-tidy`; otherwise fail non-zero.
Tests:
- Simulate missing PATH `clang-tidy` with a valid Homebrew LLVM prefix binary and verify success.
- Simulate missing PATH `clang-tidy` and missing LLVM prefix binary and verify explicit failure.

## Changelog

- 2026-05-06: Rewrote prerequisites for this repository (removed copied teller-specific dependencies) and focused on local Homebrew/Xcode/xcodegen readiness.
- 2026-05-07: Updated final guidance command references for consolidated Make targets.
- 2026-05-07: Added explicit 1psa bootstrap requirements for real Outlook token retrieval.
- 2026-05-07: Added SAST prerequisite coverage (`shellcheck`, `semgrep`, `clang-tidy`, `gitleaks`) and `make sast` readiness guidance.
