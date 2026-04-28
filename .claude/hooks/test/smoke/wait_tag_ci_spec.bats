#!/usr/bin/env bats

load '../lib/test_helper'

setup() {
  GH_STUB_DIR="$(mktemp -d)"
  export PATH="${GH_STUB_DIR}:${PATH}"
}

teardown() {
  rm -rf "${GH_STUB_DIR}"
}

# stub_gh <json> — install a `gh` shim that always echoes <json> on stdout
# regardless of arguments. Used to feign `gh run list --json ...` output.
stub_gh() {
  local json="$1"
  printf '#!/usr/bin/env bash\nprintf %%s %q\n' "${json}" > "${GH_STUB_DIR}/gh"
  chmod +x "${GH_STUB_DIR}/gh"
}

@test "--help prints usage and exits 0" {
  run "$(script wait-tag-ci.sh)" --help
  assert_success
  assert_output --partial "Usage:"
  assert_output --partial "--repo"
  assert_output --partial "--branch"
}

@test "missing --repo exits 2" {
  run "$(script wait-tag-ci.sh)" --branch v0.12.2
  assert_failure 2
  assert_output --partial "--repo"
}

@test "missing --branch exits 2" {
  run "$(script wait-tag-ci.sh)" --repo a/b
  assert_failure 2
  assert_output --partial "--branch"
}

@test "unknown arg exits 2" {
  run "$(script wait-tag-ci.sh)" --bogus
  assert_failure 2
  assert_output --partial "unknown arg"
}

@test "all runs completed + success exits 0 with ALL_DONE" {
  stub_gh '[{"databaseId":1,"name":"release","status":"completed","conclusion":"success"},{"databaseId":2,"name":"build","status":"completed","conclusion":"success"}]'
  run "$(script wait-tag-ci.sh)" --repo a/b --branch v0.12.2 --interval 0 --max-iterations 3
  assert_success
  assert_output --partial "release: completed/success"
  assert_output --partial "build: completed/success"
  assert_output --partial "ALL_DONE"
}

@test "any completed run with conclusion != success exits 1 with FAIL <name>" {
  stub_gh '[{"databaseId":1,"name":"release","status":"completed","conclusion":"success"},{"databaseId":2,"name":"build","status":"completed","conclusion":"failure"}]'
  run "$(script wait-tag-ci.sh)" --repo a/b --branch v0.12.2 --interval 0 --max-iterations 3
  assert_failure 1
  assert_output --partial "build: completed/failure"
  assert_output --partial "FAIL build"
}

@test "any in_progress run keeps polling and hits max-iterations 124" {
  stub_gh '[{"databaseId":1,"name":"release","status":"in_progress","conclusion":null},{"databaseId":2,"name":"build","status":"completed","conclusion":"success"}]'
  run "$(script wait-tag-ci.sh)" --repo a/b --branch v0.12.2 --interval 0 --max-iterations 2
  assert_equal "${status}" 124
  assert_output --partial "release: in_progress/?"
  assert_output --partial "max-iterations"
}

@test "empty run list (tag just pushed) keeps polling and hits max-iterations 124" {
  stub_gh '[]'
  run "$(script wait-tag-ci.sh)" --repo a/b --branch v0.12.2 --interval 0 --max-iterations 2
  assert_equal "${status}" 124
  refute_output --partial "ALL_DONE"
  assert_output --partial "max-iterations"
}

@test "custom --check-filter narrows to a specific run name" {
  # Two runs, one matches --check-filter '.name=="release"', the other doesn't.
  # The matched one is success → ALL_DONE despite the unmatched 'build' being in_progress.
  stub_gh '[{"databaseId":1,"name":"release","status":"completed","conclusion":"success"},{"databaseId":2,"name":"build","status":"in_progress","conclusion":null}]'
  run "$(script wait-tag-ci.sh)" --repo a/b --branch v0.12.2 --interval 0 --max-iterations 3 \
    --check-filter '.name=="release"'
  assert_success
  assert_output --partial "release:"
  refute_output --partial "build:"
  assert_output --partial "ALL_DONE"
}

@test "cancelled conclusion counts as failure" {
  stub_gh '[{"databaseId":1,"name":"release","status":"completed","conclusion":"cancelled"}]'
  run "$(script wait-tag-ci.sh)" --repo a/b --branch v0.12.2 --interval 0 --max-iterations 3
  assert_failure 1
  assert_output --partial "FAIL release"
}
