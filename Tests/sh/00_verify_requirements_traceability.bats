#!/usr/bin/env bats

make_traceability_fixture() {
  local fixture_root="$1" mode="$2"
  mkdir -p "${fixture_root}/requirements" "${fixture_root}/Tests/sh"
  cat > "${fixture_root}/requirements/fixture-requirements.md" <<'EOF'
# Fixture Requirements

## Scope

Applies to `fixture.sh`.

R001  Statement: First behavior.
R005  Statement: Second behavior.
EOF
  if [ "$mode" = "bundled" ]; then
    cat > "${fixture_root}/fixture.sh" <<'EOF'
#!/bin/bash
# #R001 #R005 #R010
echo "fixture"
EOF
  fi
  if [ "$mode" = "unscoped" ]; then
    cat > "${fixture_root}/fixture.sh" <<'EOF'
#!/bin/bash
# #R001
# #R005
echo "fixture"
EOF
  fi
  if [ "$mode" = "scoped" ]; then
    cat > "${fixture_root}/fixture.sh" <<'EOF'
#!/bin/bash
# #R001: First behavior.
echo "first"
# #R005: Second behavior.
echo "second"
EOF
  fi
  cat > "${fixture_root}/Tests/sh/fixture.bats" <<'EOF'
#!/usr/bin/env bats

@test "fixture requirement tags" {
  #R001: First behavior test trace.
  #R005: Second behavior test trace.
  [ 1 -eq 1 ]
}
EOF
  chmod +x "${fixture_root}/fixture.sh"
}

@test "Traceability tags for verifier requirements" {
  #R001: Strict mode and temp file setup requirement coverage.
  #R005: Default recursive requirements discovery coverage.
  #R010: Requirements-to-source mapping coverage.
  #R015: Missing mapping/source failure messaging coverage.
  #R020: Requirement ID parsing coverage.
  #R025: Source #R tag parsing coverage.
  #R030: Missing/extra set-difference reporting coverage.
  #R035: Pass/fail exit semantics coverage.
  #R040: Numbered script requirements coverage checks.
  #R045: Numbered requirements scope alignment checks.
  #R050: Requirement-to-test discovery coverage.
  #R055: UI-required requirement classification coverage.
  #R060: Test-lane #R extraction coverage.
  #R065: Missing test-traceability ID failure coverage.
  true
}

@test "Fails when header-bundled tags are used near file top" {
  local fixture_root
  fixture_root="$(mktemp -d)"
  make_traceability_fixture "${fixture_root}" "bundled"
  cp "${BATS_TEST_DIRNAME}/../../00_verify_requirements_traceability.sh" "${fixture_root}/00_verify_requirements_traceability.sh"
  run bash -lc "cd '${fixture_root}' && bash ./00_verify_requirements_traceability.sh requirements/fixture-requirements.md fixture.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL (anti-cheat)"* ]]
}

@test "Fails when IDs exist only as unscoped set-membership tags" {
  local fixture_root
  fixture_root="$(mktemp -d)"
  make_traceability_fixture "${fixture_root}" "unscoped"
  cp "${BATS_TEST_DIRNAME}/../../00_verify_requirements_traceability.sh" "${fixture_root}/00_verify_requirements_traceability.sh"
  run bash -lc "cd '${fixture_root}' && bash ./00_verify_requirements_traceability.sh requirements/fixture-requirements.md fixture.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Missing scoped #R comments"* ]]
}

@test "Passes when requirement IDs are scoped with #Rxxx: comments" {
  local fixture_root
  fixture_root="$(mktemp -d)"
  make_traceability_fixture "${fixture_root}" "scoped"
  cp "${BATS_TEST_DIRNAME}/../../00_verify_requirements_traceability.sh" "${fixture_root}/00_verify_requirements_traceability.sh"
  run bash -lc "cd '${fixture_root}' && bash ./00_verify_requirements_traceability.sh requirements/fixture-requirements.md fixture.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS (test-traceability)"* ]]
}
