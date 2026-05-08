#!/usr/bin/env bash
# check_readme_framework.sh - Claude Code PostToolUse hook
#
# Fires on Edit / Write / MultiEdit. When the touched file is a
# downstream repo's English README.md or a doc/README.<lang>.md
# translation, verify it conforms to the canonical framework spec
# derived from template/README.md (the framework reference).
#
# Checks (per file):
#   [1] CI status badge present
#       (regex: actions/workflows/main.yaml/badge.svg)
#   [2] 4-language switch link present
#       (literal: **[English](README.md)**)
#   [3] No `> **TL;?DR**` blockquote (must be `## TL;DR` H2)
#   [4] No stale `template/build.sh` symlink target
#       (must be `template/script/docker/build.sh` since v0.1.0)
#   [5] No `.template_version` reference
#       (version pin moved to `template/.version` since v0.16.0)
#   [6] Smoke Tests section links to TEST.md
#       (regex: \(doc/test/TEST.md\) somewhere in file)
#
# Drift check (only when editing the English README.md, not a
# translation):
#   [drift] each translation file (zh-TW / zh-CN / ja) must (a) exist
#   and (b) contain the CI badge if the English file has it. The
#   second branch nudges fanout-pending state into view.
#
# Scope: only acts on agent/<repo>/, app/<repo>/, env/<repo>/,
# multi_run/. Skips template/ (the framework reference itself),
# archive/, org-profile/.
#
# Non-blocking - always exit 0. Findings emitted as
# {systemMessage, hookSpecificOutput} JSON like every other check_*
# hook in this repo.

set -uo pipefail

is_downstream_readme() {
  local path="$1"
  case "${path}" in
    */README.md|*/doc/README.zh-TW.md|*/doc/README.zh-CN.md|*/doc/README.ja.md) ;;
    *) return 1 ;;
  esac

  local repo_root
  case "${path}" in
    */doc/README.*) repo_root="${path%/doc/README.*}" ;;
    *) repo_root="${path%/README.md}" ;;
  esac

  case "${repo_root}" in
    */template|*/archive/*|*/org-profile) return 1 ;;
  esac

  local short parent
  short="$(basename "${repo_root}")"
  parent="$(basename "$(dirname "${repo_root}")")"
  case "${parent}/${short}" in
    agent/*|app/*|env/*) ;;
    */multi_run) ;;
    *) return 1 ;;
  esac

  printf '%s' "${repo_root}"
  return 0
}

check_one() {
  local file="$1"
  local lang_label="$2"
  local prefix
  if [[ -n "${lang_label}" ]]; then
    prefix="[${lang_label}] "
  else
    prefix=""
  fi

  local findings=""
  [[ ! -f "${file}" ]] && return 0
  local contents
  contents="$(cat "${file}" 2>/dev/null || true)"

  if ! grep -q 'actions/workflows/main.yaml/badge.svg' <<< "${contents}"; then
    findings+="  ${prefix}[1] missing CI badge: expected ![CI](.../actions/workflows/main.yaml/badge.svg)"$'\n'
  fi

  if ! grep -q '\*\*\[English\](README.md)\*\*' <<< "${contents}"; then
    findings+="  ${prefix}[2] missing 4-language switch link: '**[English](README.md)** | **[繁體中文](...)** | ...'"$'\n'
  fi

  if grep -qE '^>[[:space:]]*\*\*TL;?DR\*\*' <<< "${contents}"; then
    findings+="  ${prefix}[3] TL;DR is a blockquote; framework expects '## TL;DR' H2"$'\n'
  fi

  if grep -qE 'template/build\.sh[[:space:]]+#' <<< "${contents}"; then
    findings+="  ${prefix}[4] stale path 'template/build.sh' - should be 'template/script/docker/build.sh'"$'\n'
  fi

  if grep -q '\.template_version' <<< "${contents}"; then
    findings+="  ${prefix}[5] obsolete '.template_version' reference - version pin lives in 'template/.version' since template v0.16.0"$'\n'
  fi

  if ! grep -q '(doc/test/TEST.md)' <<< "${contents}"; then
    findings+="  ${prefix}[6] missing 'See [TEST.md](doc/test/TEST.md) for details.' under '## Smoke Tests'"$'\n'
  fi

  printf '%s' "${findings}"
}

main() {
  local input file_path repo_root
  input="$(cat)"
  file_path="$(printf '%s' "${input}" | jq -r '
    .tool_input.file_path
    // .tool_response.filePath
    // empty
  ' 2>/dev/null)"

  [[ -z "${file_path}" ]] && return 0

  repo_root="$(is_downstream_readme "${file_path}")" || return 0

  local all_findings=""
  local lang_label=""

  case "${file_path}" in
    */doc/README.zh-TW.md) lang_label="zh-TW" ;;
    */doc/README.zh-CN.md) lang_label="zh-CN" ;;
    */doc/README.ja.md) lang_label="ja" ;;
    *) lang_label="" ;;
  esac

  all_findings+="$(check_one "${file_path}" "${lang_label}")"

  if [[ -z "${lang_label}" ]]; then
    local lang trans
    for lang in zh-TW zh-CN ja; do
      trans="${repo_root}/doc/README.${lang}.md"
      if [[ ! -f "${trans}" ]]; then
        all_findings+="  [drift] missing translation: doc/README.${lang}.md"$'\n'
        continue
      fi
      if grep -q 'actions/workflows/main.yaml/badge.svg' "${file_path}" \
         && ! grep -q 'actions/workflows/main.yaml/badge.svg' "${trans}"; then
        all_findings+="  [drift] doc/README.${lang}.md has not adopted the framework yet (no CI badge while English README has one)"$'\n'
      fi
    done
  fi

  all_findings="${all_findings%$'\n'}"

  if [[ -z "${all_findings}" ]]; then
    return 0
  fi

  local msg
  msg="$(printf 'README framework drift in %s:\n%s\n\nReference: ros1_bridge PR #63 applied this framework first.' "${repo_root}" "${all_findings}")"
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
