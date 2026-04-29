Auto-fix one open GitHub issue under `ycpss91255-docker/<repo>` if its scope is reasonable, refusing (with an explanatory comment on the issue) when not.

Use this when you've already triaged via `/issue-check` and want to delegate one specific issue to the agent.

## Usage

```
/issue-fix <repo> <issue_num> [--dry-run]
```

- `<repo>` (required) — short name under `ycpss91255-docker`, e.g. `template`, `claude-workspace`, `ai_agent`, `ros1_bridge`
- `<issue_num>` (required) — issue number on that repo
- `--dry-run` (optional) — read + evaluate + print the plan; do NOT open a worktree, branch, comment on the issue, or open a PR

`$ARGUMENTS` is the raw arg string. Parse positionally; reject if `<repo>` or `<issue_num>` is missing or `<issue_num>` is not a positive integer.

## Steps

### 1. Fetch issue context

```bash
gh issue view <issue_num> -R "ycpss91255-docker/<repo>" \
  --json number,title,body,state,labels,assignees,author,createdAt,updatedAt,closedByPullRequestsReferences,comments,timelineItems
```

Hard-stop conditions (report to user, do **not** comment, exit):

- Issue is `closed`
- Has any open linked PR (via `closedByPullRequestsReferences` or timeline cross-references with state `OPEN`)
- Labels include `wontfix`, `invalid`, `duplicate`, or `do-not-merge`

For these, the user already triaged the issue — don't pile on noise.

### 2. Reasonableness check (the gate that decides comment-and-reject vs proceed)

Reject if **any** apply. On reject, post exactly one comment on the issue and stop:

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

Then report rejection to user (Traditional Chinese, 1 line) and exit.

### 3. (--dry-run only) Print the plan and exit

If `--dry-run`, print to user:

- Repo / issue number / title
- Reasonableness verdict: `PASS` or `REJECT: <reason>`
- If `PASS`:
  - Proposed branch name (`fix/issue-<num>-<slug>`)
  - File(s) likely to change (best-effort guess from issue body)
  - Test type(s) needed per CLAUDE.md TDD categories (smoke / unit / integration / lint)
  - Estimated diff size

Do NOT touch the working tree, do NOT open a worktree, do NOT comment on the issue, do NOT push or open a PR. Exit.

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
  # Per feedback_use_worktree memory: ASK user, do NOT silently mkdir
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

If during implementation the production diff (excluding test fixtures) exceeds **200 lines**, STOP:

- Do NOT push or open a PR
- Leave one comment on the issue: `Reviewed by /issue-fix automation; scope grew beyond the 200-line auto-fix limit during implementation. Deferring to a human.` + a 1-sentence summary of what blew the budget
- Leave the worktree in place for human inspection (do NOT auto-remove)
- Report to user with the worktree path

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

On `ALL_DONE`: report to user `[OK] <repo>#<num> → PR #<N> CI 綠，待你 merge：<url>`. Do NOT auto-merge — leave that to the user.

On `FAIL`: fetch the failing check log via `gh run view <run-id> --log-failed | tail -200`, summarise the top error in 1–2 lines, report to user with PR url + failure summary. Leave the worktree + branch in place for the user to debug.

### 8. Cleanup policy

- Reject (step 2): no worktree opened — nothing to clean.
- Dry-run (step 3): no worktree opened — nothing to clean.
- Scope-exceeded mid-implementation (step 5 hard limit): leave worktree in place, report path. Do NOT auto-remove.
- CI failure (step 7): leave worktree + branch in place, report path. Do NOT auto-remove.
- CI green (step 7): leave worktree alive — user may want to inspect before merging. After they merge, they can `git worktree remove <path>` themselves (the rm-worktree-no-prompt clause in `feedback_use_worktree` memory means you can remove worktree dirs without asking, but only when the user explicitly asks for cleanup; don't preemptively remove on success).

## Output (Traditional Chinese, 1 line)

Always finish with exactly one line summary to the user:

| Outcome | Format |
|---|---|
| Reject | `[REJECT] <repo>#<num>: <原因>，已留 comment` |
| Dry-run, would proceed | `[DRY-RUN] <repo>#<num>: PASS — 預估 <X> 行 diff，分類 <test types>` |
| Dry-run, would reject | `[DRY-RUN] <repo>#<num>: REJECT — <原因>` |
| Scope exceeded | `[ABORT] <repo>#<num>: 修改超過 200 行，已留 comment、worktree 留在 <path>` |
| PR opened, CI green | `[OK] <repo>#<num> → PR #<N> CI 綠，待你 merge：<url>` |
| PR opened, CI red | `[FAIL] <repo>#<num> PR #<N> CI 紅：<error summary>，worktree 留在 <path>` |

## Notes

- **Never auto-merge** — even if CI is green and the diff is small. Final merge is always a human decision.
- **One issue per invocation** — don't loop. Use `/issue-check` to triage, then call `/issue-fix` once per actionable issue.
- **Do not retry rejected issues** — if you've already commented "Reviewed by /issue-fix automation", subsequent invocations on the same issue should detect the existing reject comment and report `[REJECT] <repo>#<num>: previously declined`. This prevents stacking comments on disputed issues.
- **Branch protection respected** — all PRs go through review. Even though CI may pass, `gh pr merge` is the user's call.
- **CJK block** — `remind_no_chinese_in_git_artifacts.sh` (PreToolUse, blocking) prevents CJK in commit / PR / issue comment bodies. The user-facing summary line above stays in Traditional Chinese (terminal output, not a git/GitHub artifact).

Context from user: $ARGUMENTS
