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
echo "VALVE_DISCOVERY_ENDPOINT=${VALVE_DISCOVERY_ENDPOINT:-}" >> "${CALLS_LOG}"
echo "MANIFOLD_UPLOAD_URL=${MANIFOLD_UPLOAD_URL:-}" >> "${CALLS_LOG}"
exit 0
EOF
  chmod +x "${STUB_BIN}/swift"
}

make_swift_stub_long_running_success() {
  cat > "${STUB_BIN}/swift" <<'EOF'
#!/usr/bin/env bash
echo "swift $*" >> "${CALLS_LOG}"
echo "VALVE_DISCOVERY_ENDPOINT=${VALVE_DISCOVERY_ENDPOINT:-}" >> "${CALLS_LOG}"
echo "MANIFOLD_UPLOAD_URL=${MANIFOLD_UPLOAD_URL:-}" >> "${CALLS_LOG}"
sleep 5
exit 0
EOF
  chmod +x "${STUB_BIN}/swift"
}

make_1psa_stub_for_discovery_endpoint() {
  cat > "${STUB_BIN}/1psa" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "-m" ] && [ "$2" = "VALVE_DISCOVERY_ENDPOINT" ] && [ "$3" = "protocol" ] && [ "$4" = "host" ] && [ "$5" = "port" ] && [ "$6" = "path" ]; then
  echo "protocol=https"
  echo "host=valve.example.com"
  echo "port=443"
  echo "path=/v1/piston/upload-target"
  exit 0
fi
exit 1
EOF
  chmod +x "${STUB_BIN}/1psa"
}

make_1psa_stub_for_discovery_and_credential() {
  cat > "${STUB_BIN}/1psa" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "-m" ] && [ "$2" = "VALVE_DISCOVERY_ENDPOINT" ] && [ "$3" = "protocol" ] && [ "$4" = "host" ] && [ "$5" = "port" ] && [ "$6" = "path" ]; then
  echo "protocol=https"
  echo "host=valve.example.com"
  echo "port=443"
  echo "path=/v1/piston/upload-target"
  exit 0
fi
if [ "$1" = "-f" ] && [ "$2" = "PISTON_INSTALL_CREDENTIAL" ] && [ "$3" = "password" ]; then
  echo "cred-from-1psa"
  exit 0
fi
exit 1
EOF
  chmod +x "${STUB_BIN}/1psa"
}

make_1psa_stub_for_http_discovery_protocol_only() {
  cat > "${STUB_BIN}/1psa" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "-f" ] && [ "$2" = "VALVE_DISCOVERY_ENDPOINT" ] && [ "$3" = "protocol" ]; then
  echo "http"
  exit 0
fi
exit 1
EOF
  chmod +x "${STUB_BIN}/1psa"
}

@test "Traceability tags for run-piston requirements" {
  #R001: Strict mode and script-root execution coverage.
  #R005: Required swift command and installer guidance coverage.
  #R010: Required discovery identity validation and env override coverage.
  #R015: Deterministic cache and startup default export coverage.
  #R020: Runner launch command invocation coverage.
  #R025: Detached runner pid output coverage.
  true
}

@test "R010: prints help when no args are passed" {
  run env PATH="${STUB_BIN}:/usr/bin:/bin" \
    bash "${FIXTURE_ROOT}/05_run_piston.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"--install-id <id>"* ]]
}

@test "R010: --help prints usage and exits successfully" {
  run env PATH="${STUB_BIN}:/usr/bin:/bin" \
    bash "${FIXTURE_ROOT}/05_run_piston.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"--install-id <id>"* ]]
}

@test "R010: allows no install identity when MANIFOLD_UPLOAD_URL uses http" {
  make_swift_stub_success
  run env PATH="${STUB_BIN}:/usr/bin:/bin" \
    MANIFOLD_UPLOAD_URL="http://localhost:8080/v1/events/batch" \
    bash "${FIXTURE_ROOT}/05_run_piston.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"target_source_hint=env"* ]]
  run python3 - "${CALLS_LOG}" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text(encoding="utf-8")
assert "swift run PistonRunner" in text
PY
  [ "$status" -eq 0 ]
}

@test "R010: requires install identity when MANIFOLD_UPLOAD_URL uses https" {
  make_swift_stub_success
  run env PATH="${STUB_BIN}:/usr/bin:/bin" \
    MANIFOLD_UPLOAD_URL="https://ingest.example.com/v1/events" \
    bash "${FIXTURE_ROOT}/05_run_piston.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
  [[ "$output" == *"--install-id <id>"* ]]
}

@test "R010: http discovery endpoint switches to relaxed local upload mode" {
  make_swift_stub_success
  run env PATH="${STUB_BIN}:/usr/bin:/bin" \
    VALVE_DISCOVERY_ENDPOINT="http://localhost:8090/v1/piston/upload-target" \
    bash "${FIXTURE_ROOT}/05_run_piston.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"target_source_hint=env"* ]]
  run python3 - "${CALLS_LOG}" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text(encoding="utf-8")
assert "swift run PistonRunner" in text
assert "MANIFOLD_UPLOAD_URL=http://localhost:8080/v1/events/batch" in text
PY
  [ "$status" -eq 0 ]
}

@test "R010: 1psa protocol=http switches to relaxed local upload mode" {
  make_swift_stub_success
  make_1psa_stub_for_http_discovery_protocol_only
  run env PATH="${STUB_BIN}:/usr/bin:/bin" \
    bash "${FIXTURE_ROOT}/05_run_piston.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"target_source_hint=env"* ]]
  run python3 - "${CALLS_LOG}" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text(encoding="utf-8")
assert "swift run PistonRunner" in text
assert "MANIFOLD_UPLOAD_URL=http://localhost:8080/v1/events/batch" in text
PY
  [ "$status" -eq 0 ]
}

@test "R001,R015: runs from outside cwd and emits deterministic cache hint" {
  make_swift_stub_success
  mkdir -p "${TMP_ROOT}/outside"
  run env PATH="${STUB_BIN}:/usr/bin:/bin" MANIFOLD_UPLOAD_URL="https://ingest.example.com/v1/events" PISTON_INSTALL_CREDENTIAL="cred-abc" \
    bash -c "cd '${TMP_ROOT}/outside' && bash '${FIXTURE_ROOT}/05_run_piston.sh' --install-id install-123"
  [ "$status" -eq 0 ]
  [[ "$output" == *"target_source_hint=env"* ]]
  [[ "$output" == *"${FIXTURE_ROOT}/.piston/upload-target-cache.json"* ]]
}

@test "R005: fails with installer guidance when swift is missing" {
  run env PATH="/bin" MANIFOLD_UPLOAD_URL="https://ingest.example.com/v1/events" \
    /bin/bash "${FIXTURE_ROOT}/05_run_piston.sh" --install-id install-123
  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing required command: swift"* ]]
  [[ "$output" == *"./01_install_prerequisites.sh"* ]]
}

@test "R010: fails when discovery inputs are missing and no env override is set" {
  make_swift_stub_success
  run env PATH="${STUB_BIN}:/usr/bin:/bin" \
    bash "${FIXTURE_ROOT}/05_run_piston.sh" --install-id install-123
  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing required env var: VALVE_DISCOVERY_ENDPOINT (or VALVE_DISCOVERY_URL)"* ]]
  [[ "$output" == *"must expose protocol/host/port/path"* ]]
}

@test "R010: gives credential-specific hint when install-id looks like credential token" {
  make_swift_stub_success
  run env PATH="${STUB_BIN}:/usr/bin:/bin" \
    VALVE_DISCOVERY_ENDPOINT="https://valve.example.com/v1/piston/upload-target" \
    bash "${FIXTURE_ROOT}/05_run_piston.sh" --install-id cred_guesjzqoaqmmw265r44l24scku
  [ "$status" -eq 1 ]
  [[ "$output" == *"looks like a credential token (cred_*)"* ]]
  [[ "$output" == *"--install-credential <cred_...>"* ]]
}

@test "R010,R020: starts runner with discovery vars set" {
  make_swift_stub_success
  run env PATH="${STUB_BIN}:/usr/bin:/bin" \
    VALVE_DISCOVERY_ENDPOINT="https://valve.example.com/v1/piston/upload-target" \
    PISTON_INSTALL_CREDENTIAL="cred-abc" \
    bash "${FIXTURE_ROOT}/05_run_piston.sh" --install-id install-123
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

@test "R010,R020: resolves discovery endpoint from 1psa when env var is unset" {
  make_swift_stub_success
  make_1psa_stub_for_discovery_endpoint
  run env PATH="${STUB_BIN}:/usr/bin:/bin" \
    PISTON_INSTALL_CREDENTIAL="cred-abc" \
    bash "${FIXTURE_ROOT}/05_run_piston.sh" --install-id install-123
  [ "$status" -eq 0 ]
  [[ "$output" == *"target_source_hint=discovery"* ]]
  run python3 - "${CALLS_LOG}" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text(encoding="utf-8")
assert "swift run PistonRunner" in text
assert "VALVE_DISCOVERY_ENDPOINT=https://valve.example.com:443/v1/piston/upload-target" in text
PY
  [ "$status" -eq 0 ]
}

@test "R010,R020: resolves install credential from 1psa when env var is unset" {
  make_swift_stub_success
  make_1psa_stub_for_discovery_and_credential
  run env PATH="${STUB_BIN}:/usr/bin:/bin" \
    bash "${FIXTURE_ROOT}/05_run_piston.sh" --install-id install-123
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
    PISTON_INSTALL_CREDENTIAL="cred-abc" \
    bash "${FIXTURE_ROOT}/05_run_piston.sh" --install-id install-123
  [ "$status" -eq 0 ]
  [[ "$output" == *"${TMP_ROOT}/custom-cache/upload-target-cache.json"* ]]
}

@test "R025: prints detached runner pid for long-running process" {
  make_swift_stub_long_running_success
  run env PATH="${STUB_BIN}:/usr/bin:/bin" \
    MANIFOLD_UPLOAD_URL="http://localhost:8080/v1/events/batch" \
    bash "${FIXTURE_ROOT}/05_run_piston.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"runner_detached_pid="* ]]
  [[ "$output" == *"runner_log="* ]]
  detached_pid="$(echo "$output" | awk -F= '/runner_detached_pid=/{print $2; exit}')"
  kill -0 "${detached_pid}" >/dev/null 2>&1
  [ "$?" -eq 0 ]
  kill "${detached_pid}" >/dev/null 2>&1 || true
}
