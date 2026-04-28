#!/usr/bin/env bash
# remind_use_body_file.sh — Claude Code PreToolUse hook (matcher: Bash)
#
# Fires before any Bash command. When `gh` is invoked with
# `--body "$(cat ...)"` or `--comment "$(cat ...)"`, emit a JSON
# systemMessage nudging Claude to use `--body-file <path>` instead.
# Non-blocking — exit 0.
#
# Why: `--body "$(cat /path)"` triggers Claude Code's bash AST parser
# warning ("Unhandled node type: string" for the embedded command
# substitution), prompting the user. `gh ... --body-file <path>` is the
# canonical form, parses cleanly, and works for `gh pr create / pr edit /
# pr comment / issue create / issue edit / issue comment / issue close`.
#
# Trigger: command starts with `gh ` (or chains gh later) AND contains
# `--body "$(cat ...)"` or `--comment "$(cat ...)"`. Silent on inline
# strings and `--body-file` already.

set -uo pipefail

main() {
  local input cmd msg
  input="$(cat)"
  cmd="$(printf '%s' "${input}" | jq -r '.tool_input.command // empty' 2>/dev/null)"

  [[ -z "${cmd}" ]] && return 0

  # Must invoke gh somewhere
  if ! printf '%s' "${cmd}" | grep -qE '(^|[[:space:]&|;])gh[[:space:]]'; then
    return 0
  fi

  # Must have --body|--comment "$(cat ...)" pattern.
  # `-e` separates flags from pattern (pattern starts with `--`).
  if ! printf '%s' "${cmd}" | grep -qE -e '--(body|comment)[[:space:]]+"?\$\([[:space:]]*cat[[:space:]]'; then
    return 0
  fi

  msg="gh ... --body|--comment \"\$(cat <path>)\" 觸發 parser 警告 \"Unhandled node type: string\" → user prompt。改用 \`gh ... --body-file <path>\`（gh CLI 原生支援，parses cleanly）。所有 gh subcommand（pr create/edit/comment、issue create/edit/comment/close）都支援 --body-file。"

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
