#!/usr/bin/env bash
# remind_adr_on_design_decision.sh -- Claude Code Stop hook.
#
# Fires when Claude's response finishes. Reads the session transcript;
# if the session had multiple rationale-shaped exchanges AND did not
# Write / Edit any `doc/adr/*` file, prints a non-blocking nudge
# pointing at the `/adr` slash command.
#
# Non-blocking. Cannot create the ADR itself (hook output schema
# does not support that). Throttled once-per-session per signal-set
# via a TMPDIR marker, like `remind_strategic_compact.sh`.
#
# Heuristic for "rationale-shaped":
#   Count user + assistant messages whose text contains one of:
#     - "trade-off" / "trade off" / "tradeoff"
#     - "alternative" / "alternatives"
#     - "rejected because"
#     - "why not"
#     - "we'll go with" / "going with" / "let's go with"
#     - "decided to" / "decision to"
#     - "out of scope because"
#   If the count >= threshold (default 3) AND no doc/adr/ Write/Edit
#   was performed this session, emit the nudge.
#
# Configuration via env vars:
#   ADR_REMIND_THRESHOLD   (default 3)
#   ADR_REMIND_DISABLE     (set to 1 to disable)
#
# Refs: issue ycpss91255-docker/docker_harness#97.

set -uo pipefail

readonly DEFAULT_THRESHOLD=3
readonly TMP_DIR="${TMPDIR:-/tmp}"

main() {
  local input transcript_path session_id stop_active
  input="$(cat)"

  if [[ "${ADR_REMIND_DISABLE:-0}" == "1" ]]; then
    return 0
  fi

  transcript_path="$(printf '%s' "${input}" | jq -r '.transcript_path // empty' 2>/dev/null)"
  session_id="$(printf '%s' "${input}" | jq -r '.session_id // empty' 2>/dev/null)"
  stop_active="$(printf '%s' "${input}" | jq -r '.stop_hook_active // false' 2>/dev/null)"

  [[ "${stop_active}" == "true" ]] && return 0
  [[ -z "${transcript_path}" || ! -r "${transcript_path}" ]] && return 0

  # rationale_pattern is intentionally broad; precision is achieved
  # by requiring multiple distinct hits (threshold), not single-hit
  # tightness. Case-insensitive via jq's `test("...","i")`.
  local rationale_pattern
  rationale_pattern='trade.?off|alternative|rejected because|why not|going with|decided to|decision to|out of scope because'

  local rationale_hits
  rationale_hits="$(jq -s --arg p "${rationale_pattern}" '
      [
        .[]
        | select(.message?.role == "user" or .message?.role == "assistant")
        | .message.content
        | if type == "string" then
            select(test($p; "i"))
          elif type == "array" then
            .[] | select(.type? == "text") | .text | select(test($p; "i"))
          else
            empty
          end
      ] | length
    ' "${transcript_path}" 2>/dev/null || echo 0)"

  local adr_writes
  adr_writes="$(jq -s '
      [
        .[]
        | select(.message?.role == "assistant")
        | .message.content[]?
        | select(.type == "tool_use" and (.name == "Write" or .name == "Edit" or .name == "MultiEdit"))
        | .input.file_path // ""
        | select(test("/doc/adr/"))
      ] | length
    ' "${transcript_path}" 2>/dev/null || echo 0)"

  [[ "${rationale_hits}" =~ ^[0-9]+$ ]] || rationale_hits=0
  [[ "${adr_writes}" =~ ^[0-9]+$ ]] || adr_writes=0

  local threshold="${ADR_REMIND_THRESHOLD:-${DEFAULT_THRESHOLD}}"
  [[ "${threshold}" =~ ^[0-9]+$ ]] || threshold="${DEFAULT_THRESHOLD}"

  if (( rationale_hits < threshold )); then
    return 0
  fi
  if (( adr_writes > 0 )); then
    return 0
  fi

  # Throttle: once per session per rationale-hit bucket. Bucketing by
  # /5 keeps a single session from firing on every Stop event.
  local signal_hash marker_path
  signal_hash="$(printf '%s' "$((rationale_hits / 5))" | md5sum | cut -d' ' -f1)"
  marker_path="${TMP_DIR}/claude-adr-remind-${session_id:-anon}-${signal_hash}"
  if [[ -f "${marker_path}" ]]; then
    return 0
  fi
  : > "${marker_path}" 2>/dev/null || true

  local msg
  msg="$(printf 'ADR reminder: this session had %s rationale-shaped exchanges (threshold %s) but no doc/adr/ entry was written.\nIf a clear design decision landed (chose X over Y), consider:\n  /adr <slug>\nSee .claude/commands/adr.md for the full workflow. Set ADR_REMIND_DISABLE=1 to silence.' \
    "${rationale_hits}" "${threshold}")"

  # Stop event JSON: top-level systemMessage only (no hookSpecificOutput).
  jq -n --arg m "${msg}" '{systemMessage: $m}'
  return 0
}

main "$@"
