#!/usr/bin/env bash
# wait-issue-close.sh -- poll a GitHub issue until it transitions to CLOSED.
#
# Sibling to wait-tag-ci.sh -- same Monitor invocation shape, different
# query. Use this when an adoption / fanout step is gated on an upstream
# issue closing (e.g. base#367 closing before downstream PR opens).
#
# Usage:
#   wait-issue-close.sh --repo <OWNER>/<REPO> --issue <N> [options]
#
# Options:
#   --repo <OWNER>/<REPO>     GitHub repo (required)
#   --issue <N>               Issue number (required)
#   --on-close "<msg>"        Extra message to print on CLOSED, before exit 0
#   --interval <seconds>      Poll interval (default 1800 = 30 min; 0 = no
#                             sleep, for tests)
#   --max-iterations <N>      Iteration cap (default 0 = unlimited)
#   -h, --help                Show this help
#
# Exit:
#   0   = CLOSED detected (snapshot + optional on-close message printed)
#   2   = arg error
#   124 = max-iterations exhausted
#
# Output (per state transition):
#   issue#<N>: state=<STATE>[ linked=PR#<n>,PR#<n>...]
#   ---

set -euo pipefail

_WIC_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
# shellcheck source=lib/log.sh disable=SC1091
source "${_WIC_SCRIPT_DIR}/lib/log.sh"

usage() {
  sed -n '/^# Usage:/,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
}

main() {
  local repo=""
  local issue=""
  local on_close=""
  local interval=1800
  local max_iter=0

  while (( $# > 0 )); do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --repo) repo="$2"; shift 2 ;;
      --issue) issue="$2"; shift 2 ;;
      --on-close) on_close="$2"; shift 2 ;;
      --interval) interval="$2"; shift 2 ;;
      --max-iterations) max_iter="$2"; shift 2 ;;
      *) _log_fatal wait-issue-close unrecognised_arg arg="${1}"; usage; exit 2 ;;
    esac
  done

  if [[ -z "${repo}" ]]; then
    _log_fatal wait-issue-close precondition_missing arg=--repo
    exit 2
  fi
  if [[ -z "${issue}" || ! "${issue}" =~ ^[0-9]+$ ]]; then
    _log_fatal wait-issue-close precondition_missing arg=--issue reason=not-positive-integer
    exit 2
  fi

  local prev=""
  local iter=0
  while true; do
    iter=$((iter + 1))

    local s state linked
    s=$(gh issue view "${issue}" --repo "${repo}" \
          --json state,closedByPullRequestsReferences 2>/dev/null \
        || echo '{}')
    state=$(jq -r '.state // "?"' <<< "${s}")
    linked=$(jq -r '
      .closedByPullRequestsReferences // []
      | map("PR#\(.number)")
      | if length == 0 then "" else " linked=" + join(",") end
    ' <<< "${s}")

    local out="issue#${issue}: state=${state}${linked}"
    case "${out}" in
      "${prev}") : ;;
      *) printf '%s\n---\n' "${out}" ;;
    esac
    prev="${out}"

    if [[ "${state}" == "CLOSED" ]]; then
      if [[ -n "${on_close}" ]]; then
        printf '%s\n' "${on_close}"
      fi
      exit 0
    fi

    if (( max_iter > 0 && iter >= max_iter )); then
      _log_err wait-issue-close wait_failed reason=max-iterations max="${max_iter}"
      exit 124
    fi

    if (( interval > 0 )); then
      sleep "${interval}"
    fi
  done
}

main "$@"
