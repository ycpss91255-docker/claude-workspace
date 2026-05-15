#!/usr/bin/env bash
# check_git_push_diff.sh — Claude Code PreToolUse hook (Bash).
#
# Inspect the diff a `git push` is about to upload. Surface:
#   - Large diff (> CHECK_PUSH_FILE_THRESHOLD files, default 30)
#   - Binary blobs (typical noise: lock files, images, build artifacts
#     that should not have been committed)
#   - Generated-file paths (dist/, build/, _pb2.py, .min.js, lockfiles)
#
# Non-blocking — emits systemMessage and exits 0 so the push proceeds.
# Designed to nudge a quick "is this really what I want to push?" check.
#
# Triggers on Bash commands matching `git push` (with optional flags /
# `git -C <path> push`). Skipped on: `--dry-run`, branch-delete syntax
# (`git push <remote> :branch`), `--tags`-only (no diff).
#
# Configuration env vars:
#   CHECK_PUSH_FILE_THRESHOLD  Warn when changed-file count exceeds this
#                              (default 30).
#   CHECK_PUSH_DISABLE         Set to 1 to silence the hook entirely.

set -uo pipefail

readonly DEFAULT_FILE_THRESHOLD=30
readonly GENERATED_GLOBS=(
  '*/dist/*'
  '*/build/*'
  '*/node_modules/*'
  '*_pb2.py'
  '*.min.js'
  '*.min.css'
  'package-lock.json'
  'yarn.lock'
  'poetry.lock'
  'pnpm-lock.yaml'
  'Cargo.lock'
)

emit_message() {
  local msg="$1"
  jq -n --arg m "${msg}" '{systemMessage: $m}'
}

is_push_command() {
  local cmd="$1"
  [[ "${cmd}" =~ (^|[[:space:];&|])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+push([[:space:]]|$) ]]
}

is_skipped_form() {
  local cmd="$1"
  [[ "${cmd}" == *--dry-run* ]] && return 0
  # `git push origin :branch` deletes the remote branch — no diff to inspect.
  if [[ "${cmd}" =~ git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+push[[:space:]]+[^[:space:]]+[[:space:]]+:[^[:space:]]+ ]]; then
    return 0
  fi
  # `git push --tags` (only tags) — assume the tag drift hook handles it.
  if [[ "${cmd}" =~ git[[:space:]]+push([[:space:]]+--[^[:space:]]+)*[[:space:]]+--tags([[:space:]]|$) ]] \
     && [[ "${cmd}" != *refs/heads/* ]]; then
    return 0
  fi
  return 1
}

extract_repo_path() {
  local cmd="$1"
  if [[ "${cmd}" =~ git[[:space:]]+-C[[:space:]]+([^[:space:]]+) ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  else
    printf '.'
  fi
}

is_force_with_lease() {
  local cmd="$1"
  [[ "${cmd}" == *--force-with-lease* ]]
}

main() {
  local input cmd
  input="$(cat)"

  if [[ "${CHECK_PUSH_DISABLE:-0}" == "1" ]]; then
    return 0
  fi

  cmd="$(printf '%s' "${input}" | jq -r '.tool_input.command // empty' 2>/dev/null)"
  [[ -z "${cmd}" ]] && return 0

  is_push_command "${cmd}" || return 0
  is_skipped_form "${cmd}" && return 0

  local repo_path branch upstream
  repo_path="$(extract_repo_path "${cmd}")"
  branch="$(git -C "${repo_path}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
  [[ -z "${branch}" || "${branch}" == "HEAD" ]] && return 0

  upstream="$(git -C "${repo_path}" rev-parse --abbrev-ref --symbolic-full-name "@{u}" 2>/dev/null || echo "")"

  local stat_output threshold
  threshold="${CHECK_PUSH_FILE_THRESHOLD:-${DEFAULT_FILE_THRESHOLD}}"
  [[ "${threshold}" =~ ^[0-9]+$ ]] || threshold="${DEFAULT_FILE_THRESHOLD}"

  if [[ -n "${upstream}" ]]; then
    stat_output="$(git -C "${repo_path}" diff --name-only "${upstream}"..HEAD 2>/dev/null || true)"
  else
    # No upstream yet — first push. Diff against the merge-base with main.
    local base
    base="$(git -C "${repo_path}" merge-base HEAD origin/main 2>/dev/null || echo "")"
    if [[ -n "${base}" ]]; then
      stat_output="$(git -C "${repo_path}" diff --name-only "${base}"..HEAD 2>/dev/null || true)"
    else
      return 0
    fi
  fi

  [[ -z "${stat_output}" ]] && return 0

  local file_count
  file_count="$(printf '%s\n' "${stat_output}" | grep -c -v '^$' || true)"
  [[ "${file_count}" =~ ^[0-9]+$ ]] || file_count=0

  local -a generated_hits=()
  local -a binary_hits=()
  while IFS= read -r f; do
    [[ -z "${f}" ]] && continue
    local g
    for g in "${GENERATED_GLOBS[@]}"; do
      # SC2254: glob expansion in case pattern is intentional -- the
      # GENERATED_GLOBS entries ARE the patterns we want to match against.
      # shellcheck disable=SC2254
      case "/${f}" in
        ${g}|/${g}) generated_hits+=("${f}"); break ;;
      esac
    done
    local abs="${repo_path}/${f}"
    if [[ -f "${abs}" ]] && file --mime "${abs}" 2>/dev/null | grep -qE 'charset=binary'; then
      binary_hits+=("${f}")
    fi
  done <<< "${stat_output}"

  local -a flags=()
  if (( file_count > threshold )); then
    if is_force_with_lease "${cmd}"; then
      flags+=("large diff (${file_count} files > ${threshold}) -- --force-with-lease present, likely a rebase")
    else
      flags+=("large diff (${file_count} files > ${threshold}) -- unusually broad push")
    fi
  fi
  if (( ${#binary_hits[@]} > 0 )); then
    local sample
    sample="$(printf '%s, ' "${binary_hits[@]:0:3}")"
    flags+=("binary blob(s): ${sample%, } (${#binary_hits[@]} total) -- check whether they belong in version control")
  fi
  if (( ${#generated_hits[@]} > 0 )); then
    local sample
    sample="$(printf '%s, ' "${generated_hits[@]:0:3}")"
    flags+=("generated-path hit(s): ${sample%, } (${#generated_hits[@]} total) -- check .gitignore")
  fi

  (( ${#flags[@]} == 0 )) && return 0

  local body=""
  local item
  for item in "${flags[@]}"; do
    body+="
  - ${item}"
  done

  local msg
  msg="$(printf 'Pre-push review for %s -> %s:%s\n\nReview the diff before pushing if any of these look off. Set CHECK_PUSH_DISABLE=1 to silence.' \
    "${branch}" "${upstream:-(no upstream)}" "${body}")"

  emit_message "${msg}"
  return 0
}

main "$@"
