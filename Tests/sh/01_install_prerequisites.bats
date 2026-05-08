#!/usr/bin/env bats

setup() {
  export REPO_ROOT="/Users/phil/local/src/piston"
  export SCRIPT_PATH="${REPO_ROOT}/01_install_prerequisites.sh"
  export TMP_ROOT
  TMP_ROOT="$(mktemp -d)"
  export STUB_BIN="${TMP_ROOT}/bin"
  mkdir -p "${STUB_BIN}"
}

teardown() {
  rm -rf "${TMP_ROOT}"
}

create_common_toolchain_stubs() {
  cat > "${STUB_BIN}/clang++" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "${STUB_BIN}/clang++"

  cat > "${STUB_BIN}/xcrun" <<'EOF'
#!/bin/bash
if [ "$1" = "--find" ] && [ "$2" = "swiftc" ]; then
  echo "/usr/bin/swiftc"
  exit 0
fi
exit 1
EOF
  chmod +x "${STUB_BIN}/xcrun"

  cat > "${STUB_BIN}/xcodebuild" <<'EOF'
#!/bin/bash
if [ "$1" = "-checkFirstLaunchStatus" ]; then
  exit 0
fi
if [ "$1" = "-license" ] && [ "$2" = "check" ]; then
  exit 0
fi
if [ "$1" = "-runFirstLaunch" ]; then
  exit 0
fi
if [ "$1" = "-license" ] && [ "$2" = "accept" ]; then
  exit 0
fi
exit 1
EOF
  chmod +x "${STUB_BIN}/xcodebuild"
}

create_1psa_available_stub() {
  cat > "${STUB_BIN}/1psa" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "${STUB_BIN}/1psa"
}

create_brew_stub() {
  cat > "${STUB_BIN}/brew" <<'EOF'
#!/bin/bash
if [ "$1" = "--prefix" ] && [ "$2" = "llvm" ]; then
  echo "${STUB_BIN}/opt/llvm"
  exit 0
fi
if [ "$1" = "install" ]; then
  FORMULA="$2"
  printf "install %s\n" "${FORMULA}" >> "${BREW_LOG}"
  if [ "${FORMULA}" = "llvm" ]; then
    mkdir -p "${STUB_BIN}/opt/llvm/bin"
    cat > "${STUB_BIN}/opt/llvm/bin/clang-tidy" <<'INNER'
#!/bin/bash
exit 0
INNER
    chmod +x "${STUB_BIN}/opt/llvm/bin/clang-tidy"
    exit 0
  fi
  cat > "${STUB_BIN}/${FORMULA}" <<'INNER'
#!/bin/bash
exit 0
INNER
  chmod +x "${STUB_BIN}/${FORMULA}"
  exit 0
fi
exit 0
EOF
  chmod +x "${STUB_BIN}/brew"
}

create_git_stub_for_1psa_clone() {
  cat > "${STUB_BIN}/git" <<'EOF'
#!/bin/bash
if [ "$1" = "clone" ]; then
  DEST="$3"
  mkdir -p "${DEST}/bin" "${DEST}/.git"
  cat > "${DEST}/Makefile" <<'INNER'
all:
	@echo build
install:
	@echo install
INNER
  cat > "${DEST}/bin/1psa" <<'INNER'
#!/bin/bash
exit 0
INNER
  chmod +x "${DEST}/bin/1psa"
  exit 0
fi
exit 1
EOF
  chmod +x "${STUB_BIN}/git"
}

create_make_stub_for_1psa_build_install() {
  cat > "${STUB_BIN}/make" <<'EOF'
#!/bin/bash
if [ "$1" = "-C" ]; then
  if [ "$3" = "install" ]; then
    cat > "${STUB_BIN}/1psa" <<'INNER'
#!/bin/bash
exit 0
INNER
    chmod +x "${STUB_BIN}/1psa"
  fi
  exit 0
fi
exit 1
EOF
  chmod +x "${STUB_BIN}/make"
}

create_sudo_passthrough_stub() {
  cat > "${STUB_BIN}/sudo" <<'EOF'
#!/bin/bash
"$@"
EOF
  chmod +x "${STUB_BIN}/sudo"
}

create_dirname_stub() {
  cat > "${STUB_BIN}/dirname" <<'EOF'
#!/bin/bash
/usr/bin/dirname "$@"
EOF
  chmod +x "${STUB_BIN}/dirname"
}

@test "R001: script uses strict fail-fast mode" {
  #R001
  run rg "set -euo pipefail" "${SCRIPT_PATH}"
  [ "$status" -eq 0 ]
}

@test "R005: fails with guidance when Homebrew is missing" {
  #R005
  run env PATH="/usr/bin:/bin" bash "${SCRIPT_PATH}"
  [ "$status" -ne 0 ]
  [[ "${output}" == *"[Homebrew] Not installed."* ]]
  [[ "${output}" == *"install.sh"* ]]
}

@test "R010,R030: fails clearly when Xcode toolchain commands are missing" {
  #R010 #R030
  create_brew_stub
  create_dirname_stub
  run env PATH="${STUB_BIN}:/bin" BREW_LOG="${TMP_ROOT}/brew.log" STUB_BIN="${STUB_BIN}" /bin/bash "${SCRIPT_PATH}"
  [ "$status" -ne 0 ]
  [[ "${output}" == *"[Xcode Toolchain] xcodebuild not found"* ]]
  [[ "${output}" == *"[Xcode Toolchain] xcrun"* ]]
}

@test "R020,R025,R035,R040,R055,R060,R065,R070: installs build and sast tools, validates swiftc, and prints readiness guidance" {
  #R020 #R025 #R035 #R040 #R050 #R055 #R060 #R065 #R070
  create_common_toolchain_stubs
  create_brew_stub
  create_1psa_available_stub

  run env PATH="${STUB_BIN}:/usr/bin:/bin" BREW_LOG="${TMP_ROOT}/brew.log" STUB_BIN="${STUB_BIN}" bash "${SCRIPT_PATH}"
  [ "$status" -eq 0 ]
  [[ "${output}" == *"[xcodegen] Checking..."* ]]
  [[ "${output}" == *"[Swift] swiftc available via xcrun"* ]]
  [[ "${output}" == *"[1psa] Available on PATH"* ]]
  [[ "${output}" == *"make build"* ]]
  [[ "${output}" == *"make sast"* ]]
  [[ "${output}" == *"make test"* ]]
  [[ "${output}" == *"make ui-test"* ]]
  [[ "${output}" == *"make run"* ]]
  [[ "${output}" == *"item: outlook_graph_token"* ]]
  [[ "${output}" == *"field: password"* ]]
  run rg "^install xcodegen$" "${TMP_ROOT}/brew.log"
  [ "$status" -eq 0 ]
  run rg "^install shellcheck$" "${TMP_ROOT}/brew.log"
  [ "$status" -eq 0 ]
  run rg "^install semgrep$" "${TMP_ROOT}/brew.log"
  [ "$status" -eq 0 ]
  run rg "^install llvm$" "${TMP_ROOT}/brew.log"
  [ "$status" -eq 0 ]
  run rg "^install gitleaks$" "${TMP_ROOT}/brew.log"
  [ "$status" -eq 0 ]
}

@test "R015,R035: skips first-launch actions when already configured" {
  #R015 #R035
  create_common_toolchain_stubs
  create_brew_stub
  create_1psa_available_stub
  cat > "${STUB_BIN}/xcodegen" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "${STUB_BIN}/xcodegen"

  run env PATH="${STUB_BIN}:/usr/bin:/bin" BREW_LOG="${TMP_ROOT}/brew.log" STUB_BIN="${STUB_BIN}" bash "${SCRIPT_PATH}"
  [ "$status" -eq 0 ]
  [[ "${output}" == *"[Xcode First Launch] Already configured"* ]]
}

@test "R035: reruns are idempotent and skip redundant prerequisite installs" {
  #R035 #R050 #R055 #R070
  create_common_toolchain_stubs
  create_brew_stub
  create_1psa_available_stub

  run env PATH="${STUB_BIN}:/usr/bin:/bin" BREW_LOG="${TMP_ROOT}/brew.log" STUB_BIN="${STUB_BIN}" bash "${SCRIPT_PATH}"
  [ "$status" -eq 0 ]

  run env PATH="${STUB_BIN}:/usr/bin:/bin" BREW_LOG="${TMP_ROOT}/brew.log" STUB_BIN="${STUB_BIN}" bash "${SCRIPT_PATH}"
  [ "$status" -eq 0 ]

  run rg "^install xcodegen$" "${TMP_ROOT}/brew.log" --count
  [ "$status" -eq 0 ]
  [ "${output}" = "1" ]
  run rg "^install shellcheck$" "${TMP_ROOT}/brew.log" --count
  [ "$status" -eq 0 ]
  [ "${output}" = "1" ]
  run rg "^install semgrep$" "${TMP_ROOT}/brew.log" --count
  [ "$status" -eq 0 ]
  [ "${output}" = "1" ]
  run rg "^install llvm$" "${TMP_ROOT}/brew.log" --count
  [ "$status" -eq 0 ]
  [ "${output}" = "1" ]
  run rg "^install gitleaks$" "${TMP_ROOT}/brew.log" --count
  [ "$status" -eq 0 ]
  [ "${output}" = "1" ]
}

@test "R045,R050: installs 1psa from source when missing" {
  #R045 #R050
  create_common_toolchain_stubs
  create_brew_stub
  create_git_stub_for_1psa_clone
  create_make_stub_for_1psa_build_install
  create_sudo_passthrough_stub
  cat > "${STUB_BIN}/go" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "${STUB_BIN}/go"
  cat > "${STUB_BIN}/xcodegen" <<'EOF'
#!/bin/bash
exit 0
EOF
  chmod +x "${STUB_BIN}/xcodegen"

  run env PATH="${STUB_BIN}:/usr/bin:/bin" BREW_LOG="${TMP_ROOT}/brew.log" STUB_BIN="${STUB_BIN}" ONEPSA_DIR="${TMP_ROOT}/1psa" bash "${SCRIPT_PATH}"
  [ "$status" -eq 0 ]
  [[ "${output}" == *"[1psa] Cloning source into"* ]]
  [[ "${output}" == *"[1psa] Building from source..."* ]]
  [[ "${output}" == *"[1psa] Installed and available on PATH"* ]]
}
