#!/usr/bin/env bash
# check_no_ai_attribution.sh — Claude Code PostToolUse hook
#
# Fires on Edit / Write / MultiEdit. Scans the touched file for AI-attribution
# markers (e.g. "Generated with Claude Code", "Co-Authored-By: Claude ...").
# Non-blocking — exit 0; emits a JSON systemMessage on hits.
#
# Why: CLAUDE.md「不加 AI 歸屬標記」明文禁止 commit message / PR body /
# code comment 出現此類訊息 — 對 reviewer 無用、只是視覺噪音。當 Claude
# 寫入 commit message 暫存檔 (-F) 或 PR body file (--body-file) 時，這個
# hook 會在檔案落地的瞬間把問題抓出來。命令列直接帶字串的情況由
# remind_no_ai_attribution.sh (PreToolUse Bash) 負責。
#
# Patterns (case-insensitive):
#   - Generated with [Claude Code]  /  Generated with Claude Code
#   - Co-Authored-By: Claude
#   - "robot-emoji Generated with" 這類常見 boilerplate (emoji 由 check_no_emoji 抓)

set -uo pipefail

main() {
  local input file_path hits msg
  input="$(cat)"
  file_path="$(printf '%s' "${input}" | jq -r '
    .tool_input.file_path
    // .tool_response.filePath
    // empty
  ' 2>/dev/null)"

  [[ -z "${file_path}" || ! -f "${file_path}" ]] && return 0

  case "${file_path}" in
    */.git/*|*/node_modules/*|*/coverage/*|*/.cache/*) return 0 ;;
    */check_no_ai_attribution.sh|*/remind_no_ai_attribution.sh) return 0 ;;
    # Meta-rule docs that legitimately quote the forbidden patterns to forbid them.
    */CLAUDE.md|*/.claude/commands/*.md|*/.claude/skills/*/SKILL.md) return 0 ;;
    # Project doc conventions that catalog/describe rule violations.
    */doc/test/TEST.md|*/doc/changelog/CHANGELOG.md) return 0 ;;
    # Hook-test fixtures must contain the forbidden patterns to assert detection.
    */.claude/hooks/test/*) return 0 ;;
  esac

  if file --mime "${file_path}" 2>/dev/null | grep -qE 'charset=binary'; then
    return 0
  fi

  hits="$(grep -niE 'Generated with (\[)?Claude Code|Co-Authored-By:[[:space:]]*Claude' \
    "${file_path}" 2>/dev/null \
    | head -5 \
    | awk -F: '{
        line=$1; $1=""; sub(/^ /, "");
        snippet=$0; if (length(snippet) > 80) snippet=substr(snippet, 1, 80);
        printf "  line %s: %s\n", line, snippet
      }')"

  [[ -z "${hits}" ]] && return 0

  msg="$(printf 'AI 歸屬標記 in %s（CLAUDE.md「不加 AI 歸屬標記」: PR body / commit message / code comment 一律不要加 Generated with Claude Code、Co-Authored-By: Claude 等）:\n%s' \
    "${file_path}" "${hits}")"

  jq -n --arg m "${msg}" '{
    systemMessage: $m,
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: $m
    }
  }'

  return 0
}

main "$@"
