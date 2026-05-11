#!/usr/bin/env bats

load '../lib/test_helper'

@test "fires on git subtree pull ... template" {
  run "$(hook remind_subtree_init.sh)" <<< '{"tool_input":{"command":"git subtree pull --prefix=template https://github.com/ycpss91255-docker/base.git v1.0.0 --squash"}}'
  assert_message_contains "init.sh"
}

@test "silent on git subtree pull without template keyword" {
  run "$(hook remind_subtree_init.sh)" <<< '{"tool_input":{"command":"git subtree pull --prefix=other https://example.com/repo.git main --squash"}}'
  assert_silent
}

@test "silent on git pull (not subtree)" {
  run "$(hook remind_subtree_init.sh)" <<< '{"tool_input":{"command":"git pull origin main"}}'
  assert_silent
}

@test "silent on make upgrade (recommended path)" {
  run "$(hook remind_subtree_init.sh)" <<< '{"tool_input":{"command":"make -f Makefile.ci upgrade VERSION=v1.0.0"}}'
  assert_silent
}
