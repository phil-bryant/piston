# Run Unit Tests Requirements

## Scope

Applies to `02_run_unit_tests.sh`.

R001  Statement: Run in strict fail-fast shell mode.
Design: Use `set -euo pipefail` so test-lane command failures propagate as non-zero exit.
Tests:
- Force a failing test command and verify the runner exits non-zero.

R005  Statement: Execute all test lanes from repository root.
Design: Resolve script directory and `cd` into it before running test commands.
Tests:
- Run the script from a non-repo working directory and verify lanes execute from repo root.

R010  Statement: Execute shell unit tests from `Tests/sh`.
Design: When `RUN_SHELL_TESTS=true`, verify `bats` is available and run `bats ./Tests/sh`, with optional `--filter`.
Tests:
- Enable shell lane with `Tests/sh` present and verify `bats` is invoked.
- Enable shell lane without `bats` on `PATH` and verify actionable failure output.
- Set `BATS_FILTER` and verify `bats --filter <value> ./Tests/sh` is invoked.

R020  Statement: Execute Swift package unit tests.
Design: When `RUN_SWIFT_TESTS=true`, verify `swift` is available and run `swift test`.
Tests:
- Enable Swift lane and verify `swift test` is invoked.
- Enable Swift lane without `swift` on `PATH` and verify actionable failure output.
- Disable Swift lane and verify no Swift invocation occurs.

## Changelog

- 2026-05-08: Initial requirements for `02_run_unit_tests.sh`.
