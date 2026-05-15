#!/usr/bin/env bash
# remind_make_first_upgrade.sh — Claude Code PreToolUse hook (matcher: Bash)
#
# Fires before any Bash command. When the command directly invokes
# `.base/upgrade.sh` (or `./.base/upgrade.sh` / absolute path variant)
# and the repo root has a `Makefile.ci` with an `upgrade` target, emit a
# reminder pointing at `make -f Makefile.ci upgrade` as the preferred entry.
# Non-blocking — exit 0.
#
# Why: CLAUDE.md「常用指令 → base」與「base subtree 更新流程」
# 規定升級一律 make 優先,`./.base/upgrade.sh` 留作 fallback,只在 make
# 不可用或 target 出問題時才用。這層提醒避免 agent 記憶體裡只剩
# upgrade.sh、跳過 make wrapper 的 init.sh resync / main.yaml @tag rewrite
# 自動處理。
#
# Detection:
#   1. Match `.base/upgrade.sh` invocations (`./.base/upgrade.sh`,
#      `.base/upgrade.sh`, absolute path).
#   2. Resolve work dir.
#   3. Skip if no `Makefile.ci` at repo root (no make wrapper available,
#      so .sh is the right choice).
#   4. Skip if `Makefile.ci` does not declare `upgrade:` target.
#   5. Otherwise emit reminder.

set -uo pipefail

main() {
  local input cmd cwd work_dir repo_root makefile msg version_arg
  input="$(cat)"
  cmd="$(printf '%s' "${input}" | jq -r '.tool_input.command // empty' 2>/dev/null)"
  cwd="$(printf '%s' "${input}" | jq -r '.cwd // empty' 2>/dev/null)"
  [[ -z "${cwd}" ]] && cwd="${PWD}"

  [[ -z "${cmd}" ]] && return 0

  # Match upgrade.sh invocations. Allow `./.base/upgrade.sh`,
  # `.base/upgrade.sh`, or absolute `/...../.base/upgrade.sh`.
  [[ "${cmd}" =~ (^|[[:space:]\;\&\|])(\./)?(.*/)?.base/upgrade\.sh([[:space:]]|$) ]] || return 0

  # Resolve work dir.
  work_dir=""
  if [[ "${cmd}" =~ cd[[:space:]]+([^[:space:]\&\;]+)[[:space:]]*\&\& ]]; then
    work_dir="${BASH_REMATCH[1]}"
  fi
  [[ -z "${work_dir}" ]] && work_dir="${cwd}"
  [[ "${work_dir}" != /* ]] && work_dir="${cwd}/${work_dir}"

  repo_root="$(git -C "${work_dir}" rev-parse --show-toplevel 2>/dev/null)"
  [[ -z "${repo_root}" ]] && repo_root="${work_dir}"

  makefile="${repo_root}/Makefile.ci"
  [[ -f "${makefile}" ]] || return 0
  grep -qE '^upgrade:' "${makefile}" 2>/dev/null || return 0

  # Try to extract version arg if present (e.g. `./.base/upgrade.sh v0.18.2`).
  version_arg=""
  if [[ "${cmd}" =~ .base/upgrade\.sh[[:space:]]+(v[0-9][0-9.]*(-[A-Za-z0-9.]+)?) ]]; then
    version_arg=" VERSION=${BASH_REMATCH[1]}"
  fi

  msg="$(printf 'base subtree upgrade 提醒：偵測到直接跑 ./.base/upgrade.sh,優先改用 make wrapper:\n  make -f Makefile.ci upgrade%s\nmake target 內部會呼叫同一支 upgrade.sh,但會幫你跑 init.sh resync + main.yaml @tag sed,降低漏步的機率。只在 make 不可用或 target 出問題時才 fallback 直接跑 .sh。' \
    "${version_arg}")"

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
