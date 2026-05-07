#!/usr/bin/env bash
#
# batch-gitignore-add-line.sh — open one chore PR per downstream repo
# to APPEND a given line to each repo's `.gitignore` if not already
# present. Idempotent — repos that already have the line are skipped.
#
# Generic sister of `batch-gitignore-fix.sh` (which replaced
# `.claude/` with `.claude` one-shot). Designed for any future
# "add this line to all 18 .gitignore files" need, e.g. ignoring
# `<repo>/CLAUDE.md` symlinks alongside the existing `.claude` ignore.
#
# Usage:
#   batch-gitignore-add-line.sh --line "<text>" --why-file <path> [options]
#   batch-gitignore-add-line.sh --line "<text>" --why "<text>"   [options]
#
# Options:
#   --line "<text>"       Line to append to .gitignore (required, exact match).
#   --why-file <path>     PR body Why-section content (required, or use --why).
#   --why "<text>"        Inline alternative to --why-file.
#   --dry-run             Print what would be done; skip mutations.
#   --only <r1,r2,...>    Limit to listed repos.
#   --skip <r1,r2,...>    Exclude listed repos.
#   --continue-on-error   Keep going past failures; print summary at end.
#   -h, --help            Show this help.
#
# Designed to be run from the main session (not a subagent) because
# subagent sandbox blocks `git push`.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
readonly SCRIPT_DIR
readonly ORG="ycpss91255-docker"

readonly DEFAULT_REPOS=(
  agent/ai_agent
  agent/claude_code
  agent/codex_cli
  agent/gemini_cli
  app/realsense_humble
  app/realsense_noetic
  app/ros1_bridge
  app/sick_humble
  app/sick_noetic
  app/urg_node_humble
  app/urg_node_noetic
  env/ros2_distro
  env/ros_distro
  template
)

usage() {
  sed -n '/^# Usage:/,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
}

err() {
  printf '[batch-gitignore-add-line] ERROR: %s\n' "$*" >&2
}

info() {
  printf '[batch-gitignore-add-line] %s\n' "$*"
}

# _line_pattern_for_grep <line> — escape regex metacharacters so the
# line can be searched literally with `grep -qE`.
_line_pattern_for_grep() {
  printf '%s' "$1" | sed 's|[][\\.^$*?+(){}|]|\\&|g'
}

main() {
  local line=""
  local why_file=""
  local why_text=""
  local dry_run=0
  local continue_on_error=0
  local only_csv=""
  local skip_csv=""

  while (( $# > 0 )); do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --line) line="$2"; shift 2 ;;
      --why-file) why_file="$2"; shift 2 ;;
      --why) why_text="$2"; shift 2 ;;
      --dry-run) dry_run=1; shift ;;
      --continue-on-error) continue_on_error=1; shift ;;
      --only) only_csv="$2"; shift 2 ;;
      --skip) skip_csv="$2"; shift 2 ;;
      *) err "unknown arg: $1"; usage; exit 2 ;;
    esac
  done

  if [[ -z "${line}" ]]; then
    err "--line is required"
    exit 2
  fi
  if [[ -z "${why_file}" && -z "${why_text}" ]]; then
    err "must provide --why-file <path> or --why \"<text>\""
    exit 2
  fi
  if [[ -n "${why_file}" && ! -r "${why_file}" ]]; then
    err "why-file not readable: ${why_file}"
    exit 2
  fi

  local why
  if [[ -n "${why_file}" ]]; then
    why="$(cat -- "${why_file}")"
  else
    why="${why_text}"
  fi

  local repos=()
  if [[ -n "${only_csv}" ]]; then
    IFS=',' read -ra repos <<< "${only_csv}"
  else
    repos=("${DEFAULT_REPOS[@]}")
  fi

  if [[ -n "${skip_csv}" ]]; then
    local skip_set=" ${skip_csv//,/ } "
    local kept=()
    local r
    for r in "${repos[@]}"; do
      if [[ "${skip_set}" != *" ${r} "* ]]; then
        kept+=("${r}")
      fi
    done
    repos=("${kept[@]}")
  fi

  # Lazy: only resolve workspace root if we mutate. `--help` /
  # `--dry-run` work outside a git checkout (e.g. bats test container).
  local root=""
  if (( ! dry_run )); then
    root="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel)"
    readonly root
  fi

  local branch
  branch="chore/gitignore-add-${line//[^a-zA-Z0-9._-]/-}"
  local title
  title="chore: gitignore add \`${line}\`"

  info "branch=${branch} dry_run=${dry_run} repos=${#repos[@]} line=${line}"

  local failed=()
  local skipped=()
  local opened=()

  local repo
  for repo in "${repos[@]}"; do
    local reponame="${repo##*/}"
    local url="https://github.com/${ORG}/${reponame}.git"
    info "=== [${repo}] ==="

    if (( dry_run )); then
      info "[${repo}] dry-run: would fetch ${url} main, create ${branch}, append \"${line}\" to .gitignore, open PR"
      continue
    fi

    if [[ ! -d "${root}/${repo}" ]]; then
      err "[${repo}] missing local dir; skipping"
      skipped+=("${repo} (missing)")
      continue
    fi
    if [[ ! -f "${root}/${repo}/.gitignore" ]]; then
      info "[${repo}] no .gitignore; skipping"
      skipped+=("${repo} (no .gitignore)")
      continue
    fi

    if add_one "${root}/${repo}" "${url}" "${reponame}" "${line}" "${branch}" "${title}" "${why}"; then
      opened+=("${repo}")
    else
      local rc=$?
      if (( rc == 100 )); then
        skipped+=("${repo} (already has line)")
      else
        failed+=("${repo}")
        if (( ! continue_on_error )); then
          err "[${repo}] failed (rc=${rc}); aborting (use --continue-on-error to keep going)"
          break
        fi
      fi
    fi
  done

  echo
  info "summary: opened=${#opened[@]} skipped=${#skipped[@]} failed=${#failed[@]}"
  if (( ${#opened[@]} )); then
    printf '  opened:  %s\n' "${opened[@]}"
  fi
  if (( ${#skipped[@]} )); then
    printf '  skipped: %s\n' "${skipped[@]}"
  fi
  if (( ${#failed[@]} )); then
    printf '  failed:  %s\n' "${failed[@]}"
    exit 1
  fi
}

add_one() {
  local dir="$1"
  local url="$2"
  local reponame="$3"
  local line="$4"
  local branch="$5"
  local title="$6"
  local why="$7"

  cd "${dir}"

  git fetch "${url}" main || return 1
  git checkout -B main FETCH_HEAD || return 1

  # Idempotency: skip if .gitignore already has the exact line.
  local pattern
  pattern="$(_line_pattern_for_grep "${line}")"
  if grep -qE "^${pattern}\$" .gitignore; then
    info "[${reponame}] .gitignore already contains \`${line}\`; skipping"
    return 100
  fi

  git checkout -B "${branch}" || return 1

  printf '%s\n' "${line}" >> .gitignore

  if git diff --quiet; then
    info "[${reponame}] append produced no change; skipping"
    git checkout main || return 1
    git branch -D "${branch}" || return 1
    return 100
  fi

  git add .gitignore
  git commit -m "${title}" \
    -m "Append \`${line}\` to .gitignore so the docker monorepo's per-repo Claude session symlink no longer leaks into git status. No code or build impact." \
    || return 1

  git push "${url}" "${branch}" || return 1

  local body
  # shellcheck disable=SC2016  # backticks in single-quoted printf format are intentional literal markdown code spans
  body="$(printf '## Why\n\n%s\n\n## What\n\nAppend `%s` to `.gitignore`. Idempotent — running this PR a second time would no-op.\n\nNo code, Dockerfile, or test impact.\n\n## Test plan\n\n- [x] CI green on this PR\n- After merge: confirm `git status` no longer flags `%s` (if a symlink with that name exists locally)\n' "${why}" "${line}" "${line}")"

  local pr_url
  pr_url="$(gh pr create -R "${ORG}/${reponame}" --base main --head "${branch}" \
    --title "${title}" \
    --body "${body}")" || return 1

  info "[${reponame}] PR: ${pr_url}"
}

main "$@"
