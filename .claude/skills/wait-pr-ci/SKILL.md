---
name: wait-pr-ci
description: Wait for one or more GitHub PR's CI checks to settle using the Monitor tool, instead of busy-polling with sleep loops.
---

# wait-pr-ci

After opening a PR, wait for its CI checks to settle (success / failure / skipped) before merging. Uses the Monitor tool with an `until` poll loop so the check transitions stream in as notifications and the agent isn't blocked on busy-poll sleeps.

## When to invoke

- Right after `gh pr create` and you intend to merge once green.
- Multiple PRs in flight from the same change set — pass them as a batch.
- Re-running after `@dependabot rebase` (CI fires again on rebased head).

Do **not** invoke for tag-triggered workflows (release-test-tools, release-worker) — those are not PR-scoped. For tag workflows, use a similar Monitor pattern but query `gh run list --branch <tag>` instead.

## Pattern

```bash
prev=""
while true; do
  out=""
  all_ready=1
  for pr in <PR-LIST>; do
    s=$(gh pr view "$pr" --repo <OWNER>/<REPO> --json mergeable,statusCheckRollup 2>/dev/null || echo '{}')
    state=$(jq -r '[.statusCheckRollup[]? | select(.name=="test" or (.name|startswith("Integration")))] | if length==0 then "no-checks" elif all(.conclusion=="SUCCESS") then "all-pass" elif any(.conclusion=="FAILURE") then "FAIL" else "pending" end' <<<"$s")
    m=$(jq -r '.mergeable // "?"' <<<"$s")
    out="${out}PR${pr}: checks=${state} mergeable=${m}"$'\n'
    case "${state}|${m}" in
      all-pass'|'MERGEABLE) : ;;
      *) all_ready=0 ;;
    esac
  done
  cur="${out}"
  case "${cur}" in
    "${prev}") : ;;
    *) printf "%s---\n" "${cur}" ;;
  esac
  prev="${cur}"
  if (( all_ready )); then
    echo "ALL_DONE"
    break
  fi
  sleep 45
done
```

> **Why `case` instead of `[[ a != b ]]`**: the Monitor tool's eval wrapper escapes `!` to `\!` ("history-expansion guard"), which breaks `[[ a != b ]]` with `conditional binary operator expected`. `set +H` does not save it. `case` patterns avoid the issue entirely. Note this also doesn't help with the separate `Contains simple_expansion` warning you'll hit on parameter expansions like `${var%:*}` — for that, extract the loop body into a permanent script (tracked as a follow-up issue).

Wrap that script in a `Monitor` tool call:

- `description`: `"PR #<num> CI"` (or `"PR #N1 + #N2 CI"` for batches) — appears in every notification.
- `timeout_ms`: `1800000` (30 min) for a single PR; `2400000` (40 min) for batches with retries.
- `persistent`: `false` — the loop exits naturally on `ALL_DONE`.

## Behaviour

- Each transition (`pending` → `all-pass` / `FAIL`) emits exactly one notification.
- `ALL_DONE` is the final notification — that's the cue to merge.
- If a check goes to `FAIL`, the loop also exits with a `FAIL` line; investigate before retrying.
- 45s poll interval keeps GitHub API quota happy and avoids spamming notifications when CI updates fast.

## Required check filter

The `select(.name=="test" or (.name|startswith("Integration")))` filter is **template-specific**. Adjust per repo:

| Repo | Required checks |
|---|---|
| `template`, `multi_run` | `test` + `Integration E2E (...)` |
| Container repos (`agent/*`, `app/*`, `env/*`) | `call-docker-build / docker-build` |
| `.github` (org profile) | none — just PR review |

Add or relax the `select` clause to match the protected status checks. See CLAUDE.md → Branch Protection table.

## Anti-patterns

- **`sleep 60` between manual `gh pr checks`** — burns a cache-miss with nothing to show; the agent's context fills with noisy poll output.
- **`gh pr merge --auto`** for the first merge — fine for queueing, but you don't get the failure-mode visibility the Monitor stream gives.
- **Polling individual workflow runs** (`gh run watch`) — too granular; PR-level rollup already aggregates the matrix shards.
- **`tail -f` style monitors for one-shot completion** — those never exit on their own. Use `until <check>; do sleep 30; done` so the loop ends naturally.

## Pairing with merge

Once `ALL_DONE` arrives, the merge call is one shot:

```bash
gh pr merge <PR> --repo <OWNER>/<REPO> --squash --delete-branch
```

If the merge fails with `not mergeable: branch is not up to date`, the head moved between rollup and merge. For dependabot PRs:

```bash
gh pr comment <PR> --repo <OWNER>/<REPO> --body "@dependabot rebase"
# then re-invoke wait-pr-ci on the same PR (CI re-runs on the rebased head)
```

For non-bot PRs, rebase locally + force-push, then re-invoke.

## See also

- CLAUDE.md → "## CI 監控（PR open 後）" — the project-level rule pointing back here.
- `.claude/commands/pr.md` — the full PR workflow that should call this skill at step 6 ("Wait for CI").
