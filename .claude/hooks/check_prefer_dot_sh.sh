#!/usr/bin/env bash
# check_prefer_dot_sh.sh — Claude Code PreToolUse hook (matcher: Bash)
#
# Fires before any Bash command. When the command is a state-changing
# `docker <subcommand>` (build / run / exec / stop) or
# `docker compose <up|down|build|run|exec>` AND cwd has the matching
# `.sh` wrapper, BLOCKS with a message pointing at the wrapper. When
# the wrapper is missing, forces prompt (permissionDecision="ask")
# rather than letting the broader `Bash(docker:*)` allow rule pass.
#
# Why: per CLAUDE.md「常用指令」與 user feedback,build/run/exec/stop 一律
# 走 .sh wrapper（會帶 setup.sh 自動更新 .env / compose.yaml + 語言環境
# + GPU/GUI 偵測）。直接跑 docker 跳過所有 wrapper 邏輯,容易產生與 wrapper
# 不一致的容器狀態。
#
# Subcommand → wrapper map:
#   docker build         → ./build.sh
#   docker run           → ./run.sh
#   docker exec          → ./exec.sh
#   docker stop          → ./stop.sh
#   docker compose up    → ./run.sh
#   docker compose down  → ./stop.sh
#   docker compose build → ./build.sh
#   docker compose run   → ./run.sh
#   docker compose exec  → ./exec.sh
#
# Out of scope (silent — fall through to other rules):
#   - Read-only subcommands (ps / images / version / inspect / logs / pull / ...)
#   - Destructive ones already in `permissions.ask` (rm / rmi / kill / push / ...)
#   - `make`-driven docker calls (make's subprocess; not visible to Claude)

set -uo pipefail

main() {
  local input cmd cwd subcmd wrapper msg stripped
  input="$(cat)"
  cmd="$(printf '%s' "${input}" | jq -r '.tool_input.command // empty' 2>/dev/null)"
  cwd="$(printf '%s' "${input}" | jq -r '.cwd // empty' 2>/dev/null)"
  [[ -z "${cwd}" ]] && cwd="${PWD}"
  [[ -z "${cmd}" ]] && return 0

  # Strip leading env-prefix(es): `VAR=value [VAR=value ...] cmd ...`.
  stripped="${cmd}"
  while [[ "${stripped}" =~ ^[A-Z_][A-Z0-9_]*=[^[:space:]]+[[:space:]]+ ]]; do
    stripped="${stripped#"${BASH_REMATCH[0]}"}"
  done

  subcmd=""
  wrapper=""
  if [[ "${stripped}" =~ ^docker[[:space:]]+(build|run|exec|stop)([[:space:]]|$) ]]; then
    subcmd="docker ${BASH_REMATCH[1]}"
    case "${BASH_REMATCH[1]}" in
      build) wrapper="build.sh" ;;
      run)   wrapper="run.sh" ;;
      exec)  wrapper="exec.sh" ;;
      stop)  wrapper="stop.sh" ;;
    esac
  elif [[ "${stripped}" =~ ^docker[[:space:]]+compose[[:space:]]+(up|down|build|run|exec)([[:space:]]|$) ]]; then
    subcmd="docker compose ${BASH_REMATCH[1]}"
    case "${BASH_REMATCH[1]}" in
      up|run) wrapper="run.sh" ;;
      down)   wrapper="stop.sh" ;;
      build)  wrapper="build.sh" ;;
      exec)   wrapper="exec.sh" ;;
    esac
  else
    return 0
  fi

  local wrapper_path="${cwd}/${wrapper}"
  if [[ -e "${wrapper_path}" ]]; then
    msg="$(printf '%s 改用 ./%s 提醒：當前 cwd 有 ./%s,優先呼叫 wrapper(會帶 setup.sh 自動更新 .env / compose.yaml + 語言環境 + GPU/GUI 偵測)。直接跑 docker 會繞過這層,容易產生與 wrapper 不一致的容器狀態。' \
      "${subcmd}" "${wrapper}" "${wrapper}")"
    jq -n --arg m "${msg}" '{
      systemMessage: $m,
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $m
      }
    }'
    return 0
  fi

  msg="$(printf '%s 無對應 ./%s wrapper(cwd=%s):直接跑 docker 確定要這樣?正常流程一律透過 ./build.sh / ./run.sh / ./exec.sh / ./stop.sh wrapper。' \
    "${subcmd}" "${wrapper}" "${cwd}")"
  jq -n --arg m "${msg}" '{
    systemMessage: $m,
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: $m
    }
  }'
}

main "$@"
