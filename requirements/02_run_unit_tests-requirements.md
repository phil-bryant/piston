# Run Unit Tests Requirements

## Scope

Applies to `02_run_unit_tests.sh`.

R001  Statement: Run with `bash` in strict fail-fast mode.
Design: Use `set -euo pipefail` so failures stop execution immediately.
Tests:
- Introduce a failing command and verify the script exits non-zero.

R005  Statement: Refuse unit-test execution when Swift CLI is unavailable.
Design: Require `swift` on `PATH` before any test invocation.
Tests:
- Run with `swift` unavailable and verify explicit non-zero failure output.

R010  Statement: Resolve execution root from script location rather than caller working directory.
Design: Derive repository root from the script directory and run tests from that location.
Tests:
- Invoke script from a different current working directory and verify tests still run against the repository root.

R015  Statement: Fail clearly when the Swift package manifest is missing.
Design: Validate `Package.swift` exists at the resolved repository root before running tests.
Tests:
- Remove or move `Package.swift` in a fixture and verify explicit non-zero failure output.

R020  Statement: Execute Swift unit tests with fail-fast semantics and deterministic serial output.
Design: Run `swift test --no-parallel --enable-xctest --disable-swift-testing`, stream output, and exit non-zero when the command fails.
Tests:
- Force `swift test` to fail and verify script exits non-zero.
- Verify test invocation includes `test --no-parallel --enable-xctest --disable-swift-testing`.

R025  Statement: Fail when no unit tests are executed.
Design: Parse `swift test` output and require at least one executed test row in either legacy XCTest (`Executed N test`) or
modern runner (`Test run with N tests in S suites`) format where `N > 0`, or in progress format (`[i/n] Testing ...`).
Tests:
- Simulate `Executed 0 tests` output and verify explicit non-zero coverage failure.
- Simulate `Test run with 0 tests in 0 suites` output and verify explicit non-zero coverage failure.
- Simulate progress-only output (`[1/9] Testing ...`) and verify run can complete.
- Simulate output with one or more executed tests and verify run can complete.

R030  Statement: Emit concise operator-readable pass output.
Design: Print a single `✅ PASS:` line only after all unit-test checks succeed.
Tests:
- Verify successful run emits exactly one `✅ PASS:` line.

R035  Statement: Refuse shell-unit-test execution when Bats is unavailable.
Design: Require `bats` on `PATH` before shell unit test invocation.
Tests:
- Run with `bats` unavailable and verify explicit non-zero failure output.

R040  Statement: Discover shell unit tests from the repository test lane.
Design: Resolve shell unit test files from `Tests/sh/*.bats` under the repository root and fail when none are found.
Tests:
- Run with no `Tests/sh/*.bats` files in fixture and verify explicit non-zero failure output.
- Run with one or more `Tests/sh/*.bats` files and verify invocation proceeds.

R045  Statement: Execute all discovered shell unit tests with fail-fast semantics.
Design: Invoke `bats` with all discovered `Tests/sh/*.bats` files and exit non-zero when shell tests fail.
Tests:
- Stub `bats` to fail and verify script exits non-zero with shell-test failure output.
- Verify `bats` receives all discovered `Tests/sh/*.bats` file paths.

## Changelog

- 2026-05-10: Added initial unit-test runner requirements for `02_run_unit_tests.sh`.
- 2026-05-10: Expanded `02_run_unit_tests.sh` requirements to run both Swift and `Tests/sh/*.bats` unit tests.
