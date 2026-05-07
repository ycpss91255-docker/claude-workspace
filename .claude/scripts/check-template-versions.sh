#!/usr/bin/env bash
# check-template-versions.sh — read-only HTTPS fetch of `template/.version`
# from every downstream repo's main branch. Used during release verification
# to confirm `/batch-template-upgrade <vX.Y.Z>` PRs have all merged.
#
# Replaces the ad-hoc `for repo in ...; do curl raw.githubusercontent.com ...; done`
# pattern, which trips Claude Code's bash AST parser ("Unhandled node type:
# string") because the for-loop body wraps a quoted curl URL.
#
# Usage:
#   check-template-versions.sh [options]
#
# Options:
#   --only <r1,r2,...>     Limit to listed repos (relative paths, e.g. agent/ai_agent)
#   --skip <r1,r2,...>     Exclude listed repos
#   --expect <vX.Y.Z>      Exit 1 if any repo is not at this version (default: just print)
#   -h, --help             Show this help
#
# Output: one row per repo, aligned columns:
#   <reponame>             <version-or-MISSING>
#
# Exit:
#   0 = all rows printed (or all match --expect when set)
#   1 = at least one repo did not match --expect
#   2 = arg error

set -euo pipefail

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
)

usage() {
  sed -n '/^# Usage:/,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
}

err() {
  printf '[check-versions] ERROR: %s\n' "$*" >&2
}

main() {
  local only_csv=""
  local skip_csv=""
  local expect=""

  while (( $# > 0 )); do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --only) only_csv="$2"; shift 2 ;;
      --skip) skip_csv="$2"; shift 2 ;;
      --expect) expect="$2"; shift 2 ;;
      *) err "unknown arg: $1"; usage; exit 2 ;;
    esac
  done

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

  local mismatch=0
  local repo
  for repo in "${repos[@]}"; do
    local reponame="${repo##*/}"
    local url="https://raw.githubusercontent.com/${ORG}/${reponame}/main/template/.version"
    local ver
    ver="$(curl -fsSL --max-time 10 "${url}" 2>/dev/null || echo "MISSING")"
    printf '%-22s %s\n' "${reponame}" "${ver}"
    if [[ -n "${expect}" && "${ver}" != "${expect}" ]]; then
      mismatch=1
    fi
  done

  if (( mismatch )); then
    err "one or more repos do not match --expect=${expect}"
    exit 1
  fi
}

main "$@"
