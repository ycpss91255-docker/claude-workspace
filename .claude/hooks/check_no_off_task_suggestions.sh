#!/usr/bin/env bash
# check_no_off_task_suggestions.sh -- Claude Code Stop hook.
#
# Reads the session transcript and scans the LAST assistant message for
# off-task-suggestion phrases (user breaks, meals, wellness, schedule).
# Emits a systemMessage when matched; never blocks. Throttled once per
# session per matched phrase via TMPDIR marker.
#
# Why: refs ycpss91255-docker/docker_harness#109. Closing a technical
# session turn with `Or stop for dinner?` (or similar) adds friction and
# breaks focus. The user manages their own time. End-of-turn proposals
# should be concrete technical follow-ups only.
#
# Configuration via env vars:
#   NO_OFF_TASK_REMIND_DISABLE  (set to 1 to disable the hook)

set -uo pipefail

readonly TMP_DIR="${TMPDIR:-/tmp}"

# Extended regex alternation. Outer capture (group 1) holds the matched
# phrase that surfaces in the reminder. All terms are lowercase; the
# transcript text is lowercased before matching.
readonly OFF_TASK_REGEX='(take a break|stop for (dinner|lunch|breakfast|food|a meal)|need (some )?rest|do it tomorrow|come back (later|tomorrow)|are you tired|you tired)'

main() {
  local input transcript_path session_id stop_active
  input="$(cat)"

  if [[ "${NO_OFF_TASK_REMIND_DISABLE:-0}" == "1" ]]; then
    return 0
  fi

  transcript_path="$(printf '%s' "${input}" | jq -r '.transcript_path // empty' 2>/dev/null)"
  session_id="$(printf '%s' "${input}" | jq -r '.session_id // empty' 2>/dev/null)"
  stop_active="$(printf '%s' "${input}" | jq -r '.stop_hook_active // false' 2>/dev/null)"

  [[ "${stop_active}" == "true" ]] && return 0
  [[ -z "${transcript_path}" || ! -r "${transcript_path}" ]] && return 0

  local last_msg
  last_msg="$(jq -s -r '
      [
        .[]
        | select(.message?.role == "assistant")
        | (
            .message.content
            | if type == "string" then .
              elif type == "array" then [.[] | select(.type? == "text") | .text] | join("\n")
              else "" end
          )
      ] | last // ""
    ' "${transcript_path}" 2>/dev/null || echo "")"

  [[ -z "${last_msg}" ]] && return 0

  local lower
  lower="$(printf '%s' "${last_msg}" | tr '[:upper:]' '[:lower:]')"

  local matched=""
  if [[ "${lower}" =~ ${OFF_TASK_REGEX} ]]; then
    matched="${BASH_REMATCH[1]}"
  fi
  [[ -z "${matched}" ]] && return 0

  # Throttle: once per session per matched phrase.
  local phrase_hash marker_path
  phrase_hash="$(printf '%s' "${matched}" | md5sum | cut -d' ' -f1)"
  marker_path="${TMP_DIR}/claude-no-off-task-${session_id:-anon}-${phrase_hash}"
  if [[ -f "${marker_path}" ]]; then
    return 0
  fi
  : > "${marker_path}" 2>/dev/null || true

  local msg
  msg="$(printf 'Off-task suggestion detected in session output: "%s".\nThe user manages their own time. End-of-turn proposals should be concrete technical follow-ups (next issue / next PR / next test / next command) only. See .claude/memory/feedback_no_off_task_suggestions.md.' "${matched}")"

  jq -n --arg m "${msg}" '{systemMessage: $m}'
  return 0
}

main "$@"
