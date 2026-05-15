#!/usr/bin/env bats

load '../lib/test_helper'

setup() {
  REPO_DIR="$(mktemp -d)"
  export REPO_DIR
  ORIGIN_DIR="$(mktemp -d)"
  export ORIGIN_DIR
  git init -q --bare "${ORIGIN_DIR}/origin.git"
  git -C "${REPO_DIR}" init -q -b main
  git -C "${REPO_DIR}" config user.email t@t
  git -C "${REPO_DIR}" config user.name t
  git -C "${REPO_DIR}" remote add origin "${ORIGIN_DIR}/origin.git"
  echo init > "${REPO_DIR}/seed.txt"
  git -C "${REPO_DIR}" add -A >/dev/null
  git -C "${REPO_DIR}" commit -q -m init
  git -C "${REPO_DIR}" push -q -u origin main 2>/dev/null
  git -C "${REPO_DIR}" checkout -q -b feature
  unset CHECK_PUSH_DISABLE CHECK_PUSH_FILE_THRESHOLD
}

teardown() {
  rm -rf "${REPO_DIR}" "${ORIGIN_DIR}"
}

mk_input() {
  local cmd="$1"
  printf '{"tool_input":{"command":%s}}' "$(jq -Rs . <<< "${cmd}")"
}

# ---- non-trigger paths ----

@test "silent on non-push git command" {
  run "$(hook check_git_push_diff.sh)" <<< "$(mk_input 'git status')"
  assert_silent
}

@test "silent on non-git command" {
  run "$(hook check_git_push_diff.sh)" <<< "$(mk_input 'ls /tmp')"
  assert_silent
}

@test "silent when CHECK_PUSH_DISABLE=1" {
  echo a > "${REPO_DIR}/a.txt"
  git -C "${REPO_DIR}" add a.txt
  git -C "${REPO_DIR}" commit -q -m "add a"
  CHECK_PUSH_DISABLE=1 run "$(hook check_git_push_diff.sh)" \
    <<< "$(mk_input "git -C ${REPO_DIR} push origin feature")"
  assert_silent
}

@test "silent on --dry-run" {
  run "$(hook check_git_push_diff.sh)" \
    <<< "$(mk_input "git -C ${REPO_DIR} push --dry-run origin feature")"
  assert_silent
}

@test "silent on branch-delete push (remote :branch)" {
  run "$(hook check_git_push_diff.sh)" \
    <<< "$(mk_input "git -C ${REPO_DIR} push origin :stale-branch")"
  assert_silent
}

@test "silent on small diff below threshold (default 30)" {
  echo a > "${REPO_DIR}/a.txt"
  git -C "${REPO_DIR}" add a.txt >/dev/null
  git -C "${REPO_DIR}" commit -q -m "small add"
  run "$(hook check_git_push_diff.sh)" \
    <<< "$(mk_input "git -C ${REPO_DIR} push origin feature")"
  assert_silent
}

# ---- fire paths ----

@test "large diff above threshold fires" {
  local i=0
  while (( i < 5 )); do
    echo content > "${REPO_DIR}/file_${i}.txt"
    i=$((i + 1))
  done
  git -C "${REPO_DIR}" add -A >/dev/null
  git -C "${REPO_DIR}" commit -q -m "many files"
  CHECK_PUSH_FILE_THRESHOLD=2 run "$(hook check_git_push_diff.sh)" \
    <<< "$(mk_input "git -C ${REPO_DIR} push origin feature")"
  assert_success
  assert_message_contains "large diff"
  assert_message_contains "5 files"
}

@test "force-with-lease annotates large diff as likely rebase" {
  local i=0
  while (( i < 5 )); do
    echo content > "${REPO_DIR}/file_${i}.txt"
    i=$((i + 1))
  done
  git -C "${REPO_DIR}" add -A >/dev/null
  git -C "${REPO_DIR}" commit -q -m "many files"
  CHECK_PUSH_FILE_THRESHOLD=2 run "$(hook check_git_push_diff.sh)" \
    <<< "$(mk_input "git -C ${REPO_DIR} push --force-with-lease origin feature")"
  assert_success
  assert_message_contains "likely a rebase"
}

@test "generated-file path fires" {
  mkdir -p "${REPO_DIR}/dist"
  echo bundled > "${REPO_DIR}/dist/app.min.js"
  git -C "${REPO_DIR}" add -A >/dev/null
  git -C "${REPO_DIR}" commit -q -m "build output"
  run "$(hook check_git_push_diff.sh)" \
    <<< "$(mk_input "git -C ${REPO_DIR} push origin feature")"
  assert_success
  assert_message_contains "generated-path hit"
}

@test "binary blob fires" {
  printf '\x89PNG\r\n\x1a\nbinary-data\x00\x01' > "${REPO_DIR}/icon.png"
  git -C "${REPO_DIR}" add -A >/dev/null
  git -C "${REPO_DIR}" commit -q -m "add icon"
  run "$(hook check_git_push_diff.sh)" \
    <<< "$(mk_input "git -C ${REPO_DIR} push origin feature")"
  assert_success
  assert_message_contains "binary blob"
}

# ---- defensive ----

@test "silent when not in a git repo" {
  local nogit
  nogit="$(mktemp -d)"
  run "$(hook check_git_push_diff.sh)" \
    <<< "$(mk_input "git -C ${nogit} push origin feature")"
  assert_silent
  rm -rf "${nogit}"
}

@test "silent on empty tool_input" {
  run "$(hook check_git_push_diff.sh)" <<< '{}'
  assert_silent
}
