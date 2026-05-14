#!/usr/bin/env bats

load '../lib/test_helper'

@test "--help prints usage and exits 0" {
  run "$(script fix-dockerfile-lint-lib.sh)" --help
  assert_success
  assert_output --partial "Usage:"
  assert_output --partial "--branch"
}

@test "missing --branch exits 2" {
  run "$(script fix-dockerfile-lint-lib.sh)"
  assert_failure 2
  assert_output --partial "--branch is required"
}

@test "unknown arg exits 2" {
  run "$(script fix-dockerfile-lint-lib.sh)" --bogus
  assert_failure 2
  assert_output --partial "unknown arg"
}

@test "--dry-run prints plan for all default repos and exits 0" {
  run "$(script fix-dockerfile-lint-lib.sh)" --branch chore/template-v0.28.2 --dry-run
  assert_success
  assert_output --partial "ycpss91255-docker/ai_agent @ chore/template-v0.28.2"
  assert_output --partial "ycpss91255-docker/ros_distro @ chore/template-v0.28.2"
  assert_output --partial "summary: patched=0 skipped=0 failed=0"
}

@test "--repos CSV narrows the repo list" {
  run "$(script fix-dockerfile-lint-lib.sh)" --branch chore/template-v0.28.2 --repos ai_agent,claude_code --dry-run
  assert_success
  assert_output --partial "ycpss91255-docker/ai_agent @ chore/template-v0.28.2"
  assert_output --partial "ycpss91255-docker/claude_code @ chore/template-v0.28.2"
  refute_output --partial "ycpss91255-docker/ros_distro"
}

@test "--org overrides default owner in dry-run output" {
  run "$(script fix-dockerfile-lint-lib.sh)" --branch chore/template-v0.28.2 --org other-org --repos foo --dry-run
  assert_success
  assert_output --partial "other-org/foo @ chore/template-v0.28.2"
  refute_output --partial "ycpss91255-docker/foo"
}
