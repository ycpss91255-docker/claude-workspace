#!/usr/bin/env bats

load '../lib/test_helper'

setup() {
  SCRIPT_PATH="$(script batch-template-upgrade.sh)"
  export SCRIPT_PATH
}

@test "--help prints usage and exits 0" {
  run "${SCRIPT_PATH}" --help
  assert_success
  assert_output --partial "Usage:"
  assert_output --partial "--why-file"
  assert_output --partial "--dry-run"
}

@test "missing version exits 2" {
  run "${SCRIPT_PATH}" --why "x"
  assert_failure 2
  assert_output --partial "missing <version>"
}

@test "missing why exits 2" {
  run "${SCRIPT_PATH}" v0.99.0
  assert_failure 2
  assert_output --partial "must provide --why-file"
}

@test "unknown arg exits 2" {
  run "${SCRIPT_PATH}" --bogus
  assert_failure 2
  assert_output --partial "unknown arg"
}

@test "print_next_step_hint emits both wait + merge commands when pairs given" {
  source "${SCRIPT_PATH}"
  run print_next_step_hint ai_agent:194 claude_code:195
  assert_success
  assert_output --partial "next: wait CI then merge:"
  assert_output --partial ".claude/scripts/wait-pr-ci-batch.sh ai_agent:194 claude_code:195"
  assert_output --partial "--check-filter '.name==\"call-docker-build / docker-build\"'"
  assert_output --partial ".claude/scripts/batch-pr-merge.sh ai_agent:194 claude_code:195"
}

@test "print_next_step_hint silent when no pairs" {
  source "${SCRIPT_PATH}"
  run print_next_step_hint
  assert_success
  refute_output --partial "wait-pr-ci-batch.sh"
  refute_output --partial "batch-pr-merge.sh"
}

@test "print_next_step_hint preserves single pair" {
  source "${SCRIPT_PATH}"
  run print_next_step_hint ros_noetic:42
  assert_success
  assert_output --partial ".claude/scripts/wait-pr-ci-batch.sh ros_noetic:42"
  assert_output --partial ".claude/scripts/batch-pr-merge.sh ros_noetic:42"
}
