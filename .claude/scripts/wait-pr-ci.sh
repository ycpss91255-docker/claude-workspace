#!/usr/bin/env bash
# wait-pr-ci.sh — poll GitHub PR CI rollup until all PRs settle.
#
# Designed to be wrapped in a single Monitor call from the wait-pr-ci
# skill. Extracting the loop here keeps the Monitor body to one line so
# Claude Code's bash AST parser does not emit `Contains simple_expansion`
# warnings on parameter expansions like ${pair%:*}.
#
# Usage:
#   wait-pr-ci.sh --repo <OWNER>/<REPO> --prs <N1,N2,...> [options]
#
# Options:
#   --repo <OWNER>/<REPO>     GitHub repo (required)
#   --prs <CSV>               Comma-separated PR numbers (required)
#   --check-filter <jq-expr>  jq inner expression filtering
#                             .statusCheckRollup[]?. Default:
#                             '.name=="test" or (.name|startswith("Integration"))'
#   --interval <seconds>      Poll interval (default 45; 0 = no sleep, for tests)
#   --max-iterations <N>      Iteration cap (default 0 = unlimited; for tests)
#   -h, --help                Show this help
#
# Exit:
#   0   = ALL_DONE — every PR is all-pass + MERGEABLE
#   1   = FAIL     — any required check went FAILURE
#   2   = arg error
#   124 = max-iterations exhausted without resolution
#
# Output (per state transition):
#   PR<n>: checks=<state> mergeable=<m>
#   ...
#   ---
# Final line: `ALL_DONE` or `FAIL <pr>`.

set -euo pipefail

readonly DEFAULT_FILTER='.name=="test" or (.name|startswith("Integration"))'

usage() {
  sed -n '/^# Usage:/,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
}

err() {
  printf '[wait-pr-ci] ERROR: %s\n' "$*" >&2
}

main() {
  local repo=""
  local prs_csv=""
  local check_filter="${DEFAULT_FILTER}"
  local interval=45
  local max_iter=0

  while (( $# > 0 )); do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --repo) repo="$2"; shift 2 ;;
      --prs) prs_csv="$2"; shift 2 ;;
      --check-filter) check_filter="$2"; shift 2 ;;
      --interval) interval="$2"; shift 2 ;;
      --max-iterations) max_iter="$2"; shift 2 ;;
      *) err "unknown arg: $1"; usage; exit 2 ;;
    esac
  done

  if [[ -z "${repo}" ]]; then
    err "--repo is required"
    exit 2
  fi
  if [[ -z "${prs_csv}" ]]; then
    err "--prs is required"
    exit 2
  fi

  local -a prs
  IFS=',' read -ra prs <<< "${prs_csv}"

  local prev=""
  local iter=0
  while true; do
    iter=$((iter + 1))

    local out=""
    local all_ready=1
    local fail_pr=""

    local pr
    for pr in "${prs[@]}"; do
      local s
      s=$(gh pr view "${pr}" --repo "${repo}" \
            --json mergeable,statusCheckRollup 2>/dev/null \
          || echo '{}')

      local state
      state=$(jq -r "[.statusCheckRollup[]? | select(${check_filter})] | \
        if length == 0 then \"no-checks\" \
        elif all(.conclusion == \"SUCCESS\") then \"all-pass\" \
        elif any(.conclusion == \"FAILURE\") then \"FAIL\" \
        else \"pending\" end" <<< "${s}")

      local m
      m=$(jq -r '.mergeable // "?"' <<< "${s}")

      out="${out}PR${pr}: checks=${state} mergeable=${m}"$'\n'

      case "${state}" in
        FAIL) fail_pr="${pr}"; all_ready=0 ;;
        all-pass)
          case "${m}" in
            MERGEABLE) : ;;
            *) all_ready=0 ;;
          esac
          ;;
        *) all_ready=0 ;;
      esac
    done

    case "${out}" in
      "${prev}") : ;;
      *) printf '%s---\n' "${out}" ;;
    esac
    prev="${out}"

    if [[ -n "${fail_pr}" ]]; then
      printf 'FAIL %s\n' "${fail_pr}"
      exit 1
    fi

    if (( all_ready )); then
      echo "ALL_DONE"
      exit 0
    fi

    if (( max_iter > 0 && iter >= max_iter )); then
      err "max-iterations (${max_iter}) reached"
      exit 124
    fi

    if (( interval > 0 )); then
      sleep "${interval}"
    fi
  done
}

main "$@"
