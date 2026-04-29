Auto-fix one or all open GitHub issues under `ycpss91255-docker/<repo>` when their scope is reasonable, refusing (with an explanatory comment on each issue) when not.

Use this when you've already triaged via `/issue-check` and want to delegate one specific issue, or sweep every open issue on a repo in one go.

## Usage

```
/issue-fix <repo> [<issue_num>|all] [--dry-run] [--limit N]
```

- `<repo>` (required) — short name under `ycpss91255-docker`, e.g. `template`, `claude-workspace`, `ai_agent`, `ros1_bridge`
- `<issue_num>` (optional) — issue number. **If omitted or set to `all`, run batch mode** over every open issue on the repo (oldest first, FIFO).
- `--dry-run` (optional) — read + evaluate + print the plan; do NOT open a worktree, branch, comment on the issue, or open a PR. Compatible with batch mode (lists verdict per issue).
- `--limit N` (optional, batch mode only) — process at most `N` issues after filtering. Default unlimited.

`$ARGUMENTS` is the raw arg string. Parse positionally; reject if `<repo>` is missing or `<issue_num>` (when given) is neither a positive integer nor the literal `all`.

## Modes

### Single-issue mode

Triggered when `<issue_num>` is a positive integer. Run steps 1–7 once for that issue, then emit the single-line Traditional Chinese summary (see Output).

### Batch mode

Triggered when `<issue_num>` is `all` or omitted. Sequence:

1. **List**:
   ```bash
   gh issue list -R "ycpss91255-docker/<repo>" --state open \
     --json number,title,createdAt,labels,assignees,closedByPullRequestsReferences \
     --limit 200
   ```
2. **Sort** ascending by `createdAt` (oldest first — FIFO).
3. **Pre-filter** (silent skip; counts toward "Skipped", not "Rejected" — these issues already have human action queued):
   - Has any open linked PR (already in progress)
   - Labels include `wontfix`, `invalid`, `duplicate`, `do-not-merge`, `discussion`, or `question`
   - Issue comments already contain a comment starting with `Reviewed by /issue-fix automation` (previously declined — never stack a second reject comment)
4. **Apply `--limit N`** if given (truncate to first `N` after filter).
5. **Iterate serially**: for each surviving issue, run the single-issue flow (steps 1–7 below). Wait for each PR's CI to settle (B2) before moving to the next issue.
6. **Stop the whole batch** (do NOT continue to next issue):
   - **CI red on a PR** → a real failure waits; don't compound debt by churning through more issues. Leave worktree + branch + report top error.
   - **`worktree/` directory missing on a fresh machine** → already an exit-2 condition in step 4 below; surface it and stop.
7. **Continue to next issue** (these are expected per-issue outcomes, not batch failures):
   - Reject (step 2 reasonableness gate fails) — comment posted, continue.
   - Scope exceeded mid-implementation (>200 lines) — comment posted, worktree left in place, continue.
   - PR opened, CI green — report ready-to-merge, continue.
8. **End conditions**: all issues processed, OR `--limit N` reached, OR a stop condition fired.
9. Emit the batch summary block (see Output) followed by the per-issue single-line summaries.

Batch mode is **serial, not parallel** — one issue's PR must reach CI green (or fail loudly) before the next starts. Trades wall-clock time for safety: each accepted PR is reviewable in isolation, and a CI red lights up immediately rather than getting buried under five more PRs.

## Steps (single-issue flow — also called once per issue in batch mode)

### 1. Fetch issue context

```bash
gh issue view <issue_num> -R "ycpss91255-docker/<repo>" \
  --json number,title,body,state,labels,assignees,author,createdAt,updatedAt,closedByPullRequestsReferences,comments,timelineItems
```

Hard-stop conditions (in single-issue mode: report to user, do **not** comment, exit. In batch mode: pre-filter already removed these; if one slipped through due to a race, treat as Skipped and continue):

- Issue is `closed`
- Has any open linked PR (via `closedByPullRequestsReferences` or timeline cross-references with state `OPEN`)
- Labels include `wontfix`, `invalid`, `duplicate`, or `do-not-merge`

### 2. Reasonableness check (the gate that decides comment-and-reject vs proceed)

Reject if **any** apply. On reject, post exactly one comment on the issue and stop this issue (in batch mode: continue to next):

| Reject reason | Trigger |
|---|---|
| Body too thin | <50 chars of meaningful content (excluding label/template boilerplate), or no reproducer / no described expected vs actual behaviour |
| Pure question / discussion | Body is "how do I X" / "what about Y" / "should we ..." with no defect claim and no concrete deliverable |
| Architectural decision | Requires picking a new abstraction / API / dependency where reasonable people would disagree |
| Cross-repo coordinated change | Touches `template/` AND a downstream — that's a `/batch-template-upgrade` job, not this command |
| Destructive migration | Changes `.env` / `setup.conf` / `compose.yaml` format, breaks existing users |
| Estimated >200 lines of diff | Includes all production lines; test fixtures excluded. Use issue body + linked code references to estimate |
| Conflicting / unclear | Multiple reporters disagree on root cause, or body has TODO/maybe phrasing for the core ask |

The reject comment MUST:

- Start with the literal sentence: `Reviewed by /issue-fix automation; declining to auto-fix.`
- State which check failed in 1 sentence (English — the `remind_no_chinese_in_git_artifacts.sh` PreToolUse hook will block CJK characters in `gh issue comment` bodies)
- Suggest what would unblock auto-fix (e.g. "add a minimal reproducer", "split into two issues — one for the template change, one for the downstream rollout", "discuss the abstraction in a comment first")
- Use `--body-file /tmp/issue-fix-reject-<num>.md` (write the body via the Write tool first; never inline `--body "$(cat ...)"` per CLAUDE.md `gh ... --body-file` rule)

Then record this issue's outcome and (single-issue mode) report rejection / (batch mode) continue to next issue.

### 3. (--dry-run only) Print the plan and exit (or continue iterating in batch mode)

If `--dry-run`, print to user (per issue):

- Repo / issue number / title
- Reasonableness verdict: `PASS` or `REJECT: <reason>`
- If `PASS`:
  - Proposed branch name (`fix/issue-<num>-<slug>`)
  - File(s) likely to change (best-effort guess from issue body)
  - Test type(s) needed per CLAUDE.md TDD categories (smoke / unit / integration / lint)
  - Estimated diff size

Do NOT touch the working tree, do NOT open a worktree, do NOT comment on the issue, do NOT push or open a PR.

In single-issue mode, exit after this. In batch mode, continue iterating; emit one verdict per issue, then a summary listing PASS / REJECT counts.

### 4. Open worktree (per CLAUDE.md worktree rule)

Resolve the source git tree:

| `<repo>` | Source git tree |
|---|---|
| `claude-workspace` | `${CLAUDE_PROJECT_DIR}` itself |
| any other (`template`, `ai_agent`, `app/<x>`, `env/<x>`, etc.) | `${CLAUDE_PROJECT_DIR}/<repo>` (the subtree / submodule subdir) |

Then:

```bash
WORKTREE="${CLAUDE_PROJECT_DIR}/worktree/<repo>-<issue_num>"
[ -d "${CLAUDE_PROJECT_DIR}/worktree" ] || {
  # Per feedback_use_worktree memory: ASK user, do NOT silently mkdir.
  # In batch mode, this is a hard stop for the whole batch.
  echo "worktree dir missing — ask user where to place it before continuing"
  exit 2
}
git -C "<source-tree>" worktree add "$WORKTREE" -b "fix/issue-<num>-<slug>" main
```

`<slug>` is a short kebab-case from the issue title (3–5 words, lowercase).

### 5. Make the fix in the worktree

Strict TDD (per CLAUDE.md):

1. Write a regression test FIRST (red). Place it in the right test category per CLAUDE.md "測試分類" table — smoke / unit / integration / lint.
2. Implement the minimal fix (green).
3. Verify per the repo's standard runner (always Docker, never bare `bats` / `shellcheck`):
   - `template` → `make -f Makefile.ci test`
   - `claude-workspace` → `make -C .claude/test test`
   - container repos (`agent/*` / `app/*` / `env/*`) → `./build.sh test`

If during implementation the production diff (excluding test fixtures) exceeds **200 lines**, STOP this issue:

- Do NOT push or open a PR
- Leave one comment on the issue: `Reviewed by /issue-fix automation; scope grew beyond the 200-line auto-fix limit during implementation. Deferring to a human.` + a 1-sentence summary of what blew the budget
- Leave the worktree in place for human inspection (do NOT auto-remove)
- Single-issue mode: report to user with the worktree path. Batch mode: record outcome and continue to next issue.

Sync `doc/test/TEST.md` / `doc/changelog/CHANGELOG.md` / 4-language READMEs per `/doc-sync` rules — same for any auto-fix as for any human-driven change.

### 6. Commit + push + create PR

Conventional commit (no AI attribution per CLAUDE.md):

```bash
git -C "$WORKTREE" add -A
git -C "$WORKTREE" commit -m "fix: <short description> (closes #<issue_num>)"
git -C "$WORKTREE" push -u origin "fix/issue-<num>-<slug>"
```

PR body MUST include `Closes #<issue_num>` so merging auto-closes the issue. Body is English only (CJK hook will block).

```bash
# Write body to a file first per CLAUDE.md `gh ... --body-file` rule
gh pr create -R "ycpss91255-docker/<repo>" \
  --head "fix/issue-<num>-<slug>" --base main \
  --title "fix: <short description>" \
  --body-file "/tmp/issue-fix-pr-<num>.md"
```

### 7. Wait for CI green (B2 — block until CI settles)

Use the `wait-pr-ci` skill (`.claude/skills/wait-pr-ci/SKILL.md`). Per-repo `--check-filter`:

| `<repo>` | `--check-filter` |
|---|---|
| `template`, `multi_run` | (default — covers `test` + `Integration E2E (...)`) |
| `claude-workspace` | `'.name=="bats + shellcheck + hadolint"'` |
| container repos (`agent/*` / `app/*` / `env/*`) | `'.name=="call-docker-build / docker-build"'` |
| `.github` (org profile) | `'false'` (no CI) |

On `ALL_DONE`: record outcome `[OK] <repo>#<num> → PR #<N> CI 綠` with url. Single-issue mode: report and exit. Batch mode: continue to next issue.

On `FAIL`: fetch the failing check log via `gh run view <run-id> --log-failed | tail -200`, summarise the top error in 1–2 lines. Single-issue mode: report and leave worktree + branch in place. Batch mode: **stop the whole batch here** — emit the batch summary with `Stopped: CI failure on PR #N` and exit.

### 8. Cleanup policy (same in both modes)

- Reject (step 2): no worktree opened — nothing to clean.
- Dry-run (step 3): no worktree opened — nothing to clean.
- Scope-exceeded mid-implementation (step 5 hard limit): leave worktree in place, report path. Do NOT auto-remove.
- CI failure (step 7): leave worktree + branch in place, report path. Do NOT auto-remove.
- CI green (step 7): leave worktree alive — user may want to inspect before merging. After they merge, they can `git worktree remove <path>` themselves.

## Output

### Single-issue mode (Traditional Chinese, 1 line)

| Outcome | Format |
|---|---|
| Reject | `[REJECT] <repo>#<num>: <原因>，已留 comment` |
| Dry-run, would proceed | `[DRY-RUN] <repo>#<num>: PASS — 預估 <X> 行 diff，分類 <test types>` |
| Dry-run, would reject | `[DRY-RUN] <repo>#<num>: REJECT — <原因>` |
| Scope exceeded | `[ABORT] <repo>#<num>: 修改超過 200 行，已留 comment、worktree 留在 <path>` |
| PR opened, CI green | `[OK] <repo>#<num> → PR #<N> CI 綠，待你 merge：<url>` |
| PR opened, CI red | `[FAIL] <repo>#<num> PR #<N> CI 紅：<error summary>，worktree 留在 <path>` |

### Batch mode summary block (Traditional Chinese)

End of run, after all per-issue lines (each in the single-issue format above), emit:

```
[BATCH] <repo>: N issue 處理完畢
  完成 (PR 開了 + CI 綠)：K — 待你 merge
  拒絕 (已留 comment)：M
  超出 200 行 (已留 comment + worktree)：S
  跳過 (既有 PR / wontfix / 之前已 declined)：T
  停止原因：<reason>
```

Where `<reason>` is one of: `批次跑完` / `--limit <N> 達上限` / `PR #<N> CI 紅` / `worktree 資料夾不存在` / `處理 dry-run 完畢`.

If `--dry-run`, replace the verb breakdown with: `預計修：K · 預計拒絕：M · 跳過：T`.

## Notes

- **Never auto-merge** — not in single-issue mode, not in batch mode. Final merge is always a human decision.
- **Batch mode is serial** — one PR's CI must settle before the next issue starts. Trades wall-clock time for safety; the agent makes one fix at a time, the user reviews / merges in their own pace.
- **Do not stack reject comments** — both modes detect existing `Reviewed by /issue-fix automation` comments and skip without re-commenting. Single-issue mode reports `[REJECT] <repo>#<num>: previously declined`; batch mode counts the issue under "跳過".
- **Branch protection respected** — all PRs go through review. Even if CI passes, `gh pr merge` is the user's call.
- **CJK block** — `remind_no_chinese_in_git_artifacts.sh` (PreToolUse, blocking) prevents CJK in commit / PR / issue comment bodies. The user-facing summary lines (single-issue + batch summary block) stay in Traditional Chinese — terminal output is not a git/GitHub artifact.

Context from user: $ARGUMENTS
