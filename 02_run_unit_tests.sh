#!/bin/bash
umask 007

#R001: Run with bash in strict fail-fast mode.
set -euo pipefail

#R005: Refuse test execution when swift is unavailable on PATH.
if ! command -v swift >/dev/null 2>&1; then
    echo "swift is required but was not found on PATH."
    exit 1
fi

#R010: Resolve repository root from script location to avoid caller cwd dependence.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"

#R015: Fail clearly when Swift package manifest is missing.
if [ ! -f "${REPO_ROOT}/Package.swift" ]; then
    echo "Package.swift not found at ${REPO_ROOT}/Package.swift"
    exit 1
fi

#R035: Refuse shell-test execution when bats is unavailable.
if ! command -v bats >/dev/null 2>&1; then
    echo "bats is required but was not found on PATH."
    exit 1
fi

#R020: Execute swift unit tests with parallelism and fail-fast handling.
TEST_OUTPUT_FILE="$(mktemp)"
if ! (
    cd "$REPO_ROOT"
    swift test --parallel --enable-xctest --disable-swift-testing 2>&1 | tee "$TEST_OUTPUT_FILE"
); then
    echo "Swift unit tests failed."
    exit 1
fi

#R025: Fail when swift test output reports zero executed tests.
if ! awk '{
    if (match($0, /Executed [1-9][0-9]* test/)) {
        found = 1
    }
    if (match($0, /Test run with [1-9][0-9]* tests? in [0-9]+ suites?/)) {
        found = 1
    }
    if (match($0, /^\[[1-9][0-9]*\/[1-9][0-9]*\] Testing /)) {
        found = 1
    }
} END { exit found ? 0 : 1 }' "$TEST_OUTPUT_FILE"; then
    echo "❌ Swift unit test coverage check failed: no tests were executed."
    exit 1
fi

#R040: Discover all shell unit test files from Tests/sh.
shopt -s nullglob
BATS_TEST_FILES=( "${REPO_ROOT}"/Tests/sh/*.bats )
shopt -u nullglob
if [ "${#BATS_TEST_FILES[@]}" -eq 0 ]; then
    echo "No shell unit tests found under ${REPO_ROOT}/Tests/sh/*.bats"
    exit 1
fi

#R045: Execute all discovered shell unit tests and fail fast on errors.
if ! (
    cd "$REPO_ROOT"
    bats "${BATS_TEST_FILES[@]}"
); then
    echo "Shell unit tests failed."
    exit 1
fi

#R030: Emit a single operator-readable pass line on success.
echo "✅ PASS: Repository unit tests completed."
