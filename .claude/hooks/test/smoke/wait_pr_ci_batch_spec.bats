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
# on stdout regardless of arguments.
stub_gh() {
  local json="$1"
  printf '#!/usr/bin/env bash\nprintf %%s %q\n' "${json}" > "${GH_STUB_DIR}/gh"
  chmod +x "${GH_STUB_DIR}/gh"
}

@test "--help prints usage and exits 0" {
  run "$(script wait-pr-ci-batch.sh)" --help
  assert_success
  assert_output --partial "Usage:"
  assert_output --partial "<repo>:<pr>"
}

@test "no pairs exits 2" {
  run "$(script wait-pr-ci-batch.sh)"
  assert_failure 2
  assert_output --partial "at least one"
}

@test "bad pair (no colon) exits 2" {
  run "$(script wait-pr-ci-batch.sh)" not-a-pair
  assert_failure 2
  assert_output --partial "expected <repo>:<pr>"
}

@test "non-numeric PR exits 2" {
  run "$(script wait-pr-ci-batch.sh)" ai_agent:abc
  assert_failure 2
  assert_output --partial "PR number"
}

@test "unknown flag exits 2" {
  run "$(script wait-pr-ci-batch.sh)" --bogus ai_agent:1
  assert_failure 2
  assert_output --partial "unknown arg"
}

@test "all-pass single short-form pair exits 0 with ALL_DONE" {
  stub_gh '{"mergeable":"MERGEABLE","statusCheckRollup":[{"name":"test","conclusion":"SUCCESS"}]}'
  run "$(script wait-pr-ci-batch.sh)" ai_agent:1 --interval 0 --max-iterations 3
  assert_success
  assert_output --partial "ycpss91255-docker/ai_agent#1: checks=all-pass mergeable=MERGEABLE"
  assert_output --partial "ALL_DONE"
}

@test "full owner/repo form is accepted (no prefix added)" {
  stub_gh '{"mergeable":"MERGEABLE","statusCheckRollup":[{"name":"test","conclusion":"SUCCESS"}]}'
  run "$(script wait-pr-ci-batch.sh)" other-org/repo:5 --interval 0 --max-iterations 3
  assert_success
  assert_output --partial "other-org/repo#5"
  refute_output --partial "ycpss91255-docker/other-org"
}

@test "--owner overrides default for short form" {
  stub_gh '{"mergeable":"MERGEABLE","statusCheckRollup":[{"name":"test","conclusion":"SUCCESS"}]}'
  run "$(script wait-pr-ci-batch.sh)" --owner my-org repo-a:7 --interval 0 --max-iterations 3
  assert_success
  assert_output --partial "my-org/repo-a#7"
}

@test "any FAILURE check exits 1 with FAIL <repo>#<pr>" {
  stub_gh '{"mergeable":"MERGEABLE","statusCheckRollup":[{"name":"test","conclusion":"FAILURE"}]}'
  run "$(script wait-pr-ci-batch.sh)" ai_agent:9 --interval 0 --max-iterations 3
  assert_failure 1
  assert_output --partial "checks=FAIL"
  assert_output --partial "FAIL ycpss91255-docker/ai_agent#9"
}

@test "multiple pairs all-pass + MERGEABLE exits 0" {
  stub_gh '{"mergeable":"MERGEABLE","statusCheckRollup":[{"name":"test","conclusion":"SUCCESS"}]}'
  run "$(script wait-pr-ci-batch.sh)" ai_agent:1 claude_code:2 codex_cli:3 \
        --interval 0 --max-iterations 3
  assert_success
  assert_output --partial "ai_agent#1"
  assert_output --partial "claude_code#2"
  assert_output --partial "codex_cli#3"
  assert_output --partial "ALL_DONE"
}

@test "custom --check-filter narrows to a non-default check name" {
  stub_gh '{"mergeable":"MERGEABLE","statusCheckRollup":[{"name":"call-docker-build / docker-build","conclusion":"SUCCESS"}]}'
  run "$(script wait-pr-ci-batch.sh)" \
        --check-filter '.name=="call-docker-build / docker-build"' \
        ai_agent:1 --interval 0 --max-iterations 3
  assert_success
  assert_output --partial "checks=all-pass"
}

@test "max-iterations exits 124 when stuck pending" {
  stub_gh '{"mergeable":"MERGEABLE","statusCheckRollup":[{"name":"test","conclusion":"PENDING"}]}'
  run "$(script wait-pr-ci-batch.sh)" ai_agent:1 --interval 0 --max-iterations 2
  assert_failure 124
}

@test "no matching checks counts as no-checks (not all-pass) and loops" {
  stub_gh '{"mergeable":"MERGEABLE","statusCheckRollup":[]}'
  run "$(script wait-pr-ci-batch.sh)" ai_agent:1 --interval 0 --max-iterations 2
  assert_failure 124
  assert_output --partial "checks=no-checks"
}

@test "all-pass but UNKNOWN mergeable does not exit ALL_DONE" {
  stub_gh '{"mergeable":"UNKNOWN","statusCheckRollup":[{"name":"test","conclusion":"SUCCESS"}]}'
  run "$(script wait-pr-ci-batch.sh)" ai_agent:1 --interval 0 --max-iterations 2
  assert_failure 124
  assert_output --partial "checks=all-pass mergeable=UNKNOWN"
}
