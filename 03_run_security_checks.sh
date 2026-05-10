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
RUN_DETECT_SECRETS="${RUN_DETECT_SECRETS:-true}"
RUN_SWIFTLINT="${RUN_SWIFTLINT:-true}"
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

#R045: Print manifold-style tool explainer header before each lane execution.
print_tool_header() {
  local tool_name="$1"
  local explainer_line_1="$2"
  local explainer_line_2="$3"
  local tool_url="$4"
  local border="+==============================================================================+"
  printf '%s\n' "$border"
  printf '| %-76s |\n' "Security Tool: ${tool_name}"
  printf '| %-76s |\n' "${explainer_line_1}"
  printf '| %-76s |\n' "${explainer_line_2}"
  printf '| %-76s |\n' "URL: ${tool_url}"
  printf '%s\n' "$border"
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
  print_tool_header \
    "ShellCheck" \
    "Static linting for shell scripts with security and reliability checks." \
    "Flags risky shell patterns, quoting bugs, and execution pitfalls." \
    "https://www.shellcheck.net/"
  echo "Report: ${shellcheck_report_path}"
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
  print_tool_header \
    "Semgrep" \
    "Static pattern-based scanning for security and correctness issues." \
    "Uses curated security rules against the repository source tree." \
    "https://semgrep.dev/docs/"
  echo "Report: ${semgrep_report_path}"
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
  print_tool_header \
    "Gitleaks" \
    "Scans repository content for hard-coded secrets and credentials." \
    "Detects leaked tokens, keys, and other sensitive data patterns." \
    "https://github.com/gitleaks/gitleaks"
  echo "Report: ${gitleaks_report_path}"
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

#R035: Run detect-secrets and persist JSON report.
run_detect_secrets_lane() {
  local detect_secrets_report_path="$1"
  local detect_secrets_exit=0
  print_tool_header \
    "detect-secrets" \
    "Scans repository files for high-entropy and known secret formats." \
    "Helps catch accidentally committed credentials before release." \
    "https://github.com/Yelp/detect-secrets"
  echo "Report: ${detect_secrets_report_path}"
  require_command "detect-secrets" "pip install detect-secrets"
  echo "▶ Running detect-secrets"
  set +e
  detect-secrets scan --all-files > "$detect_secrets_report_path"
  detect_secrets_exit=$?
  set -e
  if [[ "$detect_secrets_exit" -ne 0 ]]; then
    echo "❌ detect-secrets failed to execute."
    exit 1
  fi
}

#R040: Run SwiftLint in JSON mode and persist report.
run_swiftlint_lane() {
  local swiftlint_report_path="$1"
  local swiftlint_exit=0
  print_tool_header \
    "SwiftLint" \
    "Static linting for Swift style and safety diagnostics." \
    "Flags style violations and risky coding patterns in Swift files." \
    "https://github.com/realm/SwiftLint"
  echo "Report: ${swiftlint_report_path}"
  require_command "swiftlint" "brew install swiftlint"
  echo "▶ Running SwiftLint"
  set +e
  swiftlint lint --reporter json > "$swiftlint_report_path"
  swiftlint_exit=$?
  set -e
  if [[ "$swiftlint_exit" -gt 1 ]]; then
    echo "❌ SwiftLint failed to execute."
    exit 1
  fi
  if [[ "$swiftlint_exit" -eq 1 ]]; then
    echo "⚠️  SwiftLint reported findings."
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

def count_detect_secrets(path: Path) -> int:
    if not path.exists():
        return 0
    payload = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(payload, dict) and isinstance(payload.get("results"), dict):
        findings = 0
        for file_findings in payload["results"].values():
            if isinstance(file_findings, list):
                findings += len(file_findings)
        return findings
    return 0

def count_swiftlint(path: Path) -> int:
    if not path.exists():
        return 0
    payload = json.loads(path.read_text(encoding="utf-8"))
    return len(payload) if isinstance(payload, list) else 0

shellcheck_count = count_shellcheck(report_dir / "shellcheck.json")
semgrep_count = count_semgrep(report_dir / "semgrep.json")
gitleaks_count = count_gitleaks(report_dir / "gitleaks.json")
detect_secrets_count = count_detect_secrets(report_dir / "detect-secrets.json")
swiftlint_count = count_swiftlint(report_dir / "swiftlint.json")
total_findings = shellcheck_count + semgrep_count + gitleaks_count + detect_secrets_count + swiftlint_count

summary = {
    "shellcheck_findings": shellcheck_count,
    "semgrep_findings": semgrep_count,
    "gitleaks_findings": gitleaks_count,
    "detect_secrets_findings": detect_secrets_count,
    "swiftlint_findings": swiftlint_count,
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

if [[ "$RUN_DETECT_SECRETS" == "true" ]]; then
  run_detect_secrets_lane "${REPORT_DIR}/detect-secrets.json"
fi

if [[ "$RUN_SWIFTLINT" == "true" ]]; then
  run_swiftlint_lane "${REPORT_DIR}/swiftlint.json"
fi

emit_summary_and_gate "$REPORT_DIR" "$FAIL_ON_FINDINGS"
echo "✅ Security checks completed. Reports: ${REPORT_DIR}"
