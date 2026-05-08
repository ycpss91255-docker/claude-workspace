#!/usr/bin/env bash
# remind_topics_yaml_on_new_repo.sh — Claude Code PreToolUse hook (matcher: Bash)
#
# Fires before any Bash command. When the command creates a new repo
# under the ycpss91255-docker org, remind to add the repo's topic
# entry to ycpss91255-docker/.github topics.yaml. Non-blocking.
#
# Why: The org-wide topic taxonomy lives in .github/topics.yaml, which
# the weekly drift cron (.github/workflows/check-topics.yaml) compares
# against `gh repo list`. A new repo without a yaml entry will fail
# that drift check on Monday morning. Reminding at create time lets
# the maintainer open the .github PR alongside the new repo PR, so
# the taxonomy never lags behind reality.
#
# Trigger pattern: `gh repo create` containing `ycpss91255-docker/`.
# Universal CI fallback (sync-topics.sh roster_drift) still catches
# repos created out of band; this hook is the early reminder for
# in-session creates.

set -uo pipefail

main() {
  local input cmd msg
  input="$(cat)"
  cmd="$(printf '%s' "${input}" | jq -r '.tool_input.command // empty' 2>/dev/null)"

  [[ -z "${cmd}" ]] && return 0

  [[ "${cmd}" =~ gh[[:space:]]+repo[[:space:]]+create ]] || return 0
  [[ "${cmd}" == *ycpss91255-docker/* ]] || return 0

  msg="新 repo 提醒：建完之後也去 ycpss91255-docker/.github 開 PR 把這個 repo 加進 topics.yaml 的 repos.* — 否則週一 drift cron 會 fail，PR 會被擋。允許的 tag 看 .github/topics.yaml 的 allowed.* 區段。"

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
