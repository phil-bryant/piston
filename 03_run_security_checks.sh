#!/usr/bin/env bash
umask 007
#R001: Run in strict shell mode and operate from repository root.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

#R005: Support configurable report directory, lanes, and gate behavior.
REPORT_DIR="${SECURITY_REPORT_DIR:-./.security-reports}"
RUN_SHELLCHECK="${RUN_SHELLCHECK:-true}"
RUN_SEMGREP="${RUN_SEMGREP:-true}"
RUN_GITLEAKS="${RUN_GITLEAKS:-true}"
FAIL_ON_FINDINGS="${SECURITY_FAIL_ON_FINDINGS:-true}"

mkdir -p "$REPORT_DIR"

#R010: Validate required command presence for enabled lanes.
require_command() {
  local command_name="$1"
  local install_hint="$2"
  if command -v "$command_name" >/dev/null 2>&1; then
    return 0
  fi
  echo "❌ Missing required command: ${command_name}"
  echo "Install prerequisites with ./01_install_prerequisites.sh or ${install_hint}"
  exit 1
}

#R015: Run ShellCheck on repo shell automation and persist JSON report.
run_shellcheck_lane() {
  local shellcheck_report_path="$1"
  local shellcheck_targets=()
  local shellcheck_exit=0
  for candidate in ./*.sh ./Tests/sh/*.bats; do
    if [[ -f "$candidate" ]]; then
      shellcheck_targets+=("$candidate")
    fi
  done
  if [[ "${#shellcheck_targets[@]}" -eq 0 ]]; then
    printf '[]\n' > "$shellcheck_report_path"
    echo "ℹ️  ShellCheck skipped: no shell targets discovered."
    return 0
  fi
  require_command "shellcheck" "brew install shellcheck"
  echo "▶ Running ShellCheck"
  set +e
  shellcheck -f json "${shellcheck_targets[@]}" > "$shellcheck_report_path"
  shellcheck_exit=$?
  set -e
  if [[ "$shellcheck_exit" -gt 1 ]]; then
    echo "❌ ShellCheck failed to execute."
    exit 1
  fi
  if [[ "$shellcheck_exit" -eq 1 ]]; then
    echo "⚠️  ShellCheck reported findings."
    python3 - <<'PY' "$shellcheck_report_path"
import json
import sys
from pathlib import Path

report_path = Path(sys.argv[1])
payload = json.loads(report_path.read_text(encoding="utf-8")) if report_path.exists() else []
if not isinstance(payload, list):
    payload = []
print("ShellCheck findings")
for finding in payload:
    file_path = str(finding.get("file", "unknown"))
    line = int(finding.get("line", 0))
    code = str(finding.get("code", "unknown"))
    message = str(finding.get("message", "")).strip()
    level = str(finding.get("level", "warning"))
    print(f"- [{level}] {file_path}:{line} SC{code} {message}")
PY
  fi
}

#R020: Run Semgrep and persist JSON report.
run_semgrep_lane() {
  local semgrep_report_path="$1"
  local semgrep_exit=0
  require_command "semgrep" "brew install semgrep"
  echo "▶ Running Semgrep"
  set +e
  semgrep scan --config auto --json --output "$semgrep_report_path" .
  semgrep_exit=$?
  set -e
  if [[ "$semgrep_exit" -gt 1 ]]; then
    echo "❌ Semgrep failed to execute."
    exit 1
  fi
  if [[ "$semgrep_exit" -eq 1 ]]; then
    echo "⚠️  Semgrep reported findings."
  fi
}

#R025: Run Gitleaks and persist JSON report.
run_gitleaks_lane() {
  local gitleaks_report_path="$1"
  local gitleaks_exit=0
  require_command "gitleaks" "brew install gitleaks"
  echo "▶ Running Gitleaks"
  set +e
  gitleaks detect --source . --no-banner --report-format json --report-path "$gitleaks_report_path"
  gitleaks_exit=$?
  set -e
  if [[ "$gitleaks_exit" -gt 1 ]]; then
    echo "❌ Gitleaks failed to execute."
    exit 1
  fi
  if [[ "$gitleaks_exit" -eq 1 ]]; then
    echo "⚠️  Gitleaks reported findings."
  fi
}

#R030: Aggregate lane findings into summary and enforce fail-on-findings policy.
emit_summary_and_gate() {
  local report_dir="$1"
  local fail_on_findings="$2"
  python3 - <<'PY' "$report_dir" "$fail_on_findings"
import json
import sys
from pathlib import Path

report_dir = Path(sys.argv[1])
fail_on_findings = sys.argv[2].lower() == "true"

def count_shellcheck(path: Path) -> int:
    if not path.exists():
        return 0
    payload = json.loads(path.read_text(encoding="utf-8"))
    return len(payload) if isinstance(payload, list) else 0

def count_semgrep(path: Path) -> int:
    if not path.exists():
        return 0
    payload = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(payload, dict) and isinstance(payload.get("results"), list):
        return len(payload["results"])
    return 0

def count_gitleaks(path: Path) -> int:
    if not path.exists():
        return 0
    payload = json.loads(path.read_text(encoding="utf-8"))
    return len(payload) if isinstance(payload, list) else 0

shellcheck_count = count_shellcheck(report_dir / "shellcheck.json")
semgrep_count = count_semgrep(report_dir / "semgrep.json")
gitleaks_count = count_gitleaks(report_dir / "gitleaks.json")
total_findings = shellcheck_count + semgrep_count + gitleaks_count

summary = {
    "shellcheck_findings": shellcheck_count,
    "semgrep_findings": semgrep_count,
    "gitleaks_findings": gitleaks_count,
    "total_findings": total_findings,
    "gate_failed": fail_on_findings and total_findings > 0,
}

summary_path = report_dir / "security-summary.json"
summary_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
print("Security summary")
print(json.dumps(summary, indent=2))

if summary["gate_failed"]:
    print("❌ Security checks failed: findings detected with SECURITY_FAIL_ON_FINDINGS=true.")
    raise SystemExit(1)
PY
}

if [[ "$RUN_SHELLCHECK" == "true" ]]; then
  run_shellcheck_lane "${REPORT_DIR}/shellcheck.json"
fi

if [[ "$RUN_SEMGREP" == "true" ]]; then
  run_semgrep_lane "${REPORT_DIR}/semgrep.json"
fi

if [[ "$RUN_GITLEAKS" == "true" ]]; then
  run_gitleaks_lane "${REPORT_DIR}/gitleaks.json"
fi

emit_summary_and_gate "$REPORT_DIR" "$FAIL_ON_FINDINGS"
echo "✅ Security checks completed. Reports: ${REPORT_DIR}"
