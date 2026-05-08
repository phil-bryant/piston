#!/bin/bash
umask 007

#R001: Run with bash in strict fail-fast mode.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"
ONEPSA_REPO_URL="${ONEPSA_REPO_URL:-https://github.com/phil-bryant/1psa.git}"
ONEPSA_DIR="${ONEPSA_DIR:-${PARENT_DIR}/1psa}"
ONEPSA_LOCAL_BIN="${ONEPSA_DIR}/bin/1psa"
OUTLOOK_GRAPH_TOKEN_PSA_ITEM="${OUTLOOK_GRAPH_TOKEN_PSA_ITEM:-outlook_graph_token}"
OUTLOOK_GRAPH_TOKEN_PSA_FIELD="${OUTLOOK_GRAPH_TOKEN_PSA_FIELD:-password}"

print_header() {
    echo "============================================================"
    echo "Prerequisites Installer"
    echo "============================================================"
    echo ""
}

ensure_homebrew() {
    #R005: Verify Homebrew exists before package actions.
    #R030: Emit explicit status lines for this prerequisite phase.
    echo "[Homebrew] Checking..."
    if command -v brew >/dev/null 2>&1; then
        echo "✅ [Homebrew] Installed"
    else
        echo "❌ [Homebrew] Not installed."
        echo "Install Homebrew and rerun:"
        echo "/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        exit 1
    fi
}

ensure_brew_formula() {
    #R020: Install xcodegen via Homebrew when missing.
    #R030 #R035: Print clear status and keep reruns idempotent.
    local formula="$1"
    local command_name="${2:-$formula}"

    echo "[${formula}] Checking..."
    if command -v "$command_name" >/dev/null 2>&1; then
        echo "✅ [${formula}] Available on PATH"
    else
        echo "⚠️  [${formula}] Missing; installing with Homebrew..."
        brew install "$formula"
        if command -v "$command_name" >/dev/null 2>&1; then
            echo "✅ [${formula}] Installed and available"
        else
            echo "❌ [${formula}] Install completed but command is still missing"
            exit 1
        fi
    fi
}

ensure_xcode_toolchain() {
    #R010: Require xcodebuild, xcrun, and clang++ for this repository.
    #R030: Emit explicit status for each toolchain check.
    local missing_toolchain=0

    echo "[Xcode Toolchain] Checking..."
    if command -v xcodebuild >/dev/null 2>&1; then
        echo "✅ [Xcode Toolchain] xcodebuild available"
    else
        echo "❌ [Xcode Toolchain] xcodebuild not found"
        missing_toolchain=1
    fi

    if command -v xcrun >/dev/null 2>&1; then
        echo "✅ [Xcode Toolchain] xcrun available"
    else
        echo "❌ [Xcode Toolchain] xcrun not found"
        missing_toolchain=1
    fi

    if command -v clang++ >/dev/null 2>&1; then
        echo "✅ [Xcode Toolchain] clang++ available"
    else
        echo "❌ [Xcode Toolchain] clang++ not found"
        missing_toolchain=1
    fi

    if [ "$missing_toolchain" -eq 0 ]; then
        echo "✅ [Xcode Toolchain] Base toolchain checks passed"
    else
        echo "Install Xcode or Xcode Command Line Tools, then rerun."
        echo "Tip: xcode-select --install"
        exit 1
    fi
}

ensure_xcode_first_launch() {
    #R015: Ensure first-launch setup and license acceptance are completed.
    #R030 #R035: Print status and skip work when already configured.
    echo "[Xcode First Launch] Checking..."
    if xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
        echo "✅ [Xcode First Launch] Already configured"
    else
        echo "⚠️  [Xcode First Launch] Setup required; running privileged initialization..."
        sudo xcodebuild -runFirstLaunch
        if xcodebuild -license check >/dev/null 2>&1; then
            echo "✅ [Xcode First Launch] License already accepted"
        else
            echo "⚠️  [Xcode First Launch] Accepting Xcode license..."
            sudo xcodebuild -license accept
        fi
        if xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
            echo "✅ [Xcode First Launch] Setup completed"
        else
            echo "❌ [Xcode First Launch] Setup did not complete"
            exit 1
        fi
    fi
}

ensure_swift_tooling() {
    #R025: Ensure Swift compiler is discoverable for UI typecheck/build workflows.
    #R030: Emit explicit status lines for this prerequisite phase.
    echo "[Swift] Checking..."
    if xcrun --find swiftc >/dev/null 2>&1; then
        echo "✅ [Swift] swiftc available via xcrun"
    else
        echo "❌ [Swift] swiftc not discoverable via xcrun"
        echo "Install full Xcode and rerun this installer."
        exit 1
    fi
}

ensure_clang_tidy() {
    #R070: Ensure clang-tidy is available, including Homebrew llvm fallback.
    #R030 #R035: Keep status explicit and reruns idempotent.
    local llvm_prefix=""
    local llvm_clang_tidy=""

    echo "[clang-tidy] Checking..."
    if command -v clang-tidy >/dev/null 2>&1; then
        echo "✅ [clang-tidy] Available on PATH"
        return
    fi

    llvm_prefix="$(brew --prefix llvm 2>/dev/null || true)"
    llvm_clang_tidy="${llvm_prefix}/bin/clang-tidy"
    if [ -x "$llvm_clang_tidy" ]; then
        echo "✅ [clang-tidy] Available at ${llvm_clang_tidy}"
        echo "ℹ️  Add to PATH for this shell if needed: export PATH=\"${llvm_prefix}/bin:\$PATH\""
        return
    fi

    echo "⚠️  [clang-tidy] Missing; installing llvm with Homebrew..."
    brew install llvm

    if command -v clang-tidy >/dev/null 2>&1; then
        echo "✅ [clang-tidy] Installed and available on PATH"
        return
    fi

    llvm_prefix="$(brew --prefix llvm 2>/dev/null || true)"
    llvm_clang_tidy="${llvm_prefix}/bin/clang-tidy"
    if [ -x "$llvm_clang_tidy" ]; then
        echo "✅ [clang-tidy] Available at ${llvm_clang_tidy}"
        echo "ℹ️  Add to PATH for this shell if needed: export PATH=\"${llvm_prefix}/bin:\$PATH\""
        return
    fi

    echo "❌ [clang-tidy] Install completed but clang-tidy is still unavailable"
    exit 1
}

ensure_sast_tooling() {
    #R055: Ensure ShellCheck, Semgrep, clang-tidy, and gitleaks for make sast.
    #R060: Emit explicit phase status for each SAST prerequisite tool.
    echo ""
    ensure_brew_formula "shellcheck"
    ensure_brew_formula "semgrep"
    ensure_clang_tidy
    ensure_brew_formula "gitleaks"
}

ensure_1psa() {
    #R045: Ensure 1psa is available for runtime token retrieval.
    #R050: Keep 1psa setup idempotent across reruns.
    echo ""
    echo "[1psa] Checking..."
    if command -v 1psa >/dev/null 2>&1; then
        echo "✅ [1psa] Available on PATH"
    else
        ensure_brew_formula "go"
        ensure_brew_formula "git"
        if [ -d "$ONEPSA_DIR/.git" ]; then
            echo "✅ [1psa] Source repository present at ${ONEPSA_DIR}"
        elif [ -e "$ONEPSA_DIR" ]; then
            echo "❌ [1psa] ${ONEPSA_DIR} exists but is not a git repository"
            exit 1
        else
            echo "[1psa] Cloning source into ${PARENT_DIR}..."
            git clone "$ONEPSA_REPO_URL" "$ONEPSA_DIR"
        fi
        if [ ! -f "${ONEPSA_DIR}/Makefile" ]; then
            echo "❌ [1psa] Missing Makefile in ${ONEPSA_DIR}"
            exit 1
        fi
        echo "[1psa] Building from source..."
        make -C "$ONEPSA_DIR"
        if [ ! -x "$ONEPSA_LOCAL_BIN" ]; then
            echo "❌ [1psa] Expected local binary missing at ${ONEPSA_LOCAL_BIN}"
            exit 1
        fi
        echo "[1psa] Installing with sudo..."
        sudo make -C "$ONEPSA_DIR" install
        if command -v 1psa >/dev/null 2>&1; then
            echo "✅ [1psa] Installed and available on PATH"
        else
            echo "❌ [1psa] Install completed but command is still unavailable"
            exit 1
        fi
    fi
}

print_final_guidance() {
    #R040: Print local readiness guidance for core build/test commands.
    #R065: Include make sast in final readiness guidance.
    echo ""
    echo "✅ All prerequisites are satisfied for this repository."
    echo ""
    echo "Next commands:"
    echo "- make build"
    echo "- make sast"
    echo "- make test"
    echo "- make ui-test"
    echo "- make run"
    echo ""
    echo "1psa defaults for real Outlook token:"
    echo "- item: ${OUTLOOK_GRAPH_TOKEN_PSA_ITEM}"
    echo "- field: ${OUTLOOK_GRAPH_TOKEN_PSA_FIELD}"
}

print_header
ensure_homebrew
echo ""
ensure_xcode_toolchain
ensure_xcode_first_launch
ensure_swift_tooling
ensure_brew_formula "xcodegen"
ensure_sast_tooling
ensure_1psa
print_final_guidance
