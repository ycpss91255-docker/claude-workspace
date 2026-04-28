#!/usr/bin/env bash
# remind_tdd_categories.sh — Claude Code PostToolUse hook
#
# Fires on Edit / Write / MultiEdit. When the touched file falls into a
# TDD-relevant category (shell logic / entrypoint / Dockerfile / compose /
# CI workflow / lint rules), emit a JSON systemMessage reminding Claude
# which of the 4 test categories (smoke / unit / integration / lint) the
# change is expected to cover. Non-blocking — exit 0.
#
# Mapping is intentionally a soft reminder, not enforcement: the hook does
# NOT verify that tests were actually written. It just nags by re-injecting
# the relevant row of the 變更類型 → 測試類別 table from CLAUDE.md, so the
# rule stays in context the moment a relevant file is touched.
#
# Skip list:
#   - .md / .bats / TEST.md — the test or doc itself; user is doing the
#     reminding side already
#   - .claude/ internals — avoid firing when editing this hook itself
#   - .git / node_modules / coverage / cache — irrelevant
#   - generated artifacts (.env, derived compose.yaml in repo roots) are
#     not skipped here — Claude rarely edits them by hand; if it does,
#     a reminder is still cheap

set -uo pipefail

main() {
  local input file_path category reminder
  input="$(cat)"
  file_path="$(printf '%s' "${input}" | jq -r '
    .tool_input.file_path
    // .tool_response.filePath
    // empty
  ' 2>/dev/null)"

  [[ -z "${file_path}" || ! -f "${file_path}" ]] && return 0

  case "${file_path}" in
    */.git/*|*/node_modules/*|*/coverage/*|*/.cache/*) return 0 ;;
    */.claude/*) return 0 ;;
    *.md|*.bats) return 0 ;;
  esac

  category=""
  reminder=""

  case "${file_path}" in
    */entrypoint.sh)
      category="entrypoint / 容器啟動行為"
      reminder="Smoke test 必須（容器起來後核心 path 跑得過）+ Lint 必須（ShellCheck）；視函式拆分補 Unit、視 multi-container 補 Integration"
      ;;
    *.hadolint.yaml|*/.shellcheckrc|*.shellcheckrc)
      category="lint 規則調整"
      reminder="Lint 必須：跑一次全套（./build.sh test 或 make -f Makefile.ci lint）確認既有檔案沒有新 violation；Smoke / Unit / Integration 通常 N/A"
      ;;
    */.github/workflows/*.yaml|*/.github/workflows/*.yml)
      category="CI workflow / reusable workflow"
      reminder="Integration 必須（PR 跑一次驗證新 workflow 真的觸發）；視觸發點補 Smoke、Lint（actionlint 若有）"
      ;;
    */compose.yaml)
      category="compose / multi-container 行為"
      reminder="Integration 必須（multi-container 協同行為）；視單容器影響補 Smoke；Unit N/A"
      ;;
    */Dockerfile|*/Dockerfile.*|*Dockerfile)
      category="Dockerfile（stage / COPY / ENV / ARG 等）"
      reminder="Smoke test 必須（container 起得來、核心指令可用）+ Lint 必須（Hadolint）；Unit 通常 N/A；視 build flow 補 Integration"
      ;;
    *.sh)
      category="shell 函式 / 腳本邏輯"
      reminder="Unit test 必須（隔離函式邏輯，bats-mock）+ Lint 必須（ShellCheck）；視 path 影響補 Smoke、視流程影響補 Integration"
      ;;
  esac

  [[ -z "${category}" ]] && return 0

  local msg
  msg="$(printf 'TDD reminder — 剛動到 %s（類別：%s）\n%s\n對照表：CLAUDE.md「測試分類（TDD 必須涵蓋的 4 個面向）」' \
    "${file_path}" "${category}" "${reminder}")"

  jq -n --arg m "${msg}" '{
    systemMessage: $m,
    hookSpecificOutput: {
      hookEventName: "PostToolUse",
      additionalContext: $m
    }
  }'

  return 0
}

main "$@"
