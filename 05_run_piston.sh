#!/usr/bin/env bash
umask 007
#R001: Run in strict fail-fast mode from repository root.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

#R005: Require swift toolchain to launch the Piston runner.
require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: ${command_name}"
    echo "Install prerequisites with: ./01_install_prerequisites.sh"
    exit 1
  fi
}

#R010: Print CLI help for argument-driven startup contract.
print_help() {
  cat <<'EOF'
Usage:
  ./05_run_piston.sh --install-id <id>
  ./05_run_piston.sh --install-id <id> --install-credential <credential>
  ./05_run_piston.sh --help

Required arguments:
  --install-id <id>               Piston install ID used for upload-target resolution.

Optional arguments:
  --install-credential <value>    Install credential used for discovery and upload auth.
                                  If omitted, the script tries env/1psa fallback.

Credential resolution order:
  1) --install-credential argument
  2) PISTON_INSTALL_CREDENTIAL environment variable
  3) 1psa lookup using item PISTON_INSTALL_CREDENTIAL and field password
  4) 1psa lookup using item named after --install-id and field password

Discovery endpoint:
  Set VALVE_DISCOVERY_ENDPOINT (preferred) or VALVE_DISCOVERY_URL.
  If neither is set, the script attempts 1psa lookup from item VALVE_DISCOVERY_ENDPOINT
  using fields protocol, host, and port.
EOF
}

#R010: Parse CLI arguments and enforce required install-id argument.
is_http_url() {
  local value="${1:-}"
  [[ "${value}" == http://* ]]
}

resolved_discovery_url() {
  if [[ -n "${VALVE_DISCOVERY_ENDPOINT:-}" ]]; then
    echo "${VALVE_DISCOVERY_ENDPOINT}"
    return 0
  fi
  if [[ -n "${VALVE_DISCOVERY_URL:-}" ]]; then
    echo "${VALVE_DISCOVERY_URL}"
    return 0
  fi
  echo ""
}

resolved_discovery_protocol_from_1psa() {
  local item_name="${PISTON_VALVE_DISCOVERY_PSA_ITEM:-VALVE_DISCOVERY_ENDPOINT}"
  local protocol_field="${PISTON_VALVE_DISCOVERY_PSA_PROTOCOL_FIELD:-protocol}"
  local protocol

  if ! command -v 1psa >/dev/null 2>&1; then
    echo ""
    return 0
  fi

  protocol="$(1psa -f "$item_name" "$protocol_field" 2>/dev/null || true)"
  protocol="${protocol//[$'\r\n\t ']/}"
  echo "${protocol}"
}

is_insecure_http_mode() {
  local upload_url="${MANIFOLD_UPLOAD_URL:-}"
  if is_http_url "${upload_url}"; then
    return 0
  fi

  local discovery_url
  discovery_url="$(resolved_discovery_url)"
  if is_http_url "${discovery_url}"; then
    return 0
  fi

  local discovery_protocol
  discovery_protocol="$(resolved_discovery_protocol_from_1psa)"
  if [[ "${discovery_protocol}" == "http" ]]; then
    return 0
  fi

  return 1
}

parse_args() {
  local install_id_arg_set=false

  if [[ $# -eq 0 ]]; then
    if is_insecure_http_mode; then
      return 0
    fi
    print_help
    exit 1
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        print_help
        exit 0
        ;;
      --install-id)
        if [[ $# -lt 2 || -z "${2:-}" || "${2}" == --* ]]; then
          echo "Missing value for required argument: --install-id"
          print_help
          exit 1
        fi
        export PISTON_INSTALL_ID="$2"
        install_id_arg_set=true
        shift 2
        ;;
      --install-credential)
        if [[ $# -lt 2 || -z "${2:-}" || "${2}" == --* ]]; then
          echo "Missing value for argument: --install-credential"
          print_help
          exit 1
        fi
        export PISTON_INSTALL_CREDENTIAL="$2"
        shift 2
        ;;
      *)
        echo "Unknown argument: $1"
        print_help
        exit 1
        ;;
    esac
  done

  if [[ "$install_id_arg_set" != "true" ]]; then
    if is_insecure_http_mode; then
      return 0
    fi
    echo "Missing required argument: --install-id"
    print_help
    exit 1
  fi
}

#R010: Resolve discovery endpoint from 1psa when env var is unset.
resolve_discovery_endpoint_from_1psa() {
  local item_name="${PISTON_VALVE_DISCOVERY_PSA_ITEM:-VALVE_DISCOVERY_ENDPOINT}"
  local protocol_field="${PISTON_VALVE_DISCOVERY_PSA_PROTOCOL_FIELD:-protocol}"
  local host_field="${PISTON_VALVE_DISCOVERY_PSA_HOST_FIELD:-host}"
  local port_field="${PISTON_VALVE_DISCOVERY_PSA_PORT_FIELD:-port}"
  local path_field="${PISTON_VALVE_DISCOVERY_PSA_PATH_FIELD:-path}"
  local output protocol host port path

  if ! command -v 1psa >/dev/null 2>&1; then
    return 1
  fi

  if ! output="$(1psa -m "$item_name" "$protocol_field" "$host_field" "$port_field" "$path_field" 2>/dev/null)"; then
    return 1
  fi

  while IFS='=' read -r key value; do
    case "$key" in
      "$protocol_field") protocol="$value" ;;
      "$host_field") host="$value" ;;
      "$port_field") port="$value" ;;
      "$path_field") path="$value" ;;
    esac
  done <<< "$output"

  if [[ -z "${protocol:-}" || -z "${host:-}" || -z "${port:-}" || -z "${path:-}" ]]; then
    return 1
  fi

  if [[ "${path}" != /* ]]; then
    path="/${path}"
  fi

  echo "${protocol}://${host}:${port}${path}"
}

#R010: Resolve install credential from 1psa when env var is unset.
resolve_install_credential_from_1psa() {
  local install_id="$1"
  local item_name="${PISTON_INSTALL_CREDENTIAL_PSA_ITEM:-PISTON_INSTALL_CREDENTIAL}"
  local field_name="${PISTON_INSTALL_CREDENTIAL_PSA_FIELD:-password}"
  local credential

  if ! command -v 1psa >/dev/null 2>&1; then
    return 1
  fi

  credential="$(1psa -f "$item_name" "$field_name" 2>/dev/null || true)"
  if [[ -n "${credential}" ]]; then
    echo "${credential}"
    return 0
  fi

  credential="$(1psa -f "$install_id" "$field_name" 2>/dev/null || true)"
  if [[ -n "${credential}" ]]; then
    echo "${credential}"
    return 0
  fi

  return 1
}

resolve_fountain_db_path_from_local_heartbeat_state() {
  local fountain_root="${SCRIPT_DIR}/../fountain"
  local state_file="${fountain_root}/.heartbeat/heartbeat.state"
  local relative_db_path

  if [[ ! -f "${state_file}" ]]; then
    return 1
  fi

  relative_db_path="$(awk -F= '/^heartbeat_database_path=/{print $2; exit}' "${state_file}")"
  if [[ -z "${relative_db_path}" ]]; then
    return 1
  fi

  if [[ "${relative_db_path}" == /* ]]; then
    echo "${relative_db_path}"
    return 0
  fi

  echo "${fountain_root}/${relative_db_path}"
}

#R010: Validate startup identity/discovery inputs unless URL override is set.
validate_inputs() {
  if is_insecure_http_mode; then
    if [[ -z "${MANIFOLD_UPLOAD_URL:-}" ]]; then
      export MANIFOLD_UPLOAD_URL="${PISTON_DEV_MANIFOLD_UPLOAD_URL:-http://localhost:8080/v1/events/batch}"
    fi
    export PISTON_INSTALL_ID="${PISTON_INSTALL_ID:-dev-http-install}"
    export PISTON_INSTALL_CREDENTIAL="${PISTON_INSTALL_CREDENTIAL:-dev-http-credential}"
    return 0
  fi

  if [[ -n "${MANIFOLD_UPLOAD_URL:-}" ]]; then
    if [[ -z "${PISTON_INSTALL_ID:-}" ]]; then
      echo "Missing required identity in lockdown mode: set --install-id or PISTON_INSTALL_ID."
      exit 1
    fi
    if [[ -z "${PISTON_INSTALL_CREDENTIAL:-}" ]]; then
      echo "Missing required install credential in lockdown mode: set --install-credential or PISTON_INSTALL_CREDENTIAL."
      exit 1
    fi
    return 0
  fi

  local discovery_endpoint="${VALVE_DISCOVERY_ENDPOINT:-${VALVE_DISCOVERY_URL:-}}"
  if [[ -z "${discovery_endpoint}" ]]; then
    discovery_endpoint="$(resolve_discovery_endpoint_from_1psa || true)"
  fi
  if [[ -z "${discovery_endpoint}" ]]; then
    echo "Missing required env var: VALVE_DISCOVERY_ENDPOINT (or VALVE_DISCOVERY_URL)"
    echo "If using 1psa fallback, item VALVE_DISCOVERY_ENDPOINT must expose protocol/host/port/path."
    exit 1
  fi
  export VALVE_DISCOVERY_ENDPOINT="${discovery_endpoint}"
  export VALVE_DISCOVERY_URL="${discovery_endpoint}"

  local install_credential="${PISTON_INSTALL_CREDENTIAL:-}"
  if [[ -z "${install_credential}" ]]; then
    install_credential="$(resolve_install_credential_from_1psa "${PISTON_INSTALL_ID}" || true)"
  fi
  if [[ -z "${install_credential}" ]]; then
    if [[ "${PISTON_INSTALL_ID}" == cred_* ]]; then
      echo "Missing required install credential. '--install-id' value looks like a credential token (cred_*)."
      echo "Use: ./05_run_piston.sh --install-id <install-id> --install-credential <cred_...>"
    else
      echo "Missing required install credential: set --install-credential, PISTON_INSTALL_CREDENTIAL, or configure 1psa item PISTON_INSTALL_CREDENTIAL (field password)."
    fi
    exit 1
  fi
  export PISTON_INSTALL_CREDENTIAL="${install_credential}"
}

#R015: Set deterministic cache defaults for discovery fallback behavior.
CACHE_DIR="${PISTON_CACHE_DIR:-${SCRIPT_DIR}/.piston}"
export PISTON_UPLOAD_TARGET_CACHE="${PISTON_UPLOAD_TARGET_CACHE:-${CACHE_DIR}/upload-target-cache.json}"
export PISTON_RUNNER_LOG="${PISTON_RUNNER_LOG:-${CACHE_DIR}/piston-runner.log}"
export PISTON_DISCOVERY_TIMEOUT_SECONDS="${PISTON_DISCOVERY_TIMEOUT_SECONDS:-8}"
export PISTON_STALE_CACHE_GRACE_SECONDS="${PISTON_STALE_CACHE_GRACE_SECONDS:-300}"
export PISTON_MIN_UPLOAD_INTERVAL_SECONDS="${PISTON_MIN_UPLOAD_INTERVAL_SECONDS:-30}"

if [[ -z "${PISTON_FOUNTAIN_DB_PATH:-}" ]]; then
  PISTON_FOUNTAIN_DB_PATH="$(resolve_fountain_db_path_from_local_heartbeat_state || true)"
  if [[ -n "${PISTON_FOUNTAIN_DB_PATH}" ]]; then
    export PISTON_FOUNTAIN_DB_PATH
  fi
fi

mkdir -p "$CACHE_DIR"

parse_args "$@"
require_command swift
validate_inputs

resolved_source="discovery"
if [[ -n "${MANIFOLD_UPLOAD_URL:-}" ]]; then
  resolved_source="env"
fi
echo "Piston startup: target_source_hint=${resolved_source} cache=${PISTON_UPLOAD_TARGET_CACHE}"
if [[ -n "${PISTON_FOUNTAIN_DB_PATH:-}" ]]; then
  echo "Piston startup: fountain_db=${PISTON_FOUNTAIN_DB_PATH}"
fi

#R020: Start the resolver-backed runner that boots PistonUploader.
#R025: Detach long-running runner and print PID for operator visibility.
start_runner() {
  nohup swift run PistonRunner >> "${PISTON_RUNNER_LOG}" 2>&1 &
  local runner_pid=$!

  sleep 0.1
  if ! kill -0 "${runner_pid}" >/dev/null 2>&1; then
    wait "${runner_pid}"
    return $?
  fi

  disown "${runner_pid}" 2>/dev/null || true
  echo "Piston startup: runner_detached_pid=${runner_pid}"
  echo "Piston startup: runner_log=${PISTON_RUNNER_LOG}"
}

start_runner
