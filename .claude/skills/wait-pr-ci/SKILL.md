---
name: wait-pr-ci
description: Wait for one or more GitHub PR's CI checks to settle using the Monitor tool, instead of busy-polling with sleep loops.
---

# wait-pr-ci

After opening a PR, wait for its CI checks to settle (success / failure / skipped) before merging. Wraps `.claude/scripts/wait-pr-ci.sh` in a `Monitor` call so check-state transitions stream in as notifications and the agent isn't blocked on busy-poll sleeps.

## When to invoke

- Right after `gh pr create` and you intend to merge once green.
- Multiple PRs in flight from the same change set — pass them as one batch via `--prs <CSV>`.
- Re-running after `@dependabot rebase` (CI fires again on the rebased head).

Do **not** invoke for tag-triggered workflows (release-test-tools, release-worker) — those are not PR-scoped. For tag workflows, write a similar Monitor + `gh run list --branch <tag>` loop directly.

## Pattern

```
Monitor(
  description: "PR #<num> CI",   # or "PR #N1 + #N2 CI" for batches
  command: ".claude/scripts/wait-pr-ci.sh --repo <OWNER>/<REPO> --prs <CSV>",
  timeout_ms: 1800000,           # 30 min single PR; 2400000 (40 min) for batches
  persistent: false,             # script exits naturally on ALL_DONE / FAIL
)
```

The script prints one snapshot block (`PR<n>: checks=... mergeable=...` lines + `---`) per state transition, exits 0 on `ALL_DONE`, exits 1 on `FAIL <pr>`. 45s default poll interval — override with `--interval <sec>`.

## Per-repo check filter

The script's default jq filter (`.name=="test" or (.name|startswith("Integration"))`) matches the **template** repo's protected status checks. Other repos need a different `--check-filter`:

| Repo | Required checks | `--check-filter` |
|---|---|---|
| `template`, `multi_run` | `test` + `Integration E2E (...)` | (default) |
| Container repos (`agent/*`, `app/*`, `env/*`) | `call-docker-build / docker-build` | `'.name=="call-docker-build / docker-build"'` |
| `.github` (org profile) | none — PR review only | `'false'` (forces `no-checks` immediately) |

The filter is a jq inner expression substituted into `select(...)`. Pass via single quotes so the shell doesn't expand it. See CLAUDE.md → Branch Protection table for the canonical check names.

## Behaviour

- Each state transition prints exactly one snapshot block. Steady states print nothing.
- `ALL_DONE` is the final notification — that's the cue to merge.
- If a check goes to `FAIL`, the script prints `FAIL <pr>` and exits 1. Investigate before retrying.
- `--max-iterations <N>` (default 0 = unlimited) caps iterations for tests; production callers leave it unset and rely on `Monitor` `timeout_ms`.

## Anti-patterns

- **`sleep 60` between manual `gh pr checks`** — burns a cache-miss with nothing to show; the agent's context fills with noisy poll output.
- **`gh pr merge --auto`** for the first merge — fine for queueing, but you don't get the failure-mode visibility the Monitor stream gives.
- **Polling individual workflow runs** (`gh run watch`) — too granular; the PR-level rollup already aggregates matrix shards.
- **Inlining the loop in the Monitor `command`** — Claude Code's bash AST parser warns on parameter expansions like `${pair%:*}` ("Contains simple_expansion") and historically choked on `[[ a != b ]]` (Monitor's eval wrapper escapes `!` to `\!`). Calling a permanent script avoids both.

## Pairing with merge

Once `ALL_DONE` arrives, the merge is one shot:

```bash
gh pr merge <PR> --repo <OWNER>/<REPO> --squash --delete-branch
```

If merge fails with `not mergeable: branch is not up to date`, the head moved between rollup and merge. For dependabot PRs:

```bash
gh pr comment <PR> --repo <OWNER>/<REPO> --body "@dependabot rebase"
# then re-invoke wait-pr-ci on the same PR (CI re-runs on the rebased head)
```

For non-bot PRs, rebase locally + force-push, then re-invoke.

## See also

- `.claude/scripts/wait-pr-ci.sh` — the polling implementation. `--help` prints usage.
- CLAUDE.md → "## CI 監控（PR open 後）" — the project-level rule pointing back here.
- `.claude/commands/pr.md` — the full PR workflow that should call this skill at step 6 ("Wait for CI").
