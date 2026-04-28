---
name: wait-pr-ci
description: Wait for GitHub CI to settle — PR-scoped checks or tag/branch-scoped workflow runs — via the Monitor tool, instead of busy-polling with sleep loops.
---

# wait-pr-ci

Wait for GitHub CI to finish before merging or releasing, using `Monitor` so each state transition streams in as a notification and the agent isn't blocked on busy-poll sleeps.

Two flavours, one script each:

| Flavour | Script | When |
|---|---|---|
| **PR-scoped** (statusCheckRollup) | `.claude/scripts/wait-pr-ci.sh` | After `gh pr create` — waiting to merge once green. |
| **Tag/branch-scoped** (`gh run list --branch <ref>`) | `.claude/scripts/wait-tag-ci.sh` | After `git push origin <tag>` triggered `on: push: tags:` workflows like `release-test-tools` or `release-worker` — waiting to verify the release pipeline. |

The two are intentionally siblings — same CLI shape (`--repo`, `--check-filter`, `--interval`, `--max-iterations`), same exit codes (`0` = ALL_DONE, `1` = FAIL, `2` = arg error, `124` = max-iter exhausted), same Monitor-wrap pattern.

## PR-scoped — `wait-pr-ci.sh`

```
Monitor(
  description: "PR #<num> CI",   # or "PR #N1 + #N2 CI" for batches
  command: ".claude/scripts/wait-pr-ci.sh --repo <OWNER>/<REPO> --prs <CSV>",
  timeout_ms: 1800000,           # 30 min single PR; 2400000 (40 min) for batches
  persistent: false,             # script exits naturally on ALL_DONE / FAIL
)
```

The script prints one snapshot block (`PR<n>: checks=... mergeable=...` + `---`) per state transition, exits 0 on `ALL_DONE`, exits 1 on `FAIL <pr>`. 45s default poll interval — override with `--interval <sec>`.

**Per-repo `--check-filter`** (default matches template's `test` + `Integration ...`):

| Repo | Required checks | `--check-filter` |
|---|---|---|
| `template`, `multi_run` | `test` + `Integration E2E (...)` | (default) |
| Container repos (`agent/*`, `app/*`, `env/*`) | `call-docker-build / docker-build` | `'.name=="call-docker-build / docker-build"'` |
| `.github` (org profile) | none — PR review only | `'false'` (forces `no-checks` immediately) |

Cross-repo batches (e.g. one PR per downstream repo, like `/batch-template-upgrade` produces): spawn one Monitor per repo in parallel, each with `--repo <X> --prs <Y>`. Don't try to multiplex repos through one Monitor — `wait-pr-ci.sh` is single-repo by design.

## Tag/branch-scoped — `wait-tag-ci.sh`

```
Monitor(
  description: "tag v0.12.2 CI",
  command: ".claude/scripts/wait-tag-ci.sh --repo <OWNER>/<REPO> --branch <tag-or-branch>",
  timeout_ms: 1800000,
  persistent: false,
)
```

Same output shape (`<run-name>: <status>/<conclusion>` + `---`), same exit codes. Default `--check-filter` is `'true'` (all runs); narrow with e.g. `'.name=="release"'`. `--limit <N>` caps `gh run list` page size (default 10).

If the tag was just pushed, the first iteration may see no runs yet (`total == 0`); the loop keeps polling until at least one run appears, then waits for all to complete. This naturally handles the "GitHub took 30s to schedule the workflow" gap.

## Behaviour (both scripts)

- Each state transition prints exactly one snapshot block. Steady states print nothing.
- `ALL_DONE` is the final notification — that's the cue to merge / release.
- On any `FAIL`, the script prints `FAIL <name>` and exits 1. Investigate before retrying.
- `--max-iterations <N>` caps iterations for tests; production callers leave it unset and rely on `Monitor` `timeout_ms`.

## Anti-patterns

- **`sleep 60` between manual `gh pr checks` / `gh run list`** — burns a cache-miss with nothing to show; the agent's context fills with noisy poll output.
- **`gh pr merge --auto`** for the first merge — fine for queueing, but you don't get the failure-mode visibility the Monitor stream gives.
- **`gh run watch`** — polls a single workflow; PR-level rollup or branch-level run-list already aggregates matrix shards.
- **Inlining the loop in the Monitor `command`** — Claude Code's bash AST parser warns on parameter expansions like `${pair%:*}` ("Contains simple_expansion") and `<<<"$s"` ("Unhandled node type: string"); historically also choked on `[[ a != b ]]` (Monitor's eval wrapper escapes `!` to `\!`). Calling a permanent script side-steps all three.

## Pairing with merge / release

Once `ALL_DONE` arrives:

```bash
# PR
gh pr merge <PR> --repo <OWNER>/<REPO> --squash --delete-branch

# Tag (release flow continues per .claude/commands/release.md)
```

If PR merge fails with `not mergeable: branch is not up to date`, the head moved between rollup and merge. For dependabot PRs:

```bash
gh pr comment <PR> --repo <OWNER>/<REPO> --body "@dependabot rebase"
# then re-invoke wait-pr-ci on the same PR (CI re-runs on the rebased head)
```

For non-bot PRs, rebase locally + force-push, then re-invoke.

## See also

- `.claude/scripts/wait-pr-ci.sh` / `.claude/scripts/wait-tag-ci.sh` — the polling implementations. `--help` prints usage.
- CLAUDE.md → "## CI 監控（PR open 後）" — the project-level rule pointing back here.
- `.claude/commands/pr.md` — full PR workflow, calls this skill at step 6 ("Wait for CI").
- `.claude/commands/release.md` — release / tag workflow that should call the tag flavour after pushing the tag.
