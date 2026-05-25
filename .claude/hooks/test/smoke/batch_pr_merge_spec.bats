#!/usr/bin/env bats

load '../lib/test_helper'

setup() {
  export GH_STUB_DIR="$(mktemp -d)"
  export PATH="${GH_STUB_DIR}:${PATH}"
}

teardown() {
  rm -rf "${GH_STUB_DIR}"
}

# stub_gh_capture — install a `gh` shim that succeeds and writes its
# argv (one arg per line) to "${GH_STUB_DIR}/calls.log". Each invocation
# appends a separator line `---`.
stub_gh_capture() {
  cat > "${GH_STUB_DIR}/gh" <<'EOF'
#!/usr/bin/env bash
{
  printf '%s\n' "$@"
  printf '%s\n' '---'
} >> "${GH_STUB_DIR}/calls.log"
exit 0
EOF
  chmod +x "${GH_STUB_DIR}/gh"
}

stub_gh_fail() {
  cat > "${GH_STUB_DIR}/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh: simulated failure" >&2
exit 1
EOF
  chmod +x "${GH_STUB_DIR}/gh"
}

@test "--help prints usage and exits 0" {
  run "$(script batch-pr-merge.sh)" --help
  assert_success
  assert_output --partial "Usage:"
  assert_output --partial "<repo>:<pr>"
}

@test "no pairs exits 2" {
  run "$(script batch-pr-merge.sh)"
  assert_failure 2
  assert_output --partial "no <repo>:<pr> pairs given"
}

@test "bad pair (no colon) exits 2" {
  run "$(script batch-pr-merge.sh)" not-a-pair
  assert_failure 2
  assert_output --partial "unknown arg"
}

@test "non-numeric PR exits 2" {
  run "$(script batch-pr-merge.sh)" ai_agent:abc
  assert_failure 2
  assert_output --partial "PR number"
}

@test "short repo name is normalized to ycpss91255-docker/<repo>" {
  stub_gh_capture
  run "$(script batch-pr-merge.sh)" ai_agent:42
  assert_success
  assert_output --partial "merging ycpss91255-docker/ai_agent#42"
  refute_output --partial "merging ai_agent#42"
  run cat "${GH_STUB_DIR}/calls.log"
  assert_output --partial "ycpss91255-docker/ai_agent"
}

@test "full owner/repo form is accepted (no prefix added)" {
  stub_gh_capture
  run "$(script batch-pr-merge.sh)" other-org/repo:5
  assert_success
  assert_output --partial "merging other-org/repo#5"
  refute_output --partial "ycpss91255-docker/other-org"
}

@test "--owner overrides default for short form" {
  stub_gh_capture
  run "$(script batch-pr-merge.sh)" --owner my-org repo-a:7
  assert_success
  assert_output --partial "merging my-org/repo-a#7"
}

@test "--dry-run prints planned merges and skips gh invocation" {
  stub_gh_fail
  run "$(script batch-pr-merge.sh)" --dry-run ai_agent:1 claude_code:2
  assert_success
  assert_output --partial "would merge ycpss91255-docker/ai_agent#1"
  assert_output --partial "would merge ycpss91255-docker/claude_code#2"
  refute_output --partial "FAILED"
}

@test "successful merge invokes gh pr merge with --squash --delete-branch" {
  stub_gh_capture
  run "$(script batch-pr-merge.sh)" ai_agent:1
  assert_success
  run cat "${GH_STUB_DIR}/calls.log"
  assert_output --partial "pr"
  assert_output --partial "merge"
  assert_output --partial "--squash"
  assert_output --partial "--delete-branch"
}

@test "gh failure produces summary and exits 1" {
  stub_gh_fail
  run "$(script batch-pr-merge.sh)" ai_agent:1
  assert_failure 1
  assert_output --partial "FAILED"
  assert_output --partial "summary: merged=0 failed=1"
  assert_output --partial "ai_agent:1"
}

@test "mixed success and failure continues and reports both" {
  cat > "${GH_STUB_DIR}/gh" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *claude_code*)
    echo "gh: simulated failure" >&2
    exit 1
    ;;
  *)
    exit 0
    ;;
esac
EOF
  chmod +x "${GH_STUB_DIR}/gh"
  run "$(script batch-pr-merge.sh)" ai_agent:1 claude_code:2 codex_cli:3
  assert_failure 1
  assert_output --partial "summary: merged=2 failed=1"
  assert_output --partial "claude_code:2"
  refute_output --partial "ai_agent:1"  # only failed pairs listed in summary
}

# ── #146 --reset-local post-merge cleanup ──

@test "--reset-local is accepted and dry-run still skips gh + reset (#146)" {
  stub_gh_fail
  run "$(script batch-pr-merge.sh)" --reset-local --dry-run ai_agent:1
  assert_success
  assert_output --partial "would merge"
  refute_output --partial "reset-local"  # no reset attempted under --dry-run
}

@test "--reset-local: missing local checkout is logged + skipped, merge still ok (#146)" {
  # stub_gh_capture writes a successful gh stub. With no local checkout
  # for a fabricated repo, the reset-local resolver should log "no local
  # checkout for ... skipped" and the overall merge exits 0.
  stub_gh_capture
  run "$(script batch-pr-merge.sh)" --reset-local --owner fictional-org \
    fictional-repo-zzz:1
  assert_success
  assert_output --partial "reset-local: no local checkout for fictional-org/fictional-repo-zzz, skipped"
  assert_output --partial "summary: merged=1 failed=0"
}

@test "--reset-local does NOT run when merge fails (#146)" {
  stub_gh_fail
  run "$(script batch-pr-merge.sh)" --reset-local --owner fictional-org \
    fictional-repo-zzz:1
  assert_failure 1
  refute_output --partial "reset-local:"
}

@test "--reset-local appears in --help output (#146)" {
  run "$(script batch-pr-merge.sh)" --help
  assert_success
  assert_output --partial "--reset-local"
}

@test "unknown flag exits 2" {
  run "$(script batch-pr-merge.sh)" --bogus ai_agent:1
  assert_failure 2
  assert_output --partial "unknown arg"
}

@test "empty repo in pair exits 2" {
  run "$(script batch-pr-merge.sh)" :42
  assert_failure 2
  assert_output --partial "bad pair"
}

@test "empty PR in pair exits 2" {
  run "$(script batch-pr-merge.sh)" ai_agent:
  assert_failure 2
  assert_output --partial "bad pair"
}
