#!/usr/bin/env bats

load '../lib/test_helper'

setup() {
  TMPDIR="$(mktemp -d)"
}

teardown() {
  rm -rf "${TMPDIR}"
}

@test "fires when file contains emoji" {
  printf 'hello \xF0\x9F\x9A\x80 world\n' > "${TMPDIR}/x.txt"
  run "$(hook check_no_emoji.sh)" <<< "{\"tool_input\":{\"file_path\":\"${TMPDIR}/x.txt\"}}"
  assert_message_contains "Emoji detected"
}

@test "silent on clean ASCII file" {
  echo "hello world" > "${TMPDIR}/x.txt"
  run "$(hook check_no_emoji.sh)" <<< "{\"tool_input\":{\"file_path\":\"${TMPDIR}/x.txt\"}}"
  assert_silent
}

@test "silent when file does not exist" {
  run "$(hook check_no_emoji.sh)" <<< '{"tool_input":{"file_path":"/no/such/path"}}'
  assert_silent
}

@test "silent when file is binary" {
  printf '\x00\x01\x02\x03' > "${TMPDIR}/bin"
  run "$(hook check_no_emoji.sh)" <<< "{\"tool_input\":{\"file_path\":\"${TMPDIR}/bin\"}}"
  assert_silent
}
