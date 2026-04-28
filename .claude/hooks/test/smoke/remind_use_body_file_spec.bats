#!/usr/bin/env bats

load '../lib/test_helper'

@test "fires on gh issue close --comment \"\$(cat path)\"" {
  run "$(hook remind_use_body_file.sh)" <<< '{"tool_input":{"command":"gh issue close 1 --comment \"$(cat /tmp/x.md)\""}}'
  assert_message_contains "--body-file"
}

@test "fires on gh pr create --body \"\$(cat path)\"" {
  run "$(hook remind_use_body_file.sh)" <<< '{"tool_input":{"command":"gh pr create --body \"$(cat /tmp/body.md)\" --title T"}}'
  assert_message_contains "--body-file"
}

@test "fires on gh pr edit --body \$(cat path) without quotes" {
  run "$(hook remind_use_body_file.sh)" <<< '{"tool_input":{"command":"gh pr edit 5 --body $(cat /tmp/x.md)"}}'
  assert_message_contains "--body-file"
}

@test "silent on gh ... --body-file already" {
  run "$(hook remind_use_body_file.sh)" <<< '{"tool_input":{"command":"gh pr create --body-file /tmp/x.md --title T"}}'
  assert_silent
}

@test "silent on gh ... --body \"inline string\"" {
  run "$(hook remind_use_body_file.sh)" <<< '{"tool_input":{"command":"gh pr create --body \"hello inline\" --title T"}}'
  assert_silent
}

@test "silent on non-gh command using \$(cat path)" {
  run "$(hook remind_use_body_file.sh)" <<< '{"tool_input":{"command":"echo \"$(cat /tmp/x.md)\""}}'
  assert_silent
}
