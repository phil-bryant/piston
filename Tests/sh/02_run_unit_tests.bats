#!/usr/bin/env bats

setup() {
  export REPO_ROOT="/Users/phil/local/src/piston"
  export SCRIPT_SOURCE="${REPO_ROOT}/02_run_unit_tests.sh"
  export TMP_ROOT
  TMP_ROOT="$(mktemp -d)"
  export STUB_BIN="${TMP_ROOT}/bin"
  export FIXTURE_ROOT="${TMP_ROOT}/fixture"
  export CALLS_LOG="${TMP_ROOT}/calls.log"
  mkdir -p "${STUB_BIN}" "${FIXTURE_ROOT}/Tests/sh"
  cp "${SCRIPT_SOURCE}" "${FIXTURE_ROOT}/02_run_unit_tests.sh"
  chmod +x "${FIXTURE_ROOT}/02_run_unit_tests.sh"
  : > "${CALLS_LOG}"
}

write_bats_stub() {
  cat > "${STUB_BIN}/bats" <<EOF
#!/usr/bin/env bash
echo "bats cwd=\$(pwd) args=\$*" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/bats"
}

write_swift_stub() {
  cat > "${STUB_BIN}/swift" <<EOF
#!/usr/bin/env bash
echo "swift cwd=\$(pwd) args=\$*" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/swift"
}

write_dirname_stub() {
  cat > "${STUB_BIN}/dirname" <<'EOF'
#!/usr/bin/env bash
/usr/bin/dirname "$@"
EOF
  chmod +x "${STUB_BIN}/dirname"
}

@test "Traceability tags for run-unit-tests requirements" {
  #R001: Strict fail-fast shell mode coverage.
  #R005: Repository-root execution coverage.
  #R010: Shell-lane bats invocation and failure guidance coverage.
  #R020: Swift-lane invocation and failure guidance coverage.
  true
}

@test "runs from repository root regardless of caller cwd" {
  #R005
  #R010
  #R020
  write_bats_stub
  write_swift_stub
  cd "${TMP_ROOT}"
  run env PATH="${STUB_BIN}:/usr/bin:/bin" RUN_SHELL_TESTS=true RUN_SWIFT_TESTS=true /bin/bash "${FIXTURE_ROOT}/02_run_unit_tests.sh"
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "${calls}" == *"bats cwd=${FIXTURE_ROOT} args=./Tests/sh"* ]]
  [[ "${calls}" == *"swift cwd=${FIXTURE_ROOT} args=test"* ]]
}

@test "fails with guidance when shell tests enabled but bats is missing" {
  #R010
  write_swift_stub
  run env PATH="${STUB_BIN}:/usr/bin:/bin" RUN_SHELL_TESTS=true RUN_SWIFT_TESTS=false /bin/bash "${FIXTURE_ROOT}/02_run_unit_tests.sh"
  [ "$status" -eq 1 ]
  [[ "${output}" == *"bats is required for shell unit tests"* ]]
}

@test "passes bats filter when provided" {
  #R010
  write_bats_stub
  run env PATH="${STUB_BIN}:/usr/bin:/bin" RUN_SHELL_TESTS=true RUN_SWIFT_TESTS=false BATS_FILTER="smoke" /bin/bash "${FIXTURE_ROOT}/02_run_unit_tests.sh"
  [ "$status" -eq 0 ]
  calls="$(<"${CALLS_LOG}")"
  [[ "${calls}" == *"args=--filter smoke ./Tests/sh"* ]]
}

@test "fails with guidance when swift is missing and swift lane enabled" {
  #R020
  write_dirname_stub
  run env PATH="${STUB_BIN}" RUN_SHELL_TESTS=false RUN_SWIFT_TESTS=true /bin/bash "${FIXTURE_ROOT}/02_run_unit_tests.sh"
  [ "$status" -eq 1 ]
  [[ "${output}" == *"swift is required for Swift unit tests"* ]]
}

@test "can disable swift lane" {
  #R020
  write_bats_stub
  run env PATH="${STUB_BIN}:/usr/bin:/bin" RUN_SHELL_TESTS=true RUN_SWIFT_TESTS=false /bin/bash "${FIXTURE_ROOT}/02_run_unit_tests.sh"
  [ "$status" -eq 0 ]
}
