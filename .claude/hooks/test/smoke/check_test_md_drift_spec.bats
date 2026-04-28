#!/usr/bin/env bats

load '../lib/test_helper'

@test "fires when TEST.md count > actual @test count" {
  local repo
  repo="$(mktemp_test_md_repo 3 5)"
  run "$(hook check_test_md_drift.sh)" <<< "{\"tool_input\":{\"file_path\":\"${repo}/test/unit/setup_spec.bats\"}}"
  assert_message_contains "TEST.md drift"
  rm -rf "${repo}"
}

@test "fires when TEST.md count < actual @test count" {
  local repo
  repo="$(mktemp_test_md_repo 5 3)"
  run "$(hook check_test_md_drift.sh)" <<< "{\"tool_input\":{\"file_path\":\"${repo}/doc/test/TEST.md\"}}"
  assert_message_contains "TEST.md drift"
  rm -rf "${repo}"
}

@test "silent when counts match" {
  local repo
  repo="$(mktemp_test_md_repo 4 4)"
  run "$(hook check_test_md_drift.sh)" <<< "{\"tool_input\":{\"file_path\":\"${repo}/test/unit/setup_spec.bats\"}}"
  assert_silent
  rm -rf "${repo}"
}

@test "fires when TEST.md lists missing bats file" {
  local repo
  repo="$(mktemp -d)"
  mkdir -p "${repo}/test" "${repo}/doc/test"
  cat > "${repo}/doc/test/TEST.md" <<'EOF'
### test/unit/missing_spec.bats (10)
EOF
  run "$(hook check_test_md_drift.sh)" <<< "{\"tool_input\":{\"file_path\":\"${repo}/doc/test/TEST.md\"}}"
  assert_message_contains "listed in TEST.md but file missing"
  rm -rf "${repo}"
}

@test "silent when edited file is not .bats or TEST.md" {
  run "$(hook check_test_md_drift.sh)" <<< '{"tool_input":{"file_path":"/tmp/foo.txt"}}'
  assert_silent
}
