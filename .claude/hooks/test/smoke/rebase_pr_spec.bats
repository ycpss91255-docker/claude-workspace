#!/usr/bin/env bats

load '../lib/test_helper'

# rebase-pr.sh stubs `gh` and `git` via PATH. The script never actually
# touches network / refs in these tests; we only validate decision
# logic, arg parsing, exit codes, and the worktree-resolver.

setup() {
  STUB_DIR="$(mktemp -d)"
  WORKSPACE="$(mktemp -d)"
  mkdir -p "${WORKSPACE}/worktree"
  export PATH="${STUB_DIR}:${PATH}"
  export WORKSPACE_DIR="${WORKSPACE}"
}

teardown() {
  rm -rf "${STUB_DIR}" "${WORKSPACE}"
  unset WORKSPACE_DIR
}

# stub_gh <json> — gh shim that echoes the given JSON for any args.
stub_gh() {
  printf '%s' "$1" > "${STUB_DIR}/gh_resp"
  cat > "${STUB_DIR}/gh" <<EOF
#!/usr/bin/env bash
cat "${STUB_DIR}/gh_resp"
EOF
  chmod +x "${STUB_DIR}/gh"
}

stub_gh_empty() {
  cat > "${STUB_DIR}/gh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "${STUB_DIR}/gh"
}

# mk_worktree <branch> — create a fake worktree dir whose
# `git branch --show-current` returns <branch>. We do this by initing
# a real git repo and checking out a branch with that name.
mk_worktree() {
  local branch="$1"
  local dir="${WORKSPACE}/worktree/test-wt-${branch//\//-}"
  mkdir -p "${dir}"
  (
    cd "${dir}" || exit 1
    git init -q -b main >/dev/null
    git config user.email t@t
    git config user.name t
    echo init > README
    git add README >/dev/null
    git commit -q -m init
    git checkout -q -b "${branch}"
  )
  printf '%s\n' "${dir}"
}

# ------------------------------------------------------------------
# Argument validation
# ------------------------------------------------------------------

@test "--help exits 0 and prints usage" {
  run "$(script rebase-pr.sh)" --help
  assert_success
  assert_output --partial "Usage:"
  assert_output --partial "rebase-pr.sh <pr>"
}

@test "missing <pr> exits 3" {
  run "$(script rebase-pr.sh)" --dry-run
  assert_failure 3
  assert_output --partial "missing <pr>"
}

@test "non-numeric <pr> exits 3" {
  run "$(script rebase-pr.sh)" --dry-run foo
  assert_failure 3
  assert_output --partial "invalid <pr>"
}

@test "unknown flag exits 3" {
  run "$(script rebase-pr.sh)" --bogus 42
  assert_failure 3
  assert_output --partial "unknown flag"
}

@test "duplicate positional exits 3" {
  run "$(script rebase-pr.sh)" --dry-run 42 99
  assert_failure 3
  assert_output --partial "unexpected arg"
}

# ------------------------------------------------------------------
# Pre-condition failures
# ------------------------------------------------------------------

@test "gh failure (PR not found) exits 3" {
  stub_gh_empty
  run "$(script rebase-pr.sh)" --dry-run 42 --repo a/b
  assert_failure 3
  assert_output --partial "not found"
}

@test "non-OPEN PR exits 3" {
  stub_gh '{"headRefName":"feat/x","baseRefName":"main","state":"MERGED"}'
  run "$(script rebase-pr.sh)" --dry-run 42 --repo a/b
  assert_failure 3
  assert_output --partial "MERGED"
  assert_output --partial "nothing to rebase"
}

@test "no matching worktree exits 3 with hint" {
  stub_gh '{"headRefName":"feat/nowhere","baseRefName":"main","state":"OPEN"}'
  run "$(script rebase-pr.sh)" --dry-run 42 --repo a/b
  assert_failure 3
  assert_output --partial "no worktree found for branch"
  assert_output --partial "feat/nowhere"
  assert_output --partial "--worktree"
}

@test "--worktree pointing at non-existent path exits 3" {
  stub_gh '{"headRefName":"feat/x","baseRefName":"main","state":"OPEN"}'
  run "$(script rebase-pr.sh)" --dry-run 42 --repo a/b --worktree /nonexistent/path
  assert_failure 3
  assert_output --partial "worktree path does not exist"
}

# ------------------------------------------------------------------
# Worktree resolution
# ------------------------------------------------------------------

@test "auto-resolves worktree by branch via WORKSPACE_DIR scan" {
  local wt
  wt="$(mk_worktree feat/found)"
  stub_gh '{"headRefName":"feat/found","baseRefName":"main","state":"OPEN"}'
  run "$(script rebase-pr.sh)" --dry-run 42 --repo a/b
  assert_success
  assert_output --partial "rebasing PR #42 (feat/found) onto origin/main"
  assert_output --partial "${wt}"
}

@test "--worktree overrides auto-resolution" {
  local wt
  wt="$(mk_worktree feat/auto)"
  local override
  override="$(mk_worktree feat/manual)"
  stub_gh '{"headRefName":"feat/auto","baseRefName":"main","state":"OPEN"}'
  run "$(script rebase-pr.sh)" --dry-run 42 --repo a/b --worktree "${override}"
  assert_success
  assert_output --partial "${override}"
}

@test "ambiguous worktree match (>1 branch hit) falls back to no-match exit 3" {
  # Two worktrees on the same branch -- locate_worktree returns empty,
  # script reports no-worktree-found.
  mk_worktree feat/dup >/dev/null
  local second="${WORKSPACE}/worktree/test-wt-feat-dup-second"
  mkdir -p "${second}"
  (
    cd "${second}" || exit 1
    git init -q -b main >/dev/null
    git config user.email t@t
    git config user.name t
    echo init > README
    git add README >/dev/null
    git commit -q -m init
    git checkout -q -b feat/dup
  )
  stub_gh '{"headRefName":"feat/dup","baseRefName":"main","state":"OPEN"}'
  run "$(script rebase-pr.sh)" --dry-run 42 --repo a/b
  assert_failure 3
  assert_output --partial "no worktree found"
}

# ------------------------------------------------------------------
# Dry-run preview
# ------------------------------------------------------------------

@test "--dry-run prints planned commands, no fetch / rebase / push" {
  mk_worktree feat/dryrun >/dev/null
  stub_gh '{"headRefName":"feat/dryrun","baseRefName":"main","state":"OPEN"}'
  run "$(script rebase-pr.sh)" --dry-run 42 --repo a/b
  assert_success
  assert_output --partial "[dry-run] would: git -C"
  assert_output --partial "fetch origin main"
  assert_output --partial "rebase origin/main"
  assert_output --partial "push --force-with-lease"
}

@test "--dry-run honours non-main base branch" {
  mk_worktree feat/x >/dev/null
  stub_gh '{"headRefName":"feat/x","baseRefName":"develop","state":"OPEN"}'
  run "$(script rebase-pr.sh)" --dry-run 42 --repo a/b
  assert_success
  assert_output --partial "fetch origin develop"
  assert_output --partial "rebase origin/develop"
}
