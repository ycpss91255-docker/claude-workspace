#!/usr/bin/env bash
# remind_use_body_file.sh — Claude Code PreToolUse hook (matcher: Bash)
#
# Fires before any Bash command. When `gh` is invoked with one of the
# following long-body shapes, emit a JSON systemMessage nudging Claude
# to write the body to a real path and pass `--body-file <path>`.
# Non-blocking — exit 0.
#
# Detected variants:
#   1. `gh ... --body "$(cat path)"` / `--comment "$(cat path)"`
#      → triggers `Unhandled node type: string` parser warning.
#   2. `gh ... --body-file -` (stdin), typically followed by `<<EOF`
#      heredoc → triggers `Unhandled node type: string` or
#      `Contains zsh =cmd equals expansion` depending on body content.
#
# Why both forms hit the parser: long quoted bodies (whether inlined as
# `"$(cat ...)"` substitutions or piped via heredoc into `--body-file -`)
# all run through the same string-parsing path. The canonical fix is
# identical: write the body to a real file (e.g. `/tmp/<name>.md`) and
# pass `--body-file /tmp/<name>.md`. Works on every gh subcommand:
# `pr create / pr edit / pr comment / issue create / issue edit /
# issue comment / issue close`.
#
# Silent on `--body-file <real-path>` (already canonical) and inline
# string bodies like `--body "short text"`.

set -uo pipefail

main() {
  local input cmd msg
  input="$(cat)"
  cmd="$(printf '%s' "${input}" | jq -r '.tool_input.command // empty' 2>/dev/null)"

  [[ -z "${cmd}" ]] && return 0

  # Must invoke gh somewhere.
  if ! printf '%s' "${cmd}" | grep -qE '(^|[[:space:]&|;])gh[[:space:]]'; then
    return 0
  fi

  local matched=0

  # Variant 1: --body|--comment "$(cat ...)".
  # `-e` separates flags from pattern (pattern starts with `--`).
  if printf '%s' "${cmd}" | grep -qE -e '--(body|comment)[[:space:]]+"?\$\([[:space:]]*cat[[:space:]]'; then
    matched=1
  fi

  # Variant 2: --body-file - (stdin). Match a literal dash as the
  # argument value, terminated by whitespace, end-of-string, or shell
  # operator. Excludes `--body-file -<something>` (no real flag uses
  # that, but be conservative) and `--body-file <path>` (silent).
  if printf '%s' "${cmd}" | grep -qE -e '--body-file[[:space:]]+-([[:space:]&|;<]|$)'; then
    matched=1
  fi

  if (( ! matched )); then
    return 0
  fi

  msg="gh long-body 寫法觸發 parser warning（\"Unhandled node type: string\" 或 \"Contains zsh =cmd equals expansion\"）→ user prompt。canonical 寫法：先 Write 落地成 \`/tmp/<name>.md\`，再 \`gh ... --body-file /tmp/<name>.md\`。所有 gh subcommand（pr create/edit/comment、issue create/edit/comment/close）都支援 --body-file。不要用 \`--body \"\$(cat path)\"\`，也不要用 \`--body-file - <<EOF\` 串 stdin。"

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
