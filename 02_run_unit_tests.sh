#!/usr/bin/env bash
umask 007
#R001: Run with strict shell mode so any failing lane exits non-zero.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#R005: Resolve and enter repository root via script directory.
cd "$SCRIPT_DIR"

RUN_SHELL_TESTS="${RUN_SHELL_TESTS:-true}"
RUN_SWIFT_TESTS="${RUN_SWIFT_TESTS:-true}"
BATS_FILTER="${BATS_FILTER:-}"

#R010: Run shell unit tests from ./Tests/sh when enabled.
if [[ "$RUN_SHELL_TESTS" == "true" ]]; then
  if [[ -d "./Tests/sh" ]]; then
    if ! command -v bats >/dev/null 2>&1; then
      echo "❌ bats is required for shell unit tests. Install bats-core and rerun."
      exit 1
    fi
    echo "▶ Running shell unit tests (bats)..."
    if [[ -n "$BATS_FILTER" ]]; then
      bats --filter "$BATS_FILTER" ./Tests/sh
    else
      bats ./Tests/sh
    fi
  else
    echo "ℹ️  Skipping shell unit tests: ./Tests/sh not found."
  fi
fi

#R020: Run Swift package unit tests when enabled.
if [[ "$RUN_SWIFT_TESTS" == "true" ]]; then
  if ! command -v swift >/dev/null 2>&1; then
    echo "❌ swift is required for Swift unit tests. Install Xcode command line tools and rerun."
    exit 1
  fi
  echo "▶ Running Swift unit tests (swift test)..."
  swift test
fi
