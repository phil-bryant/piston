#!/usr/bin/env bats

setup() {
  export REPO_ROOT="/Users/phil/local/src/piston"
  export SCRIPT_SOURCE="${REPO_ROOT}/03_run_security_checks.sh"
  export TMP_ROOT
  TMP_ROOT="$(mktemp -d)"
  export STUB_BIN="${TMP_ROOT}/bin"
  export FIXTURE_ROOT="${TMP_ROOT}/fixture"
  export CALLS_LOG="${TMP_ROOT}/calls.log"
  mkdir -p "${STUB_BIN}" "${FIXTURE_ROOT}/Tests/sh"
  cp "${SCRIPT_SOURCE}" "${FIXTURE_ROOT}/03_run_security_checks.sh"
  chmod +x "${FIXTURE_ROOT}/03_run_security_checks.sh"
  : > "${CALLS_LOG}"
}

write_shellcheck_stub_with_findings() {
  cat > "${STUB_BIN}/shellcheck" <<'EOF'
#!/usr/bin/env bash
echo "shellcheck $*" >> "${CALLS_LOG}"
if [[ "$1" == "-f" && "$2" == "json" ]]; then
  printf '%s' '[{"file":"03_run_security_checks.sh","line":1,"code":2001,"level":"warning","message":"example finding"}]'
  exit 1
fi
exit 2
EOF
  chmod +x "${STUB_BIN}/shellcheck"
}

write_shellcheck_stub_clean() {
  cat > "${STUB_BIN}/shellcheck" <<'EOF'
#!/usr/bin/env bash
echo "shellcheck $*" >> "${CALLS_LOG}"
printf '%s' '[]'
exit 0
EOF
  chmod +x "${STUB_BIN}/shellcheck"
}

write_semgrep_stub_with_findings() {
  cat > "${STUB_BIN}/semgrep" <<'EOF'
#!/usr/bin/env bash
echo "semgrep $*" >> "${CALLS_LOG}"
output_path=""
while [[ "$#" -gt 0 ]]; do
  if [[ "$1" == "--output" ]]; then
    output_path="$2"
    shift 2
    continue
  fi
  shift
done
printf '%s' '{"results":[{"check_id":"demo","path":"demo.sh"}]}' > "${output_path}"
exit 1
EOF
  chmod +x "${STUB_BIN}/semgrep"
}

write_semgrep_stub_exec_failure() {
  cat > "${STUB_BIN}/semgrep" <<'EOF'
#!/usr/bin/env bash
echo "semgrep $*" >> "${CALLS_LOG}"
exit 2
EOF
  chmod +x "${STUB_BIN}/semgrep"
}

write_gitleaks_stub_with_findings() {
  cat > "${STUB_BIN}/gitleaks" <<'EOF'
#!/usr/bin/env bash
echo "gitleaks $*" >> "${CALLS_LOG}"
report_path=""
while [[ "$#" -gt 0 ]]; do
  if [[ "$1" == "--report-path" ]]; then
    report_path="$2"
    shift 2
    continue
  fi
  shift
done
printf '%s' '[{"RuleID":"generic-api-key","File":"Secrets.txt"}]' > "${report_path}"
exit 1
EOF
  chmod +x "${STUB_BIN}/gitleaks"
}

write_gitleaks_stub_exec_failure() {
  cat > "${STUB_BIN}/gitleaks" <<'EOF'
#!/usr/bin/env bash
echo "gitleaks $*" >> "${CALLS_LOG}"
exit 2
EOF
  chmod +x "${STUB_BIN}/gitleaks"
}

write_detect_secrets_stub_with_findings() {
  cat > "${STUB_BIN}/detect-secrets" <<'EOF'
#!/usr/bin/env bash
echo "detect-secrets $*" >> "${CALLS_LOG}"
printf '%s' '{"results":{"03_run_security_checks.sh":[{"type":"Secret Keyword","line_number":1}]}}'
exit 0
EOF
  chmod +x "${STUB_BIN}/detect-secrets"
}

write_detect_secrets_stub_exec_failure() {
  cat > "${STUB_BIN}/detect-secrets" <<'EOF'
#!/usr/bin/env bash
echo "detect-secrets $*" >> "${CALLS_LOG}"
exit 2
EOF
  chmod +x "${STUB_BIN}/detect-secrets"
}

write_swiftlint_stub_with_findings() {
  cat > "${STUB_BIN}/swiftlint" <<'EOF'
#!/usr/bin/env bash
echo "swiftlint $*" >> "${CALLS_LOG}"
printf '%s' '[{"file":"Sources/Piston/PistonUploader.swift","line":10,"reason":"Example rule"}]'
exit 2
EOF
  chmod +x "${STUB_BIN}/swiftlint"
}

write_swiftlint_stub_exec_failure() {
  cat > "${STUB_BIN}/swiftlint" <<'EOF'
#!/usr/bin/env bash
echo "swiftlint $*" >> "${CALLS_LOG}"
exit 2
EOF
  chmod +x "${STUB_BIN}/swiftlint"
}

@test "Traceability tags for security-check requirements" {
  #R001: Strict mode and repository-root execution coverage.
  #R005: Lane toggles and report directory configuration coverage.
  #R010: Missing-command failure messaging coverage.
  #R015: ShellCheck execution and report persistence coverage.
  #R020: Semgrep execution/report behavior coverage.
  #R025: Gitleaks execution/report behavior coverage.
  #R035: detect-secrets execution/report behavior coverage.
  #R040: SwiftLint execution/report behavior coverage.
  #R045: Per-tool explainer header output coverage.
  #R030: Consolidated summary and fail-on-findings policy coverage.
  true
}

@test "R001,R005: runs from outside cwd and creates custom report directory with lanes disabled" {
  #R001: Verifies script anchors to repo root via script location.
  #R005: Verifies custom report directory and lane toggles.
  mkdir -p "${TMP_ROOT}/outside"
  cd "${TMP_ROOT}/outside"
  run env PATH="/usr/bin:/bin" RUN_SHELLCHECK=false RUN_SEMGREP=false RUN_GITLEAKS=false RUN_DETECT_SCAN=false RUN_SWIFTLINT=false \
    SECURITY_REPORT_DIR="${FIXTURE_ROOT}/custom-reports" /bin/bash "${FIXTURE_ROOT}/03_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [ -d "${FIXTURE_ROOT}/custom-reports" ]
  [ -f "${FIXTURE_ROOT}/custom-reports/security-summary.json" ]
}

@test "R010: fails clearly when enabled lane command is missing" {
  #R010: Verifies explicit missing-command guidance.
  run env PATH="/usr/bin:/bin" RUN_SHELLCHECK=true RUN_SEMGREP=false RUN_GITLEAKS=false RUN_DETECT_SCAN=false RUN_SWIFTLINT=false \
    /bin/bash "${FIXTURE_ROOT}/03_run_security_checks.sh"
  [ "$status" -eq 1 ]
  [[ "${output}" == *"Missing required command: shellcheck"* ]]
}

@test "R015,R030: shellcheck findings are summarized and gate can fail" {
  #R015: Verifies shellcheck lane writes JSON report.
  #R030: Verifies fail-on-findings gate behavior.
  write_shellcheck_stub_with_findings
  run env PATH="${STUB_BIN}:/usr/bin:/bin" RUN_SEMGREP=false RUN_GITLEAKS=false RUN_DETECT_SCAN=false RUN_SWIFTLINT=false SECURITY_FAIL_ON_FINDINGS=true \
    /bin/bash "${FIXTURE_ROOT}/03_run_security_checks.sh"
  [ "$status" -eq 1 ]
  [ -f "${FIXTURE_ROOT}/.security-reports/shellcheck.json" ]
  [[ "${output}" == *"ShellCheck reported findings."* ]]
  [[ "${output}" == *"ShellCheck findings"* ]]
  [[ "${output}" == *"SC2001 example finding"* ]]
  [[ "${output}" == *"Security checks failed: findings detected"* ]]
}

@test "R020,R030: semgrep findings are summarized and can pass when gate disabled" {
  #R020: Verifies semgrep report artifact and findings handling.
  #R030: Verifies disabled gate allows findings without failing.
  write_shellcheck_stub_clean
  write_semgrep_stub_with_findings
  write_gitleaks_stub_with_findings
  write_detect_secrets_stub_with_findings
  write_swiftlint_stub_with_findings
  run env PATH="${STUB_BIN}:/usr/bin:/bin" RUN_SHELLCHECK=true RUN_SEMGREP=true RUN_GITLEAKS=true RUN_DETECT_SCAN=true RUN_SWIFTLINT=true SECURITY_FAIL_ON_FINDINGS=false \
    /bin/bash "${FIXTURE_ROOT}/03_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [ -f "${FIXTURE_ROOT}/.security-reports/semgrep.json" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/gitleaks.json" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/detect-secrets.json" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/swiftlint.json" ]
  [ -f "${FIXTURE_ROOT}/.security-reports/security-summary.json" ]
  [[ "${output}" == *"Semgrep reported findings."* ]]
  [[ "${output}" == *"Gitleaks reported findings."* ]]
  [[ "${output}" == *"SwiftLint reported findings."* ]]
}

@test "R020: semgrep execution failure exits with explicit error" {
  #R020: Verifies semgrep execution-failure path for exit code > 1.
  write_shellcheck_stub_clean
  write_semgrep_stub_exec_failure
  run env PATH="${STUB_BIN}:/usr/bin:/bin" RUN_SHELLCHECK=true RUN_SEMGREP=true RUN_GITLEAKS=false RUN_DETECT_SCAN=false RUN_SWIFTLINT=false \
    /bin/bash "${FIXTURE_ROOT}/03_run_security_checks.sh"
  [ "$status" -eq 1 ]
  [[ "${output}" == *"Semgrep failed to execute."* ]]
}

@test "R025: gitleaks execution failure exits with explicit error" {
  #R025: Verifies gitleaks execution-failure path for exit code > 1.
  write_shellcheck_stub_clean
  write_semgrep_stub_with_findings
  write_gitleaks_stub_exec_failure
  run env PATH="${STUB_BIN}:/usr/bin:/bin" RUN_SHELLCHECK=true RUN_SEMGREP=true RUN_GITLEAKS=true RUN_DETECT_SCAN=false RUN_SWIFTLINT=false SECURITY_FAIL_ON_FINDINGS=false \
    /bin/bash "${FIXTURE_ROOT}/03_run_security_checks.sh"
  [ "$status" -eq 1 ]
  [[ "${output}" == *"Gitleaks failed to execute."* ]]
}

@test "R035: detect-secrets execution failure exits with explicit error" {
  #R035: Verifies detect-secrets execution-failure path.
  write_shellcheck_stub_clean
  write_detect_secrets_stub_exec_failure
  run env PATH="${STUB_BIN}:/usr/bin:/bin" RUN_SHELLCHECK=true RUN_SEMGREP=false RUN_GITLEAKS=false RUN_DETECT_SCAN=true RUN_SWIFTLINT=false \
    /bin/bash "${FIXTURE_ROOT}/03_run_security_checks.sh"
  [ "$status" -eq 1 ]
  [[ "${output}" == *"detect-secrets failed to execute."* ]]
}

@test "R035: detect-secrets prints findings with source lines before the next tool header" {
  #R035: Verifies inline finding output includes source lines for each detect-secrets match.
  #R045: Verifies detect-secrets findings print before subsequent tool headers.
  write_shellcheck_stub_clean
  write_detect_secrets_stub_with_findings
  write_swiftlint_stub_with_findings
  run env PATH="${STUB_BIN}:/usr/bin:/bin" RUN_SHELLCHECK=true RUN_SEMGREP=false RUN_GITLEAKS=false RUN_DETECT_SCAN=true RUN_SWIFTLINT=true SECURITY_FAIL_ON_FINDINGS=false \
    /bin/bash "${FIXTURE_ROOT}/03_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [[ "${output}" == *"detect-secrets findings"* ]]
  [[ "${output}" == *"- 03_run_security_checks.sh:1 [Secret Keyword]"* ]]
  [[ "${output}" == *"  source: #!/usr/bin/env bash"* ]]
  detect_finding_line="$(printf '%s\n' "${output}" | /usr/bin/awk '/^- 03_run_security_checks.sh:1 \[Secret Keyword\]/{print NR; exit}')"
  detect_source_line="$(printf '%s\n' "${output}" | /usr/bin/awk '/^  source: #!\/usr\/bin\/env bash$/{print NR; exit}')"
  swiftlint_header_line="$(printf '%s\n' "${output}" | /usr/bin/awk '/Security Tool: SwiftLint/{print NR; exit}')"
  [ -n "${detect_finding_line}" ]
  [ -n "${detect_source_line}" ]
  [ -n "${swiftlint_header_line}" ]
  [ "${detect_source_line}" -eq "$((detect_finding_line + 1))" ]
  [ "${detect_source_line}" -lt "${swiftlint_header_line}" ]
}

@test "R040: swiftlint execution failure exits with explicit error" {
  #R040: Verifies SwiftLint execution-failure path when no valid JSON report is emitted.
  write_shellcheck_stub_clean
  write_swiftlint_stub_exec_failure
  run env PATH="${STUB_BIN}:/usr/bin:/bin" RUN_SHELLCHECK=true RUN_SEMGREP=false RUN_GITLEAKS=false RUN_DETECT_SCAN=false RUN_SWIFTLINT=true \
    /bin/bash "${FIXTURE_ROOT}/03_run_security_checks.sh"
  [ "$status" -eq 1 ]
  [[ "${output}" == *"SwiftLint failed to execute."* ]]
}

@test "R045: prints tool explainer header before each enabled lane runs" {
  #R045: Verifies each enabled lane emits tool name, purpose, and report-path header.
  write_shellcheck_stub_clean
  write_semgrep_stub_with_findings
  write_gitleaks_stub_with_findings
  write_detect_secrets_stub_with_findings
  write_swiftlint_stub_with_findings
  run env PATH="${STUB_BIN}:/usr/bin:/bin" RUN_SHELLCHECK=true RUN_SEMGREP=true RUN_GITLEAKS=true RUN_DETECT_SCAN=true RUN_SWIFTLINT=true SECURITY_FAIL_ON_FINDINGS=false \
    /bin/bash "${FIXTURE_ROOT}/03_run_security_checks.sh"
  [ "$status" -eq 0 ]
  [[ "${output}" == *"+==============================================================================+"* ]]
  [[ "${output}" == *"Security Tool: ShellCheck"* ]]
  [[ "${output}" == *"Security Tool: Semgrep"* ]]
  [[ "${output}" == *"Security Tool: Gitleaks"* ]]
  [[ "${output}" == *"Security Tool: detect-secrets"* ]]
  [[ "${output}" == *"Security Tool: SwiftLint"* ]]
  [[ "${output}" == *"URL: https://www.shellcheck.net/"* ]]
  [[ "${output}" == *"URL: https://semgrep.dev/docs/"* ]]
  [[ "${output}" == *"URL: https://github.com/gitleaks/gitleaks"* ]]
  [[ "${output}" == *"URL: https://github.com/Yelp/detect-secrets"* ]]
  [[ "${output}" == *"URL: https://github.com/realm/SwiftLint"* ]]
}
