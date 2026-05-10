#!/usr/bin/env bats

setup() {
  export REPO_ROOT="/Users/phil/local/src/piston"
  export SCRIPT_SOURCE="${REPO_ROOT}/02_run_unit_tests.sh"
  export TMP_ROOT
  TMP_ROOT="$(mktemp -d)"
  export FIXTURE_ROOT="${TMP_ROOT}/repo"
  export STUB_BIN="${TMP_ROOT}/bin"
  export CALLS_LOG="${TMP_ROOT}/calls.log"
  mkdir -p "${FIXTURE_ROOT}" "${STUB_BIN}"
  cp "${SCRIPT_SOURCE}" "${FIXTURE_ROOT}/02_run_unit_tests.sh"
  chmod +x "${FIXTURE_ROOT}/02_run_unit_tests.sh"
  mkdir -p "${FIXTURE_ROOT}/Tests/sh"
  cat > "${FIXTURE_ROOT}/Tests/sh/fixture_pass.bats" <<'EOF'
#!/usr/bin/env bats
@test "fixture pass" { [ 1 -eq 1 ]; }
EOF
  chmod +x "${FIXTURE_ROOT}/Tests/sh/fixture_pass.bats"
  cat > "${FIXTURE_ROOT}/Package.swift" <<'EOF'
// fixture manifest
EOF
}

teardown() {
  rm -rf "${TMP_ROOT}"
}

make_swift_stub() {
  local exit_code="${1:-0}"
  local mode="${2:-with-tests}"
  cat > "${STUB_BIN}/swift" <<EOF
#!/bin/bash
echo "swift \$*" >> "${CALLS_LOG}"
echo "pwd=\$(pwd)" >> "${CALLS_LOG}"
if [ "\${1:-}" = "test" ]; then
  if [ "${mode}" = "with-tests" ]; then
    cat <<'SWIFTOUT'
Test Suite 'All tests' started
Executed 4 tests, with 0 failures (0 unexpected) in 0.012 (0.013) seconds
SWIFTOUT
  fi
  if [ "${mode}" = "modern-with-tests" ]; then
    cat <<'SWIFTOUT'
◇ Test run started.
✔ Test run with 4 tests in 1 suite passed after 0.012 seconds.
SWIFTOUT
  fi
  if [ "${mode}" = "no-tests" ]; then
    cat <<'SWIFTOUT'
Test Suite 'All tests' started
Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
SWIFTOUT
  fi
  if [ "${mode}" = "modern-no-tests" ]; then
    cat <<'SWIFTOUT'
◇ Test run started.
✔ Test run with 0 tests in 0 suites passed after 0.001 seconds.
SWIFTOUT
  fi
  if [ "${mode}" = "progress-only" ]; then
    cat <<'SWIFTOUT'
[1/9] Testing PistonTests.PistonUploaderTests/testExampleA
[2/9] Testing PistonTests.PistonUploaderTests/testExampleB
SWIFTOUT
  fi
  exit ${exit_code}
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/swift"
  : > "${CALLS_LOG}"
}

make_bats_stub() {
  local exit_code="${1:-0}"
  cat > "${STUB_BIN}/bats" <<EOF
#!/bin/bash
echo "bats \$*" >> "${CALLS_LOG}"
exit ${exit_code}
EOF
  chmod +x "${STUB_BIN}/bats"
}

@test "traceability tags for unit-test runner requirements" {
  #R001: Strict fail-fast mode requirement coverage.
  #R005: Missing swift CLI failure requirement coverage.
  #R010: Script-directory root resolution requirement coverage.
  #R015: Package.swift manifest validation requirement coverage.
  #R020: swift test fail-fast invocation requirement coverage.
  #R025: No-tests-executed coverage gate requirement coverage.
  #R030: Single pass-line output requirement coverage.
  #R035: Missing bats CLI failure requirement coverage.
  #R040: Tests/sh lane discovery requirement coverage.
  #R045: bats execution fail-fast requirement coverage.
  true
}

@test "fails when swift is unavailable" {
  #R005
  mkdir -p "${TMP_ROOT}/empty-path"
  run env PATH="${TMP_ROOT}/empty-path" /bin/bash "${FIXTURE_ROOT}/02_run_unit_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"swift is required"* ]]
}

@test "runs swift test from script directory regardless of caller cwd" {
  #R010 #R020
  make_swift_stub 0 "modern-with-tests"
  make_bats_stub 0
  run bash -lc "cd '${TMP_ROOT}' && PATH='${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin' bash '${FIXTURE_ROOT}/02_run_unit_tests.sh'"
  [ "$status" -eq 0 ]
  run rg "^swift test --parallel --enable-xctest --disable-swift-testing$" "${CALLS_LOG}"
  [ "$status" -eq 0 ]
  run rg "^pwd=${FIXTURE_ROOT}$" "${CALLS_LOG}"
  [ "$status" -eq 0 ]
}

@test "fails when Package.swift is missing" {
  #R015
  make_swift_stub 0 "with-tests"
  make_bats_stub 0
  rm -f "${FIXTURE_ROOT}/Package.swift"
  run env PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" bash "${FIXTURE_ROOT}/02_run_unit_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Package.swift not found"* ]]
}

@test "fails when swift test command fails" {
  #R001 #R020
  make_swift_stub 1 "with-tests"
  make_bats_stub 0
  run env PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" bash "${FIXTURE_ROOT}/02_run_unit_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Swift unit tests failed."* ]]
}

@test "fails when swift test output reports zero tests" {
  #R025
  make_swift_stub 0 "modern-no-tests"
  make_bats_stub 0
  run env PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" bash "${FIXTURE_ROOT}/02_run_unit_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no tests were executed"* ]]
}

@test "passes with executed tests and emits single pass line" {
  #R025 #R030
  make_swift_stub 0 "with-tests"
  make_bats_stub 0
  run env PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" bash "${FIXTURE_ROOT}/02_run_unit_tests.sh"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | rg -c "✅ PASS:")" -eq 1 ]
}

@test "passes when runner output includes only progress test rows" {
  #R025
  make_swift_stub 0 "progress-only"
  make_bats_stub 0
  run env PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" bash "${FIXTURE_ROOT}/02_run_unit_tests.sh"
  [ "$status" -eq 0 ]
}

@test "fails when bats is unavailable" {
  #R035
  make_swift_stub 0 "with-tests"
  run env PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" bash "${FIXTURE_ROOT}/02_run_unit_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"bats is required"* ]]
}

@test "fails when no shell unit tests are discovered" {
  #R040
  make_swift_stub 0 "with-tests"
  make_bats_stub 0
  rm -f "${FIXTURE_ROOT}/Tests/sh/"*.bats
  run env PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" bash "${FIXTURE_ROOT}/02_run_unit_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"No shell unit tests found under"* ]]
}

@test "fails when shell unit tests fail in bats" {
  #R045
  make_swift_stub 0 "with-tests"
  make_bats_stub 1
  run env PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" bash "${FIXTURE_ROOT}/02_run_unit_tests.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Shell unit tests failed."* ]]
}

@test "runs bats with all discovered shell test files" {
  #R040 #R045
  make_swift_stub 0 "with-tests"
  make_bats_stub 0
  cat > "${FIXTURE_ROOT}/Tests/sh/fixture_second.bats" <<'EOF'
#!/usr/bin/env bats
@test "fixture second pass" { [ 1 -eq 1 ]; }
EOF
  run env PATH="${STUB_BIN}:/usr/bin:/bin:/usr/sbin:/sbin" bash "${FIXTURE_ROOT}/02_run_unit_tests.sh"
  [ "$status" -eq 0 ]
  run rg "bats .*fixture_pass\\.bats.*fixture_second\\.bats|bats .*fixture_second\\.bats.*fixture_pass\\.bats" "${CALLS_LOG}"
  [ "$status" -eq 0 ]
}
