#!/usr/bin/env bats

load '../lib/test_helper'

setup() {
  GH_STUB_DIR="$(mktemp -d)"
  export PATH="${GH_STUB_DIR}:${PATH}"
}

teardown() {
  rm -rf "${GH_STUB_DIR}"
}

# stub_gh <json> — install a `gh` shim that always echoes the given JSON
# on stdout regardless of arguments. Used to feign `gh pr view` output.
stub_gh() {
  local json="$1"
  printf '#!/usr/bin/env bash\nprintf %%s %q\n' "${json}" > "${GH_STUB_DIR}/gh"
  chmod +x "${GH_STUB_DIR}/gh"
}

@test "--help prints usage and exits 0" {
  run "$(script wait-pr-ci.sh)" --help
  assert_success
  assert_output --partial "Usage:"
  assert_output --partial "--repo"
  assert_output --partial "--prs"
}

@test "missing --repo exits 2" {
  run "$(script wait-pr-ci.sh)" --prs 1
  assert_failure 2
  assert_output --partial "--repo"
}

@test "missing --prs exits 2" {
  run "$(script wait-pr-ci.sh)" --repo a/b
  assert_failure 2
  assert_output --partial "--prs"
}

@test "unknown arg exits 2" {
  run "$(script wait-pr-ci.sh)" --bogus
  assert_failure 2
  assert_output --partial "unknown arg"
}

@test "all-pass + MERGEABLE single PR exits 0 with ALL_DONE" {
  stub_gh '{"mergeable":"MERGEABLE","statusCheckRollup":[{"name":"test","conclusion":"SUCCESS"}]}'
  run "$(script wait-pr-ci.sh)" --repo a/b --prs 1 --interval 0 --max-iterations 3
  assert_success
  assert_output --partial "PR1: checks=all-pass mergeable=MERGEABLE"
  assert_output --partial "ALL_DONE"
}

@test "any FAILURE check exits 1 with FAIL <pr>" {
  stub_gh '{"mergeable":"MERGEABLE","statusCheckRollup":[{"name":"test","conclusion":"FAILURE"}]}'
  run "$(script wait-pr-ci.sh)" --repo a/b --prs 7 --interval 0 --max-iterations 3
  assert_failure 1
  assert_output --partial "checks=FAIL"
  assert_output --partial "FAIL 7"
}

@test "multiple PRs all-pass + MERGEABLE exits 0" {
  stub_gh '{"mergeable":"MERGEABLE","statusCheckRollup":[{"name":"test","conclusion":"SUCCESS"}]}'
  run "$(script wait-pr-ci.sh)" --repo a/b --prs 1,2,3 --interval 0 --max-iterations 3
  assert_success
  assert_output --partial "PR1:"
  assert_output --partial "PR2:"
  assert_output --partial "PR3:"
  assert_output --partial "ALL_DONE"
}

@test "custom --check-filter narrows to a non-default check name" {
  # Default filter looks for name=="test"; provide only name=="build"
  # → with default filter, length==0 → no-checks → not ready → loops.
  # With --check-filter '.name=="build"' → all-pass → ALL_DONE.
  stub_gh '{"mergeable":"MERGEABLE","statusCheckRollup":[{"name":"build","conclusion":"SUCCESS"}]}'
  run "$(script wait-pr-ci.sh)" --repo a/b --prs 1 --interval 0 --max-iterations 3 \
    --check-filter '.name=="build"'
  assert_success
  assert_output --partial "ALL_DONE"
}

@test "max-iterations exits 124 when stuck pending" {
  stub_gh '{"mergeable":"MERGEABLE","statusCheckRollup":[{"name":"test","conclusion":"PENDING"}]}'
  run "$(script wait-pr-ci.sh)" --repo a/b --prs 1 --interval 0 --max-iterations 2
  assert_equal "${status}" 124
  assert_output --partial "max-iterations"
}

@test "no matching checks counts as no-checks (not all-pass) and loops" {
  # statusCheckRollup has only "lint", default filter wants "test" → length==0 → no-checks.
  # Should NOT trigger ALL_DONE — we exit 124 via max-iterations.
  stub_gh '{"mergeable":"MERGEABLE","statusCheckRollup":[{"name":"lint","conclusion":"SUCCESS"}]}'
  run "$(script wait-pr-ci.sh)" --repo a/b --prs 1 --interval 0 --max-iterations 2
  assert_equal "${status}" 124
  assert_output --partial "checks=no-checks"
}

@test "all-pass but UNKNOWN mergeable does not exit ALL_DONE" {
  stub_gh '{"mergeable":"UNKNOWN","statusCheckRollup":[{"name":"test","conclusion":"SUCCESS"}]}'
  run "$(script wait-pr-ci.sh)" --repo a/b --prs 1 --interval 0 --max-iterations 2
  assert_equal "${status}" 124
  assert_output --partial "PR1: checks=all-pass mergeable=UNKNOWN"
  refute_output --partial "ALL_DONE"
}
