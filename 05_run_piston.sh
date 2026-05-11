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

#R010: Validate startup identity/discovery inputs unless URL override is set.
validate_inputs() {
  if [[ -n "${MANIFOLD_UPLOAD_URL:-}" ]]; then
    return 0
  fi

  if [[ -z "${VALVE_DISCOVERY_URL:-}" ]]; then
    echo "Missing required env var: VALVE_DISCOVERY_URL"
    exit 1
  fi
  if [[ -z "${PISTON_INSTALL_ID:-}" ]]; then
    echo "Missing required env var: PISTON_INSTALL_ID"
    exit 1
  fi
  if [[ -z "${PISTON_INSTALL_CREDENTIAL:-}" ]]; then
    echo "Missing required env var: PISTON_INSTALL_CREDENTIAL"
    exit 1
  fi
}

#R015: Set deterministic cache defaults for discovery fallback behavior.
CACHE_DIR="${PISTON_CACHE_DIR:-${SCRIPT_DIR}/.piston}"
export PISTON_UPLOAD_TARGET_CACHE="${PISTON_UPLOAD_TARGET_CACHE:-${CACHE_DIR}/upload-target-cache.json}"
export PISTON_DISCOVERY_TIMEOUT_SECONDS="${PISTON_DISCOVERY_TIMEOUT_SECONDS:-8}"
export PISTON_STALE_CACHE_GRACE_SECONDS="${PISTON_STALE_CACHE_GRACE_SECONDS:-300}"
export PISTON_MIN_UPLOAD_INTERVAL_SECONDS="${PISTON_MIN_UPLOAD_INTERVAL_SECONDS:-30}"

mkdir -p "$CACHE_DIR"

require_command swift
validate_inputs

resolved_source="discovery"
if [[ -n "${MANIFOLD_UPLOAD_URL:-}" ]]; then
  resolved_source="env"
fi
echo "Piston startup: target_source_hint=${resolved_source} cache=${PISTON_UPLOAD_TARGET_CACHE}"

#R020: Start the resolver-backed runner that boots PistonUploader.
swift run PistonRunner
