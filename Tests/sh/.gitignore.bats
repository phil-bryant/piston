#!/usr/bin/env bats

@test ".build artifacts are ignored and hidden from git status" {
  #R001: Build output must be ignored recursively.
  #R020: Ignored build paths must not be tracked.
  #R025: Regression guard for `.build/` ignore behavior.
  tmp_path=".build/traceability-ignore-test-$$.tmp"
  cleanup() { rm -f "$tmp_path"; }
  trap cleanup EXIT
  mkdir -p ".build"
  printf "traceability-fixture\n" > "$tmp_path"

  run git check-ignore -q "$tmp_path"
  [ "$status" -eq 0 ]

  run bash -lc "git status --porcelain -- '$tmp_path'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "xcode local metadata remains ignored" {
  #R005: User-local Xcode metadata must be excluded from version control.
  run git check-ignore -v "DerivedData/example/index"
  [ "$status" -eq 0 ]
  [[ "$output" == *".gitignore"* ]]
}

@test "project source and shared config stay trackable" {
  #R010: Source and shared package metadata must stay tracked.
  #R015: Cleanup should happen via cached removals, not local deletion.
  run git check-ignore -q "Package.swift"
  [ "$status" -ne 0 ]
}
