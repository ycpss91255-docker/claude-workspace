#!/usr/bin/env bats

load '../lib/test_helper'

@test "fires on gh pr create" {
  run "$(hook remind_pr_wait_ci.sh)" <<< '{"tool_input":{"command":"gh pr create --title foo --body bar"}}'
  assert_message_contains "wait-pr-ci"
}

@test "fires on chained command containing gh pr create" {
  run "$(hook remind_pr_wait_ci.sh)" <<< '{"tool_input":{"command":"git push -u origin foo && gh pr create --fill"}}'
  assert_message_contains "wait-pr-ci"
}

@test "silent on gh pr list" {
  run "$(hook remind_pr_wait_ci.sh)" <<< '{"tool_input":{"command":"gh pr list"}}'
  assert_silent
}

@test "silent on unrelated command" {
  run "$(hook remind_pr_wait_ci.sh)" <<< '{"tool_input":{"command":"echo hello"}}'
  assert_silent
}

@test "silent on empty command" {
  run "$(hook remind_pr_wait_ci.sh)" <<< '{"tool_input":{}}'
  assert_silent
}
