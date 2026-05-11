#!/usr/bin/env bash
umask 007
#R001: Run in strict fail-fast mode from repository root.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

REPORT_DIR="${SECURITY_REPORT_DIR:-./.security-reports}"
RUN_CLAMAV="${RUN_CLAMAV:-true}"
CLAMAV_SCAN_TARGET="${CLAMAV_SCAN_TARGET:-.}"
CLAMAV_SIGNATURE_MAX_AGE_HOURS="${CLAMAV_SIGNATURE_MAX_AGE_HOURS:-48}"
CLAMAV_HEARTBEAT_SECONDS="${CLAMAV_HEARTBEAT_SECONDS:-15}"
CLAMAV_POLL_SECONDS="${CLAMAV_POLL_SECONDS:-1}"
FAIL_ON_HIGH_CRITICAL="${SECURITY_FAIL_ON_HIGH_CRITICAL:-true}"

CLAMAV_LOG="${REPORT_DIR}/clamav.log"
CLAMAV_SUMMARY="${REPORT_DIR}/clamav-summary.json"
FRESHCLAM_LOG="${REPORT_DIR}/clamav.log.freshclam.log"

mkdir -p "$REPORT_DIR"

require_command() {
  local command_name="$1"
  #R005: Fail fast with installer guidance when required commands are missing.
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: ${command_name}"
    echo "Install prerequisites with: ./01_install_prerequisites.sh"
    exit 1
  fi
}

normalize_positive_int() {
  local value="$1"
  local fallback="$2"
  if [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -ge 1 ]; then
    echo "$value"
    return 0
  fi
  echo "$fallback"
}

detect_clamav_db_dir() {
  #R020: Detect ClamAV database directory for signature freshness reporting.
  if [ -n "${CLAMAV_DB_DIR:-}" ] && [ -d "${CLAMAV_DB_DIR}" ]; then
    echo "${CLAMAV_DB_DIR}"
    return 0
  fi

  if command -v brew >/dev/null 2>&1; then
    local brew_prefix=""
    brew_prefix="$(brew --prefix 2>/dev/null || true)"
    if [ -n "$brew_prefix" ] && [ -d "${brew_prefix}/var/lib/clamav" ]; then
      echo "${brew_prefix}/var/lib/clamav"
      return 0
    fi
  fi

  if [ -d "/var/lib/clamav" ]; then
    echo "/var/lib/clamav"
    return 0
  fi

  echo ""
}

print_signature_freshness() {
  local db_dir="$1"
  #R020: Print signature freshness details before scan execution.
  if [ -z "$db_dir" ]; then
    echo "ClamAV signature freshness: unknown (database directory not found)"
    return 0
  fi

  python3 - "$db_dir" "$CLAMAV_SIGNATURE_MAX_AGE_HOURS" <<'PY'
import glob
import os
import sys
import time

db_dir = sys.argv[1]
max_age_hours = int(sys.argv[2]) if sys.argv[2].isdigit() else 48
patterns = ("*.cvd", "*.cld", "*.inc")
paths = []
for pattern in patterns:
    paths.extend(glob.glob(os.path.join(db_dir, pattern)))

if not paths:
    print(f"ClamAV signature freshness: unknown (no signatures found in {db_dir})")
    print("Refresh signatures with: freshclam --stdout")
    raise SystemExit(0)

latest_mtime = max(os.path.getmtime(path) for path in paths)
age_hours = (time.time() - latest_mtime) / 3600.0
status = "fresh" if age_hours <= max_age_hours else "stale"
print(
    "ClamAV signature freshness: "
    f"{age_hours:.1f}h old ({status}, threshold {max_age_hours}h, db {db_dir})"
)
if status == "stale":
    print("ClamAV signatures appear out of date.")
    print("Refresh signatures with: freshclam --stdout")
PY
}

run_clamscan_once() {
  local report_path="$1"
  local scan_target="$2"
  local heartbeat_seconds="$3"
  local poll_seconds="$4"
  local clamscan_exit=0

  #R015: Run recursive ClamAV scan and write command output to report log.
  clamscan \
    --recursive \
    --infected \
    --exclude-dir='^\.git$' \
    --exclude-dir='^\.security-reports$' \
    --exclude-dir='^node_modules$' \
    --exclude-dir='^\.venv$' \
    --exclude-dir='^venv$' \
    --exclude-dir='^\.pytest_cache$' \
    --exclude-dir='^\.mypy_cache$' \
    --exclude-dir='^\.gomodcache$' \
    "${scan_target}" >"${report_path}" 2>&1 &
  local clamscan_pid=$!
  local start_epoch
  local next_heartbeat=0
  start_epoch="$(date +%s)"
  next_heartbeat="$heartbeat_seconds"

  #R025: Emit heartbeat progress while long-running scans execute.
  while kill -0 "$clamscan_pid" >/dev/null 2>&1; do
    local now elapsed
    now="$(date +%s)"
    elapsed=$((now - start_epoch))
    if [ "$elapsed" -ge "$next_heartbeat" ]; then
      echo "ClamAV scan in progress (${elapsed}s elapsed)"
      next_heartbeat=$((next_heartbeat + heartbeat_seconds))
    fi
    sleep "$poll_seconds"
  done

  wait "$clamscan_pid"
  clamscan_exit=$?

  cat "${report_path}"
  return "$clamscan_exit"
}

write_summary_json() {
  local report_path="$1"
  local summary_path="$2"
  local scan_exit="$3"
  local skipped="$4"
  local fail_on_high="$5"
  #R030: Persist machine-readable ClamAV summary and optional gate result.
  python3 - "$report_path" "$summary_path" "$scan_exit" "$skipped" "$fail_on_high" <<'PY'
import json
import re
import sys
from pathlib import Path

report_path = Path(sys.argv[1])
summary_path = Path(sys.argv[2])
scan_exit = int(sys.argv[3])
skipped = sys.argv[4].lower() == "true"
fail_on_high = sys.argv[5].lower() == "true"

scanned_files = 0
infected_files = 0
if report_path.exists():
    text = report_path.read_text(encoding="utf-8", errors="replace")
    scanned_match = re.search(r"Scanned files:\s*([0-9]+)", text)
    infected_match = re.search(r"Infected files:\s*([0-9]+)", text)
    if scanned_match:
        scanned_files = int(scanned_match.group(1))
    if infected_match:
        infected_files = int(infected_match.group(1))
    elif scan_exit == 1:
        infected_files = 1

gate_failed = (not skipped) and fail_on_high and infected_files > 0
payload = {
    "scanned_files": scanned_files,
    "infected_files": infected_files,
    "exit_code": scan_exit,
    "skipped": skipped,
    "gate_failed": gate_failed,
}
summary_path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
print("Antivirus (ClamAV) summary")
print(json.dumps(payload, indent=2))
if gate_failed:
    print("Antivirus (ClamAV) gate failed: infected files detected.")
    raise SystemExit(1)
PY
}

run_clamav_lane() {
  #R010: Allow explicit skip behavior while still emitting deterministic artifacts.
  if [[ "$RUN_CLAMAV" != "true" ]]; then
    : > "$CLAMAV_LOG"
    write_summary_json "$CLAMAV_LOG" "$CLAMAV_SUMMARY" 0 true false
    echo "ClamAV lane skipped."
    return 0
  fi

  require_command clamscan
  require_command python3

  CLAMAV_HEARTBEAT_SECONDS="$(normalize_positive_int "$CLAMAV_HEARTBEAT_SECONDS" 15)"
  CLAMAV_POLL_SECONDS="$(normalize_positive_int "$CLAMAV_POLL_SECONDS" 1)"

  local resolved_target
  resolved_target="$(python3 - "$CLAMAV_SCAN_TARGET" <<'PY'
import os
import sys
print(os.path.abspath(sys.argv[1]))
PY
)"
  #R035: Fail clearly when configured scan targets do not exist.
  if [ ! -e "$resolved_target" ]; then
    echo "ClamAV scan target not found: ${resolved_target}"
    exit 1
  fi

  local db_dir
  db_dir="$(detect_clamav_db_dir)"
  echo "Running ClamAV scan"
  echo "ClamAV scan target: ${resolved_target}"
  print_signature_freshness "$db_dir"

  local clamscan_exit
  set +e
  run_clamscan_once "$CLAMAV_LOG" "$resolved_target" "$CLAMAV_HEARTBEAT_SECONDS" "$CLAMAV_POLL_SECONDS"
  clamscan_exit=$?
  set -e

  #R040: Refresh signatures and retry once when ClamAV reports missing database files.
  if [ "$clamscan_exit" -gt 1 ] && python3 - "$CLAMAV_LOG" <<'PY'
from pathlib import Path
import sys

text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
raise SystemExit(0 if "No supported database files found" in text else 1)
PY
  then
    require_command freshclam
    echo "ClamAV database missing; attempting one-time database refresh with freshclam --stdout."
    set +e
    freshclam --stdout | tee "$FRESHCLAM_LOG"
    set -e
    echo "Retrying ClamAV repository scan after freshclam refresh."
    set +e
    run_clamscan_once "$CLAMAV_LOG" "$resolved_target" "$CLAMAV_HEARTBEAT_SECONDS" "$CLAMAV_POLL_SECONDS"
    clamscan_exit=$?
    set -e
  fi

  #R045: Treat ClamAV exit codes above 1 as execution errors.
  if [ "$clamscan_exit" -gt 1 ]; then
    write_summary_json "$CLAMAV_LOG" "$CLAMAV_SUMMARY" "$clamscan_exit" false false
    echo "ClamAV failed to execute."
    exit 1
  fi

  if [ "$clamscan_exit" -eq 1 ]; then
    echo "ClamAV detected infected files; gate evaluation will determine pass/fail."
  fi

  write_summary_json "$CLAMAV_LOG" "$CLAMAV_SUMMARY" "$clamscan_exit" false "$FAIL_ON_HIGH_CRITICAL"
  echo "Antivirus (ClamAV) checks completed."
}

run_clamav_lane

#R050: Emit deterministic completion output including report directory.
echo "AV checks completed. Reports: ${REPORT_DIR}"
