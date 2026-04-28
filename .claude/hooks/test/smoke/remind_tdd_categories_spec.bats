#!/usr/bin/env bats

load '../lib/test_helper'

setup() {
  TMPDIR="$(mktemp -d)"
}

teardown() {
  rm -rf "${TMPDIR}"
}

@test "fires on .sh file edit" {
  echo "echo a" > "${TMPDIR}/foo.sh"
  run "$(hook remind_tdd_categories.sh)" <<< "{\"tool_input\":{\"file_path\":\"${TMPDIR}/foo.sh\"}}"
  assert_message_contains "shell 函式"
}

@test "fires on Dockerfile edit" {
  echo "FROM alpine" > "${TMPDIR}/Dockerfile"
  run "$(hook remind_tdd_categories.sh)" <<< "{\"tool_input\":{\"file_path\":\"${TMPDIR}/Dockerfile\"}}"
  assert_message_contains "Dockerfile"
}

@test "fires on compose.yaml edit" {
  echo "services:" > "${TMPDIR}/compose.yaml"
  run "$(hook remind_tdd_categories.sh)" <<< "{\"tool_input\":{\"file_path\":\"${TMPDIR}/compose.yaml\"}}"
  assert_message_contains "compose"
}

@test "fires on entrypoint.sh edit" {
  echo "#!/bin/sh" > "${TMPDIR}/entrypoint.sh"
  run "$(hook remind_tdd_categories.sh)" <<< "{\"tool_input\":{\"file_path\":\"${TMPDIR}/entrypoint.sh\"}}"
  assert_message_contains "entrypoint"
}

@test "fires on .hadolint.yaml edit" {
  echo "ignored:" > "${TMPDIR}/.hadolint.yaml"
  run "$(hook remind_tdd_categories.sh)" <<< "{\"tool_input\":{\"file_path\":\"${TMPDIR}/.hadolint.yaml\"}}"
  assert_message_contains "lint"
}

@test "silent on .md edit" {
  echo "# title" > "${TMPDIR}/README.md"
  run "$(hook remind_tdd_categories.sh)" <<< "{\"tool_input\":{\"file_path\":\"${TMPDIR}/README.md\"}}"
  assert_silent
}

@test "silent on .bats edit" {
  echo "@test x { :; }" > "${TMPDIR}/foo.bats"
  run "$(hook remind_tdd_categories.sh)" <<< "{\"tool_input\":{\"file_path\":\"${TMPDIR}/foo.bats\"}}"
  assert_silent
}

@test "silent on .claude/ internals" {
  mkdir -p "${TMPDIR}/.claude/hooks"
  echo "echo a" > "${TMPDIR}/.claude/hooks/foo.sh"
  run "$(hook remind_tdd_categories.sh)" <<< "{\"tool_input\":{\"file_path\":\"${TMPDIR}/.claude/hooks/foo.sh\"}}"
  assert_silent
}
