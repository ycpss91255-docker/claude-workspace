#!/usr/bin/env bats

load '../lib/test_helper'

@test "fires on standalone shellcheck" {
  run "$(hook remind_docker_for_lint.sh)" <<< '{"tool_input":{"command":"shellcheck script/foo.sh"}}'
  assert_message_contains "驗證一律走 Docker"
}

@test "fires on standalone bats" {
  run "$(hook remind_docker_for_lint.sh)" <<< '{"tool_input":{"command":"bats test/unit/foo_spec.bats"}}'
  assert_message_contains "驗證一律走 Docker"
}

@test "fires on standalone hadolint" {
  run "$(hook remind_docker_for_lint.sh)" <<< '{"tool_input":{"command":"hadolint Dockerfile"}}'
  assert_message_contains "驗證一律走 Docker"
}

@test "silent inside docker run wrapper" {
  run "$(hook remind_docker_for_lint.sh)" <<< '{"tool_input":{"command":"docker run --rm img shellcheck foo.sh"}}'
  assert_silent
}

@test "silent inside ./build.sh test wrapper" {
  run "$(hook remind_docker_for_lint.sh)" <<< '{"tool_input":{"command":"./build.sh test"}}'
  assert_silent
}

@test "silent inside make -f Makefile.ci wrapper" {
  run "$(hook remind_docker_for_lint.sh)" <<< '{"tool_input":{"command":"make -f Makefile.ci lint"}}'
  assert_silent
}

@test "silent on unrelated command containing the word bats in path" {
  run "$(hook remind_docker_for_lint.sh)" <<< '{"tool_input":{"command":"ls /usr/lib/bats-core"}}'
  assert_silent
}
