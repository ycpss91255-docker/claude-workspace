#!/usr/bin/env bats

load '../lib/test_helper'

setup() {
  TX_DIR="$(mktemp -d)"
  export TX_DIR
  export TMPDIR="${TX_DIR}"
  export SESSION_SUMMARY_LOG_DIR="${TX_DIR}"
  unset SESSION_SUMMARY_DISABLE
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

edit_entry() {
  local path="$1"
  jq -nc --arg p "${path}" '{message:{role:"assistant",content:[{type:"tool_use",name:"Edit",input:{file_path:$p}}]}}'
}

mk_input() {
  local tx="$1" session_id="${2:-s1}" stop_active="${3:-false}"
  printf '{"transcript_path":"%s","session_id":"%s","stop_hook_active":%s,"hook_event_name":"Stop"}\n' \
    "${tx}" "${session_id}" "${stop_active}"
}

# ---- non-trigger paths ----

@test "silent on stop_hook_active=true (re-entry guard)" {
  local tx
  tx="$(mk_transcript "$(bash_entry 'git status')")"
  run "$(hook session_summary.sh)" <<< "$(mk_input "${tx}" s1 true)"
  assert_silent
}

@test "silent when SESSION_SUMMARY_DISABLE=1" {
  local tx
  tx="$(mk_transcript "$(bash_entry 'git status')")"
  SESSION_SUMMARY_DISABLE=1 run "$(hook session_summary.sh)" <<< "$(mk_input "${tx}")"
  assert_silent
}

@test "silent on missing transcript_path" {
  run "$(hook session_summary.sh)" <<< '{}'
  assert_silent
}

@test "silent on unreadable transcript_path" {
  run "$(hook session_summary.sh)" <<< '{"transcript_path":"/nonexistent","session_id":"s1","stop_hook_active":false}'
  assert_silent
}

@test "silent on empty transcript (no activity to log)" {
  local tx
  tx="$(mk_transcript)"
  run "$(hook session_summary.sh)" <<< "$(mk_input "${tx}")"
  assert_silent
  [[ ! -f "${TX_DIR}/claude-session-$(date +%F).log" ]]
}

# ---- fire paths ----

@test "appends summary when bash + edit + PR URL present" {
  local tx
  tx="$(mk_transcript \
    "$(bash_entry 'git push origin feature')" \
    "$(bash_entry 'gh pr create --title foo --body-file /tmp/x.md')" \
    "$(bash_entry 'gh pr view 42 --repo ycpss91255-docker/docker_harness')" \
    "$(bash_entry 'gh pr merge 42 https://github.com/ycpss91255-docker/docker_harness/pull/42 --auto')" \
    "$(edit_entry '/home/u/.claude/hooks/foo.sh')")"
  run "$(hook session_summary.sh)" <<< "$(mk_input "${tx}")"
  assert_success
  local log="${TX_DIR}/claude-session-$(date +%F).log"
  [[ -f "${log}" ]]
  grep -q 'session=s1' "${log}"
  grep -q 'Files touched (1)' "${log}"
  grep -q 'foo.sh' "${log}"
  grep -q 'Bash command mix' "${log}"
  grep -q 'gh=' "${log}"
  grep -q 'pull/42' "${log}"
}

@test "command mix groups git / gh / docker / make correctly" {
  local tx
  tx="$(mk_transcript \
    "$(bash_entry 'git status')" \
    "$(bash_entry 'git push')" \
    "$(bash_entry 'gh pr view 1')" \
    "$(bash_entry 'docker ps')" \
    "$(bash_entry 'make test')" \
    "$(bash_entry 'ls -la')")"
  run "$(hook session_summary.sh)" <<< "$(mk_input "${tx}")"
  assert_success
  local log="${TX_DIR}/claude-session-$(date +%F).log"
  grep -q 'git=2' "${log}"
  grep -q 'gh=1' "${log}"
  grep -q 'docker=1' "${log}"
  grep -q 'make=1' "${log}"
  grep -q 'other=1' "${log}"
}

@test "throttle marker prevents double-write within same session" {
  local tx
  tx="$(mk_transcript "$(bash_entry 'git status')")"
  run "$(hook session_summary.sh)" <<< "$(mk_input "${tx}")"
  assert_success
  local log="${TX_DIR}/claude-session-$(date +%F).log"
  local lines_before
  lines_before=$(wc -l < "${log}")
  run "$(hook session_summary.sh)" <<< "$(mk_input "${tx}")"
  assert_success
  local lines_after
  lines_after=$(wc -l < "${log}")
  [[ "${lines_before}" == "${lines_after}" ]]
}

@test "different session_id writes a fresh entry" {
  local tx
  tx="$(mk_transcript "$(bash_entry 'git status')")"
  run "$(hook session_summary.sh)" <<< "$(mk_input "${tx}" sA)"
  assert_success
  run "$(hook session_summary.sh)" <<< "$(mk_input "${tx}" sB)"
  assert_success
  local log="${TX_DIR}/claude-session-$(date +%F).log"
  local n
  n=$(grep -c 'session=' "${log}")
  [[ "${n}" -ge 2 ]]
}
