#!/usr/bin/env bash
# remind_subtree_init.sh — Claude Code PreToolUse hook (matcher: Bash)
#
# Fires before any Bash command. When the command pulls the `.base/`
# git subtree (`git subtree pull ... --prefix=.base ...`, or the legacy
# `... template ...` form), remind to run `./.base/init.sh` afterwards
# to resync root symlinks. Non-blocking.
#
# Why: memory `feedback_template_subtree_upgrade.md` 記載過去踩坑 —
# subtree pull 不會自動更新 root symlinks（build.sh / run.sh / exec.sh
# 等），漏跑 init.sh 會導致 root 指向舊 target；首選改用
# `make -f Makefile.ci upgrade`，內部已包含 init.sh resync。
#
# Trigger pattern: 出現 `git subtree pull` 且 command 含 `.base` 或
# 舊名 `template`（為相容仍保留）。不擋 make-driven upgrade
# (其本身就是包好的),只 nag 直接 subtree pull。

set -uo pipefail

main() {
  local input cmd msg
  input="$(cat)"
  cmd="$(printf '%s' "${input}" | jq -r '.tool_input.command // empty' 2>/dev/null)"

  [[ -z "${cmd}" ]] && return 0

  [[ "${cmd}" =~ git[[:space:]]+subtree[[:space:]]+pull ]] || return 0
  [[ "${cmd}" == *template* || "${cmd}" == *.base* ]] || return 0

  msg="Subtree pull 提醒：拉完一定要跑 ./.base/init.sh 重整 root symlinks（build.sh / run.sh / exec.sh / stop.sh / Makefile / .hadolint.yaml）。或直接改用 make -f Makefile.ci upgrade [VERSION=vX.Y.Z]（內部已含 init.sh resync + main.yaml @tag sed，較不易漏）。"

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
