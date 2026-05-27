#!/usr/bin/env bash
# wait-tag-ci.sh — poll GitHub Actions runs for a tag or branch until settled.
#
# Sibling to wait-pr-ci.sh — same shape, different query. wait-pr-ci uses
# `gh pr view --json statusCheckRollup`; this one uses `gh run list
# --branch <ref>` because tag-triggered workflows are not PR-scoped (no
# rollup). Use this for release-test-tools / release-worker / any
# `on: push: tags:` workflow.
#
# Usage:
#   wait-tag-ci.sh --repo <OWNER>/<REPO> --branch <ref> [options]
#
# Options:
#   --repo <OWNER>/<REPO>     GitHub repo (required)
#   --branch <ref>            Tag or branch name (e.g. v0.12.2, main) (required)
#   --check-filter <jq-expr>  jq inner expression filtering .[]?. Default: 'true'
#                             (all runs). Example: '.name=="release"'.
#   --limit <N>               Max runs to query per poll (default 10)
#   --interval <seconds>      Poll interval (default 45; 0 = no sleep, for tests)
#   --max-iterations <N>      Iteration cap (default 0 = unlimited; for tests)
#   -h, --help                Show this help
#
# Exit:
#   0   = ALL_DONE — every matched run conclusion = success
#   1   = FAIL     — at least one matched run completed with conclusion != success
#   2   = arg error
#   124 = max-iterations exhausted (e.g. tag pushed but no run ever appeared)
#
# Output (per state transition):
#   <run-name>: <status>/<conclusion>
#   ...
#   ---
# Final line: `ALL_DONE` or `FAIL <run-name>`.

set -euo pipefail

_WTC_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
# shellcheck source=lib/log.sh disable=SC1091
source "${_WTC_SCRIPT_DIR}/lib/log.sh"

readonly DEFAULT_FILTER='true'

usage() {
  sed -n '/^# Usage:/,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
}

main() {
  local repo=""
  local ref=""
  local check_filter="${DEFAULT_FILTER}"
  local limit=10
  local interval=45
  local max_iter=0

  while (( $# > 0 )); do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --repo) repo="$2"; shift 2 ;;
      --branch) ref="$2"; shift 2 ;;
      --check-filter) check_filter="$2"; shift 2 ;;
      --limit) limit="$2"; shift 2 ;;
      --interval) interval="$2"; shift 2 ;;
      --max-iterations) max_iter="$2"; shift 2 ;;
      *) _log_fatal wait-tag-ci unrecognised_arg arg="${1}"; usage; exit 2 ;;
    esac
  done

  if [[ -z "${repo}" ]]; then
    _log_fatal wait-tag-ci precondition_missing arg=--repo
    exit 2
  fi
  if [[ -z "${ref}" ]]; then
    _log_fatal wait-tag-ci precondition_missing arg=--branch
    exit 2
  fi

  local prev=""
  local iter=0
  while true; do
    iter=$((iter + 1))

    local s
    s=$(gh run list --repo "${repo}" --branch "${ref}" \
          --limit "${limit}" \
          --json databaseId,name,status,conclusion 2>/dev/null \
        || echo '[]')

    local filtered
    filtered=$(jq -c "[.[]? | select(${check_filter})]" <<< "${s}")

    local out
    out=$(jq -r '.[] | "\(.name): \(.status)/\(.conclusion // "?")"' \
            <<< "${filtered}" | sort)

    case "${out}" in
      "${prev}") : ;;
      *) printf '%s\n---\n' "${out}" ;;
    esac
    prev="${out}"

    local total done_count failed_count
    total=$(jq -r 'length' <<< "${filtered}")
    done_count=$(jq -r '[.[] | select(.status == "completed")] | length' \
                   <<< "${filtered}")
    failed_count=$(jq -r \
      '[.[] | select(.status == "completed" and .conclusion != "success" and .conclusion != "skipped")] | length' \
      <<< "${filtered}")

    if (( total > 0 && done_count == total )); then
      if (( failed_count == 0 )); then
        echo "ALL_DONE"
        exit 0
      fi
      local first_fail
      first_fail=$(jq -r \
        '[.[] | select(.status == "completed" and .conclusion != "success" and .conclusion != "skipped")][0].name // "?"' \
        <<< "${filtered}")
      printf 'FAIL %s\n' "${first_fail}"
      exit 1
    fi

    if (( max_iter > 0 && iter >= max_iter )); then
      _log_err wait-tag-ci wait_failed reason=max-iterations max="${max_iter}"
      exit 124
    fi

    if (( interval > 0 )); then
      sleep "${interval}"
    fi
  done
}

main "$@"
