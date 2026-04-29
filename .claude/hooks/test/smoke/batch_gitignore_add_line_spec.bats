#!/usr/bin/env bats

load '../lib/test_helper'

@test "--help prints usage and exits 0" {
  run "$(script batch-gitignore-add-line.sh)" --help
  assert_success
  assert_output --partial "Usage:"
  assert_output --partial "--line"
  assert_output --partial "--dry-run"
}

@test "missing --line exits 2" {
  run "$(script batch-gitignore-add-line.sh)" --why "x" --dry-run
  assert_failure 2
  assert_output --partial "--line is required"
}

@test "missing --why-file and --why exits 2" {
  run "$(script batch-gitignore-add-line.sh)" --line CLAUDE.md --dry-run
  assert_failure 2
  assert_output --partial "must provide"
}

@test "unknown arg exits 2" {
  run "$(script batch-gitignore-add-line.sh)" --bogus
  assert_failure 2
  assert_output --partial "unknown arg"
}

@test "--dry-run prints would-do line per repo without mutating" {
  run "$(script batch-gitignore-add-line.sh)" \
    --line CLAUDE.md --why "test" --dry-run --only agent/ai_agent,template
  assert_success
  assert_output --partial "dry-run"
  assert_output --partial "agent/ai_agent"
  assert_output --partial "template"
  assert_output --partial 'CLAUDE.md'
  refute_output --partial "ERROR"
}

@test "--only narrows to listed repos in dry-run" {
  run "$(script batch-gitignore-add-line.sh)" \
    --line CLAUDE.md --why "test" --dry-run --only agent/ai_agent
  assert_success
  assert_output --partial "agent/ai_agent"
  refute_output --partial "env/ros_noetic"
  refute_output --partial "template"
}

@test "branch name slugifies the --line value" {
  run "$(script batch-gitignore-add-line.sh)" \
    --line "weird path/with spaces!" --why "test" --dry-run --only agent/ai_agent
  assert_success
  assert_output --partial "branch=chore/gitignore-add-weird-path-with-spaces-"
}
