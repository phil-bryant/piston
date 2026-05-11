#!/usr/bin/env bats

setup() {
  export REPO_ROOT="/Users/phil/local/src/piston"
  export SCRIPT_SOURCE="${REPO_ROOT}/05_run_piston.sh"
  export TMP_ROOT
  TMP_ROOT="$(mktemp -d)"
  export STUB_BIN="${TMP_ROOT}/bin"
  export FIXTURE_ROOT="${TMP_ROOT}/fixture"
  export CALLS_LOG="${TMP_ROOT}/calls.log"
  mkdir -p "${STUB_BIN}" "${FIXTURE_ROOT}"
  cp "${SCRIPT_SOURCE}" "${FIXTURE_ROOT}/05_run_piston.sh"
  chmod +x "${FIXTURE_ROOT}/05_run_piston.sh"
  : > "${CALLS_LOG}"
}

teardown() {
  rm -rf "${TMP_ROOT}"
}

make_swift_stub_success() {
  cat > "${STUB_BIN}/swift" <<'EOF'
#!/usr/bin/env bash
echo "swift $*" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/swift"
}

@test "Traceability tags for run-piston requirements" {
  #R001: Strict mode and script-root execution coverage.
  #R005: Required swift command and installer guidance coverage.
  #R010: Required discovery identity validation and env override coverage.
  #R015: Deterministic cache and startup default export coverage.
  #R020: Runner launch command invocation coverage.
  true
}

@test "R001,R015: runs from outside cwd and emits deterministic cache hint" {
  make_swift_stub_success
  mkdir -p "${TMP_ROOT}/outside"
  run env PATH="${STUB_BIN}:/usr/bin:/bin" MANIFOLD_UPLOAD_URL="https://ingest.example.com/v1/events" \
    bash -c "cd '${TMP_ROOT}/outside' && bash '${FIXTURE_ROOT}/05_run_piston.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"target_source_hint=env"* ]]
  [[ "$output" == *"${FIXTURE_ROOT}/.piston/upload-target-cache.json"* ]]
}

@test "R005: fails with installer guidance when swift is missing" {
  run env PATH="/bin" MANIFOLD_UPLOAD_URL="https://ingest.example.com/v1/events" \
    /bin/bash "${FIXTURE_ROOT}/05_run_piston.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing required command: swift"* ]]
  [[ "$output" == *"./01_install_prerequisites.sh"* ]]
}

@test "R010: fails when discovery inputs are missing and no env override is set" {
  make_swift_stub_success
  run env PATH="${STUB_BIN}:/usr/bin:/bin" \
    bash "${FIXTURE_ROOT}/05_run_piston.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing required env var: VALVE_DISCOVERY_URL"* ]]
}

@test "R010,R020: starts runner with discovery vars set" {
  make_swift_stub_success
  run env PATH="${STUB_BIN}:/usr/bin:/bin" \
    VALVE_DISCOVERY_URL="https://valve.example.com/v1/piston/upload-target" \
    PISTON_INSTALL_ID="install-123" \
    PISTON_INSTALL_CREDENTIAL="cred-abc" \
    bash "${FIXTURE_ROOT}/05_run_piston.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"target_source_hint=discovery"* ]]
  run python3 - "${CALLS_LOG}" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text(encoding="utf-8")
assert "swift run PistonRunner" in text
PY
  [ "$status" -eq 0 ]
}

@test "R015: custom cache directory changes default cache path" {
  make_swift_stub_success
  run env PATH="${STUB_BIN}:/usr/bin:/bin" \
    PISTON_CACHE_DIR="${TMP_ROOT}/custom-cache" \
    MANIFOLD_UPLOAD_URL="https://ingest.example.com/v1/events" \
    bash "${FIXTURE_ROOT}/05_run_piston.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"${TMP_ROOT}/custom-cache/upload-target-cache.json"* ]]
}
