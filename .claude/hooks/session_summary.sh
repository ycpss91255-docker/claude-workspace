#!/usr/bin/env bash
# session_summary.sh — Claude Code Stop hook.
#
# When Claude's response finishes, scan the session transcript and
# append a one-paragraph summary to a per-day rolling log under
# ${TMPDIR:-/tmp}/claude-session-<YYYY-MM-DD>.log. Summary captures:
#   - PR URLs created or merged
#   - Files modified (Edit / Write tool calls)
#   - Bash commands grouped by category (git, gh, docker, make, other)
#
# Non-blocking: produces no systemMessage on normal stop; only emits
# one if the transcript is unreadable or jq errors. The log file is
# the value carrier — the chat is not polluted.
#
# Throttled to once per session per content-hash so a Stop event from
# a re-entry storm (decision=block from a parent hook) does not
# multiply log entries. Configuration env vars:
#   SESSION_SUMMARY_DISABLE  Set to 1 to silence the hook entirely.
#   SESSION_SUMMARY_LOG_DIR  Override log directory (default ${TMPDIR}/).

set -uo pipefail

readonly TMP_DIR="${TMPDIR:-/tmp}"

main() {
  local input transcript_path session_id stop_active
  input="$(cat)"

  if [[ "${SESSION_SUMMARY_DISABLE:-0}" == "1" ]]; then
    return 0
  fi

  transcript_path="$(printf '%s' "${input}" | jq -r '.transcript_path // empty' 2>/dev/null)"
  session_id="$(printf '%s' "${input}" | jq -r '.session_id // empty' 2>/dev/null)"
  stop_active="$(printf '%s' "${input}" | jq -r '.stop_hook_active // false' 2>/dev/null)"

  [[ "${stop_active}" == "true" ]] && return 0
  [[ -z "${transcript_path}" || ! -r "${transcript_path}" ]] && return 0

  local files_modified bash_cmds
  files_modified="$(jq -rs '
      [
        .[]
        | select(.message?.role == "assistant")
        | .message.content[]?
        | select(.type == "tool_use" and (.name == "Edit" or .name == "Write" or .name == "MultiEdit"))
        | .input.file_path // empty
      ] | unique | .[]
    ' "${transcript_path}" 2>/dev/null || true)"

  bash_cmds="$(jq -rs '
      [
        .[]
        | select(.message?.role == "assistant")
        | .message.content[]?
        | select(.type == "tool_use" and .name == "Bash")
        | .input.command // ""
      ] | .[]
    ' "${transcript_path}" 2>/dev/null || true)"

  # Extract PR / issue URLs from bash command strings via grep (jq
  # capture regex is brittle across jq versions; grep is reliable).
  local pr_urls=""
  if [[ -n "${bash_cmds}" ]]; then
    pr_urls="$(printf '%s\n' "${bash_cmds}" \
      | grep -oE 'https://github\.com/[A-Za-z0-9_./-]+/(pull|issues)/[0-9]+' \
      | sort -u || true)"
  fi

  local n_pr=0 n_files=0 n_git=0 n_gh=0 n_docker=0 n_make=0 n_other=0
  if [[ -n "${pr_urls}" ]]; then
    n_pr=$(printf '%s\n' "${pr_urls}" | grep -c -v '^$' || true)
  fi
  if [[ -n "${files_modified}" ]]; then
    n_files=$(printf '%s\n' "${files_modified}" | grep -c -v '^$' || true)
  fi
  if [[ -n "${bash_cmds}" ]]; then
    n_git=$(printf '%s\n' "${bash_cmds}" | grep -cE '(^|[[:space:];&|])git([[:space:]]|$)' || true)
    n_gh=$(printf '%s\n' "${bash_cmds}" | grep -cE '(^|[[:space:];&|])gh([[:space:]]|$)' || true)
    n_docker=$(printf '%s\n' "${bash_cmds}" | grep -cE '(^|[[:space:];&|])docker([[:space:]]|$)' || true)
    n_make=$(printf '%s\n' "${bash_cmds}" | grep -cE '(^|[[:space:];&|])make([[:space:]]|$)' || true)
    n_other=$(printf '%s\n' "${bash_cmds}" \
      | grep -v '^$' \
      | grep -cvE '(^|[[:space:];&|])(git|gh|docker|make)([[:space:]]|$)' || true)
  fi

  [[ "${n_pr}" =~ ^[0-9]+$ ]] || n_pr=0
  [[ "${n_files}" =~ ^[0-9]+$ ]] || n_files=0
  [[ "${n_git}" =~ ^[0-9]+$ ]] || n_git=0
  [[ "${n_gh}" =~ ^[0-9]+$ ]] || n_gh=0
  [[ "${n_docker}" =~ ^[0-9]+$ ]] || n_docker=0
  [[ "${n_make}" =~ ^[0-9]+$ ]] || n_make=0
  [[ "${n_other}" =~ ^[0-9]+$ ]] || n_other=0

  if (( n_pr == 0 && n_files == 0 && n_git + n_gh + n_docker + n_make + n_other == 0 )); then
    return 0
  fi

  local log_dir log_path
  log_dir="${SESSION_SUMMARY_LOG_DIR:-${TMP_DIR}}"
  log_path="${log_dir}/claude-session-$(date +%F).log"

  # Throttle: hash on (session, pr_urls, file count, command totals).
  local sig marker
  sig="$(printf '%s|%s|%s|%d|%d|%d|%d|%d' \
    "${session_id:-anon}" \
    "${pr_urls}" \
    "${files_modified}" \
    "${n_git}" "${n_gh}" "${n_docker}" "${n_make}" "${n_other}" \
    | md5sum | cut -d' ' -f1)"
  marker="${log_dir}/.claude-session-summary-${session_id:-anon}-${sig}"
  if [[ -f "${marker}" ]]; then
    return 0
  fi
  mkdir -p "${log_dir}" 2>/dev/null || true
  : > "${marker}" 2>/dev/null || true

  {
    printf '## %s  session=%s\n' "$(date -u +%FT%TZ)" "${session_id:-anon}"
    if (( n_pr > 0 )); then
      printf 'PR/issue activity (%d):\n' "${n_pr}"
      printf '%s\n' "${pr_urls}" | sed 's/^/  - /'
    fi
    if (( n_files > 0 )); then
      printf 'Files touched (%d):\n' "${n_files}"
      printf '%s\n' "${files_modified}" | sed 's/^/  - /'
    fi
    printf 'Bash command mix: git=%d gh=%d docker=%d make=%d other=%d\n\n' \
      "${n_git}" "${n_gh}" "${n_docker}" "${n_make}" "${n_other}"
  } >> "${log_path}" 2>/dev/null || true

  return 0
}

main "$@"
