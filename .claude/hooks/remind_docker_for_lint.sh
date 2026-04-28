#!/usr/bin/env bash
# remind_docker_for_lint.sh — Claude Code PreToolUse hook (matcher: Bash)
#
# Fires before any Bash command. When the command directly invokes a
# lint / test tool (bats / shellcheck / hadolint / kcov) outside of
# Docker / make / build.sh wrappers, remind that 驗證一律走 Docker.
# Non-blocking (always exit 0).
#
# Why: CLAUDE.md「驗證一律走 Docker」明文禁止本機直接呼叫 — 本機
# bats-mock / bats-support / shellcheck 版本可能與 CI 不同,結果會
# 不一致。CI reusable workflow 也是透過同一組 Docker image 執行。
#
# Trigger pattern: command 含 standalone tool word（line start 或
# `;`/`&&`/`||`/`|` 之後),且 command 不在 wrapper 內
# (`docker run`/`docker exec`/`docker compose`/`make -f Makefile.ci`/
# `./build.sh`)。

set -uo pipefail

main() {
  local input cmd msg
  input="$(cat)"
  cmd="$(printf '%s' "${input}" | jq -r '.tool_input.command // empty' 2>/dev/null)"

  [[ -z "${cmd}" ]] && return 0

  case "${cmd}" in
    *"docker run"*|*"docker exec"*|*"docker compose"*) return 0 ;;
    *"make -f Makefile.ci"*|*"./build.sh"*) return 0 ;;
  esac

  [[ "${cmd}" =~ (^|[\;\&\|][[:space:]]*)(bats|shellcheck|hadolint|kcov)([[:space:]]|$) ]] || return 0

  local tool="${BASH_REMATCH[2]}"
  msg="$(printf '驗證一律走 Docker 提醒：偵測到直接跑 %s,結果可能與 CI 不一致(本機 bats-mock / shellcheck 版本可能不同)。改用 ./build.sh test 或 make -f Makefile.ci test/lint。' "${tool}")"

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
