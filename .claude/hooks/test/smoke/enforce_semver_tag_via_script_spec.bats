#!/usr/bin/env bats

load '../lib/test_helper'

# enforce_semver_tag_via_script.sh inspects only the tool_input.command
# string; no filesystem state is needed. Each test feeds a JSON blob
# through stdin and asserts deny / silent.

run_hook() {
  local cmd="$1"
  run "$(hook enforce_semver_tag_via_script.sh)" \
    <<< "{\"tool_input\":{\"command\":\"${cmd}\"}}"
}

@test "denies git tag -a vX.Y.Z" {
  run_hook "git tag -a v1.3.0 -m bump"
  assert_permission_decision "deny"
  assert_message_contains "release-tag flow gate"
  assert_message_contains ".claude/scripts/release-tag.sh"
}

@test "denies git tag -a vX.Y.Z-rcN" {
  run_hook "git tag -a v1.3.0-rc1 -m rc"
  assert_permission_decision "deny"
  assert_message_contains "release-tag flow gate"
}

@test "denies lightweight git tag vX.Y.Z" {
  run_hook "git tag v1.3.0"
  assert_permission_decision "deny"
}

@test "denies git push origin vX.Y.Z" {
  run_hook "git push origin v1.3.0"
  assert_permission_decision "deny"
}

@test "denies git push origin refs/tags/vX.Y.Z" {
  run_hook "git push origin refs/tags/v1.3.0"
  assert_permission_decision "deny"
}

@test "denies git push --tags" {
  run_hook "git push --tags"
  assert_permission_decision "deny"
}

@test "denies git push origin --tags" {
  run_hook "git push origin --tags"
  assert_permission_decision "deny"
}

@test "denies even when ACK env appears in command (Claude must use script, not raw git)" {
  run_hook "RELEASE_X_BUMP_ACK=v1.0.0 git tag v1.0.0"
  assert_permission_decision "deny"
}

@test "silent for git tag listing (-l)" {
  run_hook "git tag -l"
  assert_silent
}

@test "silent for git tag --list" {
  run_hook "git tag --list 'v*'"
  assert_silent
}

@test "silent for git tag with no args (list form)" {
  # Note: bare `git tag` is a list form. Hook should not deny because
  # no vX.Y.Z appears in the command string.
  run_hook "git tag"
  assert_silent
}

@test "silent for git tag -d <tag> (delete annotated)" {
  run_hook "git tag -d v1.3.0"
  assert_silent
}

@test "silent for git tag --delete <tag>" {
  run_hook "git tag --delete v1.3.0"
  assert_silent
}

@test "silent for git push origin :v1.3.0 (refspec delete)" {
  run_hook "git push origin :v1.3.0"
  assert_silent
}

@test "silent for regular branch push (no v-tag refspec)" {
  run_hook "git push origin main"
  assert_silent
}

@test "silent for non-version tag (e.g. release-2026)" {
  run_hook "git tag -a release-2026 -m yearly"
  assert_silent
}

@test "silent for non-git command" {
  run_hook "ls -la"
  assert_silent
}

@test "silent for invocation of .claude/scripts/release-tag.sh itself" {
  run_hook ".claude/scripts/release-tag.sh v1.3.0 -m 'release'"
  assert_silent
}

@test "denies git -C <dir> tag vX.Y.Z (global -C flag)" {
  run_hook "git -C /tmp/repo tag v1.3.0"
  assert_permission_decision "deny"
}

@test "denies git tag -f vX.Y.Z (force re-tag)" {
  run_hook "git tag -f v1.3.0"
  assert_permission_decision "deny"
}

@test "silent on empty command (defensive)" {
  run "$(hook enforce_semver_tag_via_script.sh)" <<< "{\"tool_input\":{\"command\":\"\"}}"
  assert_silent
}
