#!/usr/bin/env bash
# remind_no_ai_attribution.sh — Claude Code PreToolUse hook (matcher: Bash)
#
# Fires before any Bash command. When the command embeds AI-attribution
# markers in a git/gh argument (commit -m, gh pr create --body 等)，emit
# a JSON systemMessage. Non-blocking — exit 0.
#
# Why: CLAUDE.md「不加 AI 歸屬標記」明文禁止 commit message / PR body /
# code comment 出現此類訊息。檔案落地的情況由 check_no_ai_attribution.sh
# (PostToolUse Edit/Write) 抓；命令列直接帶 inline 字串的情況由本 hook
# 抓 (e.g. `git commit -m "feat: x\n\nCo-Authored-By: Claude ..."`).
#
# Trigger: command 含 `git commit`/`gh pr create`/`gh pr edit`/
# `gh pr comment`/`gh issue create`/`gh issue edit`/`gh issue comment`，
# 且 command 字串裡偵測到 AI 歸屬 pattern。

set -uo pipefail

main() {
  local input cmd msg
  input="$(cat)"
  cmd="$(printf '%s' "${input}" | jq -r '.tool_input.command // empty' 2>/dev/null)"

  [[ -z "${cmd}" ]] && return 0

  case "${cmd}" in
    *"git commit"*|*"gh pr create"*|*"gh pr edit"*|*"gh pr comment"*) ;;
    *"gh issue create"*|*"gh issue edit"*|*"gh issue comment"*) ;;
    *) return 0 ;;
  esac

  if ! printf '%s' "${cmd}" | grep -qiE 'Generated with (\[)?Claude Code|Co-Authored-By:[[:space:]]*Claude'; then
    return 0
  fi

  msg="AI 歸屬標記 in command（CLAUDE.md「不加 AI 歸屬標記」: 一律不要加 Generated with Claude Code、Co-Authored-By: Claude 等。對 reviewer 無用、只是視覺噪音）。請從訊息中移除這類行再 commit / open PR。"

  jq -n --arg m "${msg}" '{
    systemMessage: $m,
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      additionalContext: $m
    }
  }'

  return 0
}

main "$@"
