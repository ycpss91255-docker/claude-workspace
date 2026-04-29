#!/usr/bin/env bash
# remind_readme_on_core_script.sh — Claude Code PreToolUse hook (matcher: Bash)
#
# Fires before any Bash command. When the command is `git commit`, check
# whether template's core install/upgrade scripts are staged without a
# corresponding update to any README. On drift, emit an advisory JSON
# systemMessage. Non-blocking — exit 0.
#
# Why: README's "Upgrading" / "Configuration" sections describe behavior
# implemented in upgrade.sh / init.sh / setup.sh, but no mechanical link
# binds them. Past instances: implicit-downgrade refusal, _warn_config_drift,
# config/ preservation — all shipped in upgrade.sh without README mention.
# Unlike CHANGELOG, the gap is semantic (what gets preserved vs regenerated)
# and cannot be auto-derived; this hook just nudges.
#
# Trigger:
#   - `git commit` (not amend / allow-empty)
#   - staged paths match core scripts (template/upgrade.sh, template/init.sh,
#     template/script/docker/setup.sh, or the same paths from a
#     template-internal session without the `template/` prefix)
#   - no README*.md staged in the same commit

set -uo pipefail

main() {
  local input cmd cwd work_dir repo_root staged
  local has_core=0 has_readme=0
  local core_re='^(template/)?(upgrade|init|upgrade-check)\.sh$|^(template/)?script/docker/setup\.sh$'
  local readme_re='(^|/)README(\.[A-Za-z]{2,3}(-[A-Z]{2,3})?)?\.md$'

  input="$(cat)"
  cmd="$(printf '%s' "${input}" | jq -r '.tool_input.command // empty' 2>/dev/null)"
  cwd="$(printf '%s' "${input}" | jq -r '.cwd // empty' 2>/dev/null)"
  [[ -z "${cwd}" ]] && cwd="${PWD}"

  [[ -z "${cmd}" ]] && return 0

  [[ "${cmd}" =~ git[[:space:]]+(-[A-Za-z]+[[:space:]]+[^[:space:]]+[[:space:]]+)*commit([[:space:]]|$) ]] || return 0
  [[ "${cmd}" == *"--amend"* ]] && return 0
  [[ "${cmd}" == *"--allow-empty"* ]] && return 0

  work_dir=""
  if [[ "${cmd}" =~ git[[:space:]]+-C[[:space:]]+([^[:space:]]+) ]]; then
    work_dir="${BASH_REMATCH[1]}"
  elif [[ "${cmd}" =~ cd[[:space:]]+([^[:space:]\&\;]+)[[:space:]]*\&\& ]]; then
    work_dir="${BASH_REMATCH[1]}"
  fi
  [[ -z "${work_dir}" ]] && work_dir="${cwd}"
  [[ "${work_dir}" != /* ]] && work_dir="${cwd}/${work_dir}"

  repo_root="$(git -C "${work_dir}" rev-parse --show-toplevel 2>/dev/null)"
  [[ -z "${repo_root}" ]] && return 0

  staged="$(git -C "${repo_root}" diff --cached --name-only 2>/dev/null)"
  [[ -z "${staged}" ]] && return 0

  while IFS= read -r f; do
    [[ -z "${f}" ]] && continue
    if [[ "${f}" =~ ${core_re} ]]; then
      has_core=1
    fi
    if [[ "${f}" =~ ${readme_re} ]]; then
      has_readme=1
    fi
  done <<< "${staged}"

  (( has_core == 1 && has_readme == 0 )) || return 0

  local msg
  msg="$(printf 'README drift reminder in %s:\n  staged template core script(s) (upgrade.sh / init.sh / setup.sh) but no README*.md is in the commit.\n  README "Upgrading" / "Configuration" sections often need to track behavior changes here (e.g. preserved vs regenerated files, safety guards, implicit-downgrade refusal).\n  This is advisory — if your change is internal-only (refactor, lint fix), ignore. Run /doc-sync if unsure.\n  Staged files:\n%s' \
    "${repo_root}" "$(printf '%s' "${staged}" | sed 's/^/    /')")"

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
