#!/usr/bin/env bash
# remind_strategic_compact.sh — Claude Code Stop hook.
#
# Fires when Claude's response finishes. Reads the session transcript
# and proposes `/compact` if the session has hit a "task boundary":
#   - A `gh pr merge` Bash invocation occurred this session
#   - Total tool-call count reached the threshold (default 50)
#
# Non-blocking. Cannot trigger `/compact` itself (hook output schema
# does not support that). Once-per-session per signal-set: a marker
# file in TMPDIR records the last proposal so the hook does not nag
# on every subsequent stop.
#
# Why: Claude Code's built-in auto-compaction fires when context
# nears the model limit, often mid-task. Strategic compact at *task
# boundaries* (PR merged, distilled plan written, etc.) preserves
# more useful state. See `.claude/skills/strategic-compact/SKILL.md`
# for the full rubric.
#
# Configuration via env vars:
#   STRATEGIC_COMPACT_TOOL_THRESHOLD  (default 50)
#   STRATEGIC_COMPACT_DISABLE         (set to 1 to disable the hook)

set -uo pipefail

readonly DEFAULT_TOOL_THRESHOLD=50
readonly TMP_DIR="${TMPDIR:-/tmp}"

main() {
  local input transcript_path session_id stop_active
  input="$(cat)"

  if [[ "${STRATEGIC_COMPACT_DISABLE:-0}" == "1" ]]; then
    return 0
  fi

  transcript_path="$(printf '%s' "${input}" | jq -r '.transcript_path // empty' 2>/dev/null)"
  session_id="$(printf '%s' "${input}" | jq -r '.session_id // empty' 2>/dev/null)"
  stop_active="$(printf '%s' "${input}" | jq -r '.stop_hook_active // false' 2>/dev/null)"

  # Avoid re-entry storms if a parent hook returned `decision=block`.
  [[ "${stop_active}" == "true" ]] && return 0

  [[ -z "${transcript_path}" || ! -r "${transcript_path}" ]] && return 0

  local tool_count pr_merge_count
  tool_count="$(jq -s '
      [
        .[]
        | select(.message?.role == "assistant")
        | .message.content[]?
        | select(.type == "tool_use")
      ] | length
    ' "${transcript_path}" 2>/dev/null || echo 0)"
  pr_merge_count="$(jq -s '
      [
        .[]
        | select(.message?.role == "assistant")
        | .message.content[]?
        | select(.type == "tool_use" and .name == "Bash")
        | .input.command // ""
        | select(test("gh[[:space:]]+pr[[:space:]]+merge"))
      ] | length
    ' "${transcript_path}" 2>/dev/null || echo 0)"

  # Defensive: ensure ints.
  [[ "${tool_count}" =~ ^[0-9]+$ ]] || tool_count=0
  [[ "${pr_merge_count}" =~ ^[0-9]+$ ]] || pr_merge_count=0

  local threshold="${STRATEGIC_COMPACT_TOOL_THRESHOLD:-${DEFAULT_TOOL_THRESHOLD}}"
  [[ "${threshold}" =~ ^[0-9]+$ ]] || threshold="${DEFAULT_TOOL_THRESHOLD}"

  local -a reasons=()
  if (( pr_merge_count > 0 )); then
    reasons+=("gh pr merge invoked ${pr_merge_count} time(s) this session")
  fi
  if (( tool_count >= threshold )); then
    reasons+=("tool-call count ${tool_count} >= threshold ${threshold}")
  fi

  (( ${#reasons[@]} == 0 )) && return 0

  # Throttle: once per session per signal-set hash.
  local signal_hash marker_path
  signal_hash="$(printf '%s|%s' "${pr_merge_count}" "$((tool_count / 25))" | md5sum | cut -d' ' -f1)"
  marker_path="${TMP_DIR}/claude-strategic-compact-${session_id:-anon}-${signal_hash}"
  if [[ -f "${marker_path}" ]]; then
    return 0
  fi
  : > "${marker_path}" 2>/dev/null || true

  local reasons_md=""
  local r
  for r in "${reasons[@]}"; do
    reasons_md+="
  - ${r}"
  done

  local msg
  msg="$(printf 'Strategic compact suggestion: session hit a task boundary.\nSignals:%s\nConsider running /compact now -- distilled state (files on disk, git, CLAUDE.md, TaskList) survives; mid-task reasoning does not. See .claude/skills/strategic-compact/SKILL.md for the when-to / when-not-to rubric.' \
    "${reasons_md}")"

  jq -n --arg m "${msg}" '{
    systemMessage: $m,
    hookSpecificOutput: {
      hookEventName: "Stop",
      additionalContext: $m
    }
  }'

  return 0
}

main "$@"
