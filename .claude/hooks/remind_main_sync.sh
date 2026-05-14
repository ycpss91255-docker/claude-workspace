#!/usr/bin/env bash
# remind_main_sync.sh — Claude Code PreToolUse hook (matcher: Bash)
#
# Fires before `gh pr merge` (any flag combination). Emits a JSON
# systemMessage reminding the user to `git pull --ff-only origin main`
# on the main checkout after the merge lands, so the local main keeps
# tracking origin/main HEAD instead of freezing in place.
#
# Non-blocking (always exit 0). Two message variants:
#   - With --auto: merge is queued; remind to pull after CI passes
#   - Without --auto: merge is immediate; remind to pull right after
#
# Why: CLAUDE.md「Git 工作流程 > 主 checkout 狀態」要求主 checkout
# 永遠停在 origin/main HEAD — 意思是「持續 ff-tracking」不是「凍結在
# 某個 commit」。PR #89 那次踩到正是因為 local main 落後好幾個 PR,
# 從 stale base 起 worktree branch,後來才被迫 rebase。
#
# Trigger pattern: `gh pr merge` 出現在 command 任一段（含 chained &&）。
# 不限定 `--squash` / `--merge` / `--rebase`,任何 merge mode 都觸發。
# Skip read-only `gh pr view` / `gh pr checks` etc.

set -uo pipefail

main() {
  local input cmd msg variant
  input="$(cat)"
  cmd="$(printf '%s' "${input}" | jq -r '.tool_input.command // empty' 2>/dev/null)"

  [[ -z "${cmd}" ]] && return 0

  # Must contain `gh pr merge` (with whitespace before "merge" to exclude
  # `gh pr merged-by-N` etc. — currently no such subcommand but defensive).
  [[ "${cmd}" =~ gh[[:space:]]+pr[[:space:]]+merge([[:space:]]|$) ]] || return 0

  if [[ "${cmd}" =~ --auto([[:space:]]|$) ]]; then
    variant="queued"
    msg="Auto-merge queued. After CI passes and GitHub completes the merge, run \`git -C \$(git rev-parse --show-toplevel 2>/dev/null) pull --ff-only origin main\` (or the same from your main checkout) to keep local main tracking origin/main HEAD. See CLAUDE.md 'Git 工作流程 > 主 checkout 狀態'."
  else
    variant="immediate"
    msg="PR merged. Run \`git pull --ff-only origin main\` on your main checkout now so local main keeps tracking origin/main HEAD (don't let it freeze behind). See CLAUDE.md 'Git 工作流程 > 主 checkout 狀態'."
  fi

  jq -n --arg m "${msg}" --arg v "${variant}" '{
    systemMessage: $m,
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      additionalContext: ($m + " [variant=" + $v + "]")
    }
  }'

  return 0
}

main "$@"
