#!/usr/bin/env bash
#
# Batch-upgrade all downstream repos under ycpss91255-docker to a target
# template tag. Iterates a fixed repo list, fetches main via HTTPS (works
# around stale SSH origin tracking), creates chore/template-<tag> branch,
# runs ./template/upgrade.sh + ./template/init.sh, opens a PR per repo.
#
# Usage:
#   batch-template-upgrade.sh <version> --why-file <path> [options]
#   batch-template-upgrade.sh <version> --why "<text>" [options]
#
# Options:
#   --why-file <path>      PR body Why-section content (required, or use --why)
#   --why "<text>"         Inline alternative to --why-file
#   --issue <num>          Tracking issue number for PR body (optional)
#   --dry-run              Print what would be done; skip mutations
#   --only <r1,r2,...>     Limit to listed repos (relative paths, e.g. agent/ai_agent)
#   --skip <r1,r2,...>     Exclude listed repos
#   --continue-on-error    Keep going past failed repos; print summary at end
#   -h, --help             Show this help
#
# Designed to be run from the main session (not a subagent) because subagent
# sandbox blocks git push.

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
readonly SCRIPT_DIR
readonly DEFAULT_PR_BODY_TEMPLATE="${SCRIPT_DIR}/batch-template-pr-body.template.md"
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
  env/osrf_ros2_humble
  env/osrf_ros_kinetic
  env/osrf_ros_noetic
  env/ros2_humble
  env/ros_kinetic
  env/ros_noetic
)

usage() {
  sed -n '/^# Usage:/,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
}

err() {
  printf '[batch-upgrade] ERROR: %s\n' "$*" >&2
}

info() {
  printf '[batch-upgrade] %s\n' "$*"
}

main() {
  local version=""
  local why_file=""
  local why_text=""
  local issue=""
  local dry_run=0
  local continue_on_error=0
  local only_csv=""
  local skip_csv=""

  while (( $# > 0 )); do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --why-file) why_file="$2"; shift 2 ;;
      --why) why_text="$2"; shift 2 ;;
      --issue) issue="$2"; shift 2 ;;
      --dry-run) dry_run=1; shift ;;
      --continue-on-error) continue_on_error=1; shift ;;
      --only) only_csv="$2"; shift 2 ;;
      --skip) skip_csv="$2"; shift 2 ;;
      v[0-9]*) version="$1"; shift ;;
      *) err "unknown arg: $1"; usage; exit 2 ;;
    esac
  done

  if [[ -z "${version}" ]]; then
    err "missing <version> (e.g. v0.12.1)"
    usage
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
  if [[ ! -r "${DEFAULT_PR_BODY_TEMPLATE}" ]]; then
    err "PR body template not found: ${DEFAULT_PR_BODY_TEMPLATE}"
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

  local root
  root="$(git -C "${SCRIPT_DIR}" rev-parse --show-toplevel)"
  readonly root

  local branch="chore/template-${version}"
  local issue_line=""
  if [[ -n "${issue}" ]]; then
    issue_line="Closes part of ${ORG}/template#${issue}."
  fi

  info "version=${version} branch=${branch} dry_run=${dry_run} repos=${#repos[@]}"

  local failed=()
  local skipped=()
  local opened=()

  local repo
  for repo in "${repos[@]}"; do
    local reponame="${repo##*/}"
    local url="https://github.com/${ORG}/${reponame}.git"
    info "=== [${repo}] ==="

    if [[ ! -d "${root}/${repo}" ]]; then
      err "[${repo}] missing local dir; skipping"
      skipped+=("${repo} (missing)")
      continue
    fi

    if (( dry_run )); then
      info "[${repo}] dry-run: would fetch ${url} main, create ${branch}, run upgrade.sh ${version} + init.sh, open PR"
      continue
    fi

    if upgrade_one "${root}/${repo}" "${url}" "${branch}" "${version}" "${reponame}" "${why}" "${issue_line}"; then
      opened+=("${repo}")
    else
      local rc=$?
      if (( rc == 100 )); then
        skipped+=("${repo} (already at ${version})")
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

upgrade_one() {
  local dir="$1"
  local url="$2"
  local branch="$3"
  local version="$4"
  local reponame="$5"
  local why="$6"
  local issue_line="$7"

  cd "${dir}"

  git fetch "${url}" main || return 1
  git checkout -B main FETCH_HEAD || return 1
  git checkout -B "${branch}" || return 1

  ./template/upgrade.sh "${version}" || return 1
  ./template/init.sh || return 1

  # Skip only if the branch is fully equivalent to main: no commits ahead
  # AND no uncommitted edits AND no untracked files. `git diff --quiet HEAD`
  # alone misses the upgrade case — upgrade.sh commits its work, so HEAD vs
  # working-tree is always clean even when the branch carries a real upgrade.
  if git diff --quiet main HEAD \
     && git diff --quiet \
     && [[ -z "$(git ls-files --others --exclude-standard)" ]]; then
    info "[${reponame}] no changes after upgrade — already at ${version}"
    git checkout main || return 1
    git branch -D "${branch}" || return 1
    return 100
  fi

  if ! git diff --quiet || git ls-files --others --exclude-standard | grep -q .; then
    git add -A
    git commit -m "chore: re-run init.sh after template ${version} pull" || true
  fi

  git push "${url}" "${branch}" || return 1

  local body
  body="$(render_pr_body "${version}" "${why}" "${issue_line}")"

  local pr_url
  pr_url="$(gh pr create -R "${ORG}/${reponame}" --base main --head "${branch}" \
    --title "chore: upgrade template subtree to ${version}" \
    --body "${body}")" || return 1

  info "[${reponame}] PR: ${pr_url}"
}

render_pr_body() {
  local version="$1"
  local why="$2"
  local issue_line="$3"

  # shellcheck disable=SC2016  # envsubst placeholders must stay literal
  VERSION="${version}" \
  WHY="${why}" \
  ISSUE_LINE="${issue_line}" \
    envsubst '${VERSION} ${WHY} ${ISSUE_LINE}' < "${DEFAULT_PR_BODY_TEMPLATE}"
}

main "$@"
