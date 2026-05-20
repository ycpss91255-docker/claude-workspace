# ADR-00000006: All Non-Main Work Lives in `git worktree`; Main Checkout Continuously ff-Tracks `origin/main`

- **Date:** 2026-05-20
- **Status:** Accepted

## Context

Each repo in the workspace (downstream repos + `template/` +
the docker_harness main checkout) is a separate git clone. When
multiple branches need to be touched in parallel (e.g. a
long-running feature PR + a hotfix on the same repo), the
classic approach -- `git checkout -B <branch>` in the main
checkout -- has two failure modes:

1. **Stash / WIP juggling.** Switching branches forces uncommitted
   work into the stash, or worse, gets accidentally committed to
   the wrong branch. The user must remember which branch they
   were on. Mistakes here cost rework.

2. **Stale base for new branches.** If the user starts a branch
   while `main` is several commits behind `origin/main`, the new
   branch is built on a stale base. CI catches it via "this
   branch is out of date", but only after the PR is open; by then
   the user has invested effort that has to be re-rebased.

`git worktree add` solves both: each branch gets its own
directory tree, so parallel work doesn't share an index or
stash, and `git worktree add -b <branch> main` forces the user
to pick a base explicitly.

PR #89 was the precedent. A worktree was added off `main` while
`main` was 2 commits behind `origin/main`. The branch built up
fine locally, but when the PR was opened, GitHub flagged it as
"BEHIND" and required a rebase. The forced rebase introduced a
conflict that took ~30 minutes to resolve. Lesson: the main
checkout's freshness matters every time a worktree is created.

## Decision

All non-main work lives in `<workspace>/worktree/<repo>-<N>/`,
created via `git worktree add ... -b <branch> main`. The
worktree directory naming convention is `<repo>-<N>` where N is
the issue / PR number, or a short branch slug if no number
exists.

The main checkout's role is reduced to "ff-tracking
`origin/main` HEAD":

- After every `gh pr merge`, the user runs
  `git pull --ff-only origin main` (or, when working-tree files
  are bind-mounted read-only,
  `git update-ref refs/heads/main refs/remotes/origin/main`) so
  local `main` keeps pace with the remote.
- The main checkout never holds in-progress work, never has
  uncommitted changes, never is on a non-main branch.
- `git worktree add ... -b <branch> main` always builds off a
  fresh base.

Enforcement: two PreToolUse hooks.

- `remind_main_sync.sh` fires before `gh pr merge`, reminding
  the user to ff `main` after merge.
- `check_main_fresh_before_worktree.sh` fires before
  `git worktree add ... main`, *blocking* if local `main` is
  behind `origin/main`. The user must ff first.

Cross-repo batch scripts (`batch-template-upgrade.sh` etc.) are
an explicit exception -- they include their own
`git fetch && git checkout -B main FETCH_HEAD` flow, run inside
the main checkout, and don't use worktrees.

## Alternatives

Three alternatives were considered and rejected:

1. **Status quo: `git checkout -B <branch>` in main checkout,
   stash discipline by convention.** Rejected: PR #89 + repeated
   stash mishaps showed the discipline doesn't hold under load.
   The mechanism has to enforce, not the convention.

2. **One clone per repo + one clone per branch (parallel checkouts
   instead of worktrees).** Rejected: parallel checkouts duplicate
   the entire `.git/` directory per branch, costing disk and
   slowing fetch / push. Worktrees share `.git/` and only
   duplicate the working tree.

3. **Forbid parallel branches; always finish one before starting
   another.** Rejected: real work is parallel (hotfix while
   feature is in CI; reviewer feedback on PR A while PR B is in
   progress). The mechanism needs to support parallelism, not
   wish it away.

## Consequences

- **`<workspace>/worktree/` is the convention**: gitignored at
  the workspace level, agents auto-create per-issue subdirectories
  (`worktree/<repo>-<N>/`).

- **Hooks enforce the discipline**: `check_main_fresh_before_
  worktree.sh` blocks stale-base worktrees; `remind_main_sync.sh`
  prompts the ff after merge.

- **Bind-mount-aware ff workaround**: the workspace `.git/`
  directory has read-only bind mounts on certain files. When
  `git pull --ff-only` fails with "Device or resource busy" on
  the working-tree side, `git update-ref refs/heads/main
  refs/remotes/origin/main` updates the branch pointer without
  touching the working tree files. Documented in CLAUDE.md.

- **Fresh-machine setup**: when `<workspace>/worktree/` does
  not exist (new clone, new machine), the agent is required to
  ask the user before creating the directory. Documented in
  CLAUDE.md "fresh machine" note.

- **Batch scripts are exempt**: `batch-template-upgrade.sh` /
  `batch-rename-template-to-base.sh` / etc. run in the main
  checkout because they intentionally mutate `main` across many
  repos as part of an atomic batch operation. Single-repo
  changes use worktrees; cross-repo batches use the main
  checkout.

## References

- Issue ycpss91255-docker/docker_harness#119 (this ADR's
  tracking issue; Tier 1 of #116).
- PR ycpss91255-docker/docker_harness#89 (the
  stale-base-rebase incident that motivated the
  `check_main_fresh_before_worktree.sh` hook).
- `.claude/hooks/check_main_fresh_before_worktree.sh` --
  blocking hook.
- `.claude/hooks/remind_main_sync.sh` -- non-blocking
  ff-after-merge reminder.
- `feedback_use_worktree` memory entry.
