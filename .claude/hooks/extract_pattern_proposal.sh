#!/usr/bin/env bash
# extract_pattern_proposal.sh — Claude Code Stop hook.
#
# After a PR merge signal in the session, scan the transcript for
# repeated patterns the user might want to capture as memory entries
# (`.claude/memory/feedback_*.md` / `project_*.md`). The hook does NOT
# write memory itself; it surfaces up to 3 candidates via systemMessage
# so the user (or the next assistant turn) decides whether they are
# worth keeping.
#
# Trigger condition: at least one `gh pr merge` Bash invocation in the
# session. This restricts proposals to natural task-completion moments
# — avoids nagging on every Stop event.
#
# Pattern detectors:
#   - Repeated script paths (any `.claude/scripts/<name>.sh` invoked
#     >= REPEAT_THRESHOLD times). Suggests the script could deserve a
#     skill / command if it does not have one.
#   - Repeated /tmp/<name>.sh executions (ad-hoc scripts that recur
#     across sessions). Suggests promotion to a permanent script.
#   - New non-obvious bash idioms (commands using `until`, `Monitor`,
#     `run_in_background` combined). Suggests a skill snippet.
#
# Throttled to once per session per (signal-set, candidate-list) hash.
# Non-blocking; cannot trigger /memory directly (hook output schema
# does not support that).
#
# Configuration env vars:
#   EXTRACT_PATTERN_DISABLE      Set to 1 to silence the hook entirely.
#   EXTRACT_PATTERN_REPEAT       Threshold for "repeated" detection
#                                (default 3).

set -uo pipefail

readonly TMP_DIR="${TMPDIR:-/tmp}"
readonly DEFAULT_REPEAT=3

main() {
  local input transcript_path session_id stop_active
  input="$(cat)"

  if [[ "${EXTRACT_PATTERN_DISABLE:-0}" == "1" ]]; then
    return 0
  fi

  transcript_path="$(printf '%s' "${input}" | jq -r '.transcript_path // empty' 2>/dev/null)"
  session_id="$(printf '%s' "${input}" | jq -r '.session_id // empty' 2>/dev/null)"
  stop_active="$(printf '%s' "${input}" | jq -r '.stop_hook_active // false' 2>/dev/null)"

  [[ "${stop_active}" == "true" ]] && return 0
  [[ -z "${transcript_path}" || ! -r "${transcript_path}" ]] && return 0

  local pr_merge_count
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
  [[ "${pr_merge_count}" =~ ^[0-9]+$ ]] || pr_merge_count=0

  (( pr_merge_count > 0 )) || return 0

  local repeat="${EXTRACT_PATTERN_REPEAT:-${DEFAULT_REPEAT}}"
  [[ "${repeat}" =~ ^[0-9]+$ ]] || repeat="${DEFAULT_REPEAT}"

  local bash_cmds
  bash_cmds="$(jq -rs '
      [
        .[]
        | select(.message?.role == "assistant")
        | .message.content[]?
        | select(.type == "tool_use" and .name == "Bash")
        | .input.command // ""
      ] | .[]
    ' "${transcript_path}" 2>/dev/null || true)"

  local -a candidates=()

  # Detector 1: repeated .claude/scripts/<name>.sh invocations.
  local repeated_scripts
  repeated_scripts="$(printf '%s\n' "${bash_cmds}" \
    | grep -oE '\.claude/scripts/[A-Za-z0-9_./-]+\.sh' \
    | sort | uniq -c \
    | awk -v t="${repeat}" '$1 >= t { sub(/^ +[0-9]+ +/, ""); print }')"
  while IFS= read -r script; do
    [[ -z "${script}" ]] && continue
    candidates+=("repeated invocation of ${script} (>= ${repeat}x): consider a skill or slash command if none exists yet")
  done <<< "${repeated_scripts}"

  # Detector 2: ad-hoc /tmp/*.sh re-runs.
  local tmp_scripts
  tmp_scripts="$(printf '%s\n' "${bash_cmds}" \
    | grep -oE '/tmp/[A-Za-z0-9_./-]+\.sh' \
    | sort | uniq -c \
    | awk -v t="${repeat}" '$1 >= t { sub(/^ +[0-9]+ +/, ""); print }')"
  while IFS= read -r script; do
    [[ -z "${script}" ]] && continue
    candidates+=("ad-hoc ${script} run >= ${repeat}x: promote to .claude/scripts/<name>.sh if it survives this session")
  done <<< "${tmp_scripts}"

  # Detector 3: Monitor + until poll idiom (signals a polling pattern
  # worth a skill snippet).
  local until_monitor_count
  until_monitor_count="$(printf '%s\n' "${bash_cmds}" \
    | grep -cE 'until[[:space:]].*do[[:space:]]+sleep' || true)"
  [[ "${until_monitor_count}" =~ ^[0-9]+$ ]] || until_monitor_count=0
  if (( until_monitor_count >= repeat )); then
    candidates+=("until/sleep poll idiom used >= ${repeat}x: a wait-* skill (.claude/skills/wait-pr-ci/SKILL.md style) may capture it cleanly")
  fi

  # Top 3 candidates only — keep the proposal short.
  local n=${#candidates[@]}
  (( n == 0 )) && return 0
  if (( n > 3 )); then
    candidates=("${candidates[@]:0:3}")
    n=3
  fi

  # Throttle by (session, candidate set hash).
  local sig marker
  sig="$(printf '%s' "${candidates[*]}" | md5sum | cut -d' ' -f1)"
  marker="${TMP_DIR}/.claude-extract-pattern-${session_id:-anon}-${sig}"
  if [[ -f "${marker}" ]]; then
    return 0
  fi
  : > "${marker}" 2>/dev/null || true

  local body=""
  local c
  for c in "${candidates[@]}"; do
    body+="
  - ${c}"
  done

  local msg
  msg="$(printf 'Memory / skill candidate(s) surfaced after PR merge (%d):%s\n\nThese are heuristics, not assertions. If a candidate is worth keeping, write the corresponding .claude/memory/feedback_*.md (or open a skill). Disable with EXTRACT_PATTERN_DISABLE=1.' \
    "${n}" "${body}")"

  jq -n --arg m "${msg}" '{systemMessage: $m}'
  return 0
}

main "$@"
