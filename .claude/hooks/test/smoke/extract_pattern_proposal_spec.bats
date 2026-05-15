#!/usr/bin/env bats

load '../lib/test_helper'

setup() {
  TX_DIR="$(mktemp -d)"
  export TX_DIR
  export TMPDIR="${TX_DIR}"
  unset EXTRACT_PATTERN_DISABLE EXTRACT_PATTERN_REPEAT
}

teardown() {
  rm -rf "${TX_DIR}"
}

mk_transcript() {
  local path="${TX_DIR}/transcript.jsonl"
  : > "${path}"
  local entry
  for entry in "$@"; do
    printf '%s\n' "${entry}" >> "${path}"
  done
  printf '%s\n' "${path}"
}

bash_entry() {
  local cmd="$1"
  jq -nc --arg c "${cmd}" '{message:{role:"assistant",content:[{type:"tool_use",name:"Bash",input:{command:$c}}]}}'
}

mk_input() {
  local tx="$1" session_id="${2:-s1}" stop_active="${3:-false}"
  printf '{"transcript_path":"%s","session_id":"%s","stop_hook_active":%s,"hook_event_name":"Stop"}\n' \
    "${tx}" "${session_id}" "${stop_active}"
}

# ---- non-trigger paths ----

@test "silent when no pr-merge signal in session" {
  local tx
  tx="$(mk_transcript \
    "$(bash_entry '.claude/scripts/wait-pr-ci.sh --prs 1')" \
    "$(bash_entry '.claude/scripts/wait-pr-ci.sh --prs 2')" \
    "$(bash_entry '.claude/scripts/wait-pr-ci.sh --prs 3')")"
  run "$(hook extract_pattern_proposal.sh)" <<< "$(mk_input "${tx}")"
  assert_silent
}

@test "silent when EXTRACT_PATTERN_DISABLE=1" {
  local tx
  tx="$(mk_transcript "$(bash_entry 'gh pr merge 42')")"
  EXTRACT_PATTERN_DISABLE=1 run "$(hook extract_pattern_proposal.sh)" <<< "$(mk_input "${tx}")"
  assert_silent
}

@test "silent on stop_hook_active=true (re-entry guard)" {
  local tx
  tx="$(mk_transcript "$(bash_entry 'gh pr merge 42')")"
  run "$(hook extract_pattern_proposal.sh)" <<< "$(mk_input "${tx}" s1 true)"
  assert_silent
}

@test "silent on missing transcript_path" {
  run "$(hook extract_pattern_proposal.sh)" <<< '{}'
  assert_silent
}

@test "silent when pr-merge present but no repeated patterns" {
  local tx
  tx="$(mk_transcript \
    "$(bash_entry 'gh pr merge 42')" \
    "$(bash_entry 'git status')")"
  run "$(hook extract_pattern_proposal.sh)" <<< "$(mk_input "${tx}")"
  assert_silent
}

# ---- fire paths ----

@test "fires on repeated .claude/scripts/<name>.sh invocation after pr merge" {
  local tx
  tx="$(mk_transcript \
    "$(bash_entry 'gh pr merge 42')" \
    "$(bash_entry '.claude/scripts/wait-pr-ci.sh --prs 1')" \
    "$(bash_entry '.claude/scripts/wait-pr-ci.sh --prs 2')" \
    "$(bash_entry '.claude/scripts/wait-pr-ci.sh --prs 3')")"
  run "$(hook extract_pattern_proposal.sh)" <<< "$(mk_input "${tx}")"
  assert_success
  assert_message_contains "wait-pr-ci.sh"
  assert_message_contains "Memory / skill candidate"
}

@test "fires on repeated /tmp/*.sh ad-hoc script after pr merge" {
  local tx
  tx="$(mk_transcript \
    "$(bash_entry 'gh pr merge 42')" \
    "$(bash_entry '/tmp/fixup.sh repo1')" \
    "$(bash_entry '/tmp/fixup.sh repo2')" \
    "$(bash_entry '/tmp/fixup.sh repo3')")"
  run "$(hook extract_pattern_proposal.sh)" <<< "$(mk_input "${tx}")"
  assert_success
  assert_message_contains "ad-hoc /tmp/fixup.sh"
}

@test "fires on repeated until/sleep poll idiom after pr merge" {
  local tx
  tx="$(mk_transcript \
    "$(bash_entry 'gh pr merge 42')" \
    "$(bash_entry 'until grep -q READY log; do sleep 1; done')" \
    "$(bash_entry 'until test -f flag; do sleep 2; done')" \
    "$(bash_entry 'until curl -s host; do sleep 3; done')")"
  run "$(hook extract_pattern_proposal.sh)" <<< "$(mk_input "${tx}")"
  assert_success
  assert_message_contains "until/sleep poll idiom"
}

@test "caps candidates at 3 even when more present" {
  local tx
  tx="$(mk_transcript \
    "$(bash_entry 'gh pr merge 42')" \
    "$(bash_entry '.claude/scripts/a.sh')" "$(bash_entry '.claude/scripts/a.sh')" "$(bash_entry '.claude/scripts/a.sh')" \
    "$(bash_entry '.claude/scripts/b.sh')" "$(bash_entry '.claude/scripts/b.sh')" "$(bash_entry '.claude/scripts/b.sh')" \
    "$(bash_entry '/tmp/c.sh')" "$(bash_entry '/tmp/c.sh')" "$(bash_entry '/tmp/c.sh')" \
    "$(bash_entry '/tmp/d.sh')" "$(bash_entry '/tmp/d.sh')" "$(bash_entry '/tmp/d.sh')")"
  run "$(hook extract_pattern_proposal.sh)" <<< "$(mk_input "${tx}")"
  assert_success
  assert_message_contains "candidate(s) surfaced after PR merge (3)"
}

@test "throttle marker prevents repeat proposal within same session" {
  local tx
  tx="$(mk_transcript \
    "$(bash_entry 'gh pr merge 42')" \
    "$(bash_entry '.claude/scripts/wait-pr-ci.sh --prs 1')" \
    "$(bash_entry '.claude/scripts/wait-pr-ci.sh --prs 2')" \
    "$(bash_entry '.claude/scripts/wait-pr-ci.sh --prs 3')")"
  run "$(hook extract_pattern_proposal.sh)" <<< "$(mk_input "${tx}")"
  assert_success
  run "$(hook extract_pattern_proposal.sh)" <<< "$(mk_input "${tx}")"
  assert_silent
}

@test "honours EXTRACT_PATTERN_REPEAT override" {
  local tx
  tx="$(mk_transcript \
    "$(bash_entry 'gh pr merge 42')" \
    "$(bash_entry '.claude/scripts/wait-pr-ci.sh')" \
    "$(bash_entry '.claude/scripts/wait-pr-ci.sh')")"
  EXTRACT_PATTERN_REPEAT=2 run "$(hook extract_pattern_proposal.sh)" <<< "$(mk_input "${tx}")"
  assert_success
  assert_message_contains "wait-pr-ci.sh"
}
