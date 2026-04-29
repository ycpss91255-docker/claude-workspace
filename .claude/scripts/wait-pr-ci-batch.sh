#!/usr/bin/env bash
# wait-pr-ci-batch.sh — poll multiple PRs across multiple repos in a
# single Monitor pass. Sibling of wait-pr-ci.sh (single-repo); both
# share output shape and exit codes.
#
# Designed for `/batch-template-upgrade` follow-up: after opening N PRs
# across N downstream repos, you need them all green before calling
# batch-pr-merge.sh. Spawning one Monitor per repo (the previous
# advice in wait-pr-ci/SKILL.md) works for N=2-3 but produces N
# parallel notification streams at N=15+. This script aggregates into
# one stream — one snapshot block per state transition.
#
# Usage:
#   wait-pr-ci-batch.sh <repo>:<pr> [<repo>:<pr> ...] [options]
#
# `<repo>` is short (e.g. `ai_agent`) — prefixed with the default
# owner — or full (`<owner>/<repo>`).
#
# Options:
#   --owner <OWNER>           Default owner for short `<repo>` form
#                             (default: ycpss91255-docker)
#   --check-filter <jq-expr>  jq inner expression filtering
#                             .statusCheckRollup[]?. Default:
#                             '.name=="test" or (.name|startswith("Integration"))'
#                             For container repos (the typical
#                             batch-template-upgrade case) pass
#                             '.name=="call-docker-build / docker-build"'.
#   --interval <seconds>      Poll interval (default 45; 0 for tests)
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
#   <owner>/<repo>#<pr>: checks=<state> mergeable=<m>
#   ...
#   ---
# Final line: `ALL_DONE` or `FAIL <owner>/<repo>#<pr>`.

set -euo pipefail

readonly DEFAULT_FILTER='.name=="test" or (.name|startswith("Integration"))'
readonly DEFAULT_OWNER='ycpss91255-docker'

usage() {
  sed -n '/^# Usage:/,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
}

err() {
  printf '[wait-pr-ci-batch] ERROR: %s\n' "$*" >&2
}

main() {
  local owner="${DEFAULT_OWNER}"
  local check_filter="${DEFAULT_FILTER}"
  local interval=45
  local max_iter=0
  local -a pairs=()

  while (( $# > 0 )); do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --owner) owner="$2"; shift 2 ;;
      --check-filter) check_filter="$2"; shift 2 ;;
      --interval) interval="$2"; shift 2 ;;
      --max-iterations) max_iter="$2"; shift 2 ;;
      --) shift; pairs+=("$@"); break ;;
      -*) err "unknown arg: $1"; usage; exit 2 ;;
      *)
        if [[ "$1" != *:* ]]; then
          err "expected <repo>:<pr>, got: $1"
          exit 2
        fi
        pairs+=("$1")
        shift
        ;;
    esac
  done

  if (( ${#pairs[@]} == 0 )); then
    err "at least one <repo>:<pr> required"
    exit 2
  fi

  # Normalize each pair into "<owner>/<repo>:<pr>".
  local -a norm_pairs=()
  local p repo pr
  for p in "${pairs[@]}"; do
    repo="${p%:*}"
    pr="${p##*:}"
    if [[ -z "${repo}" || -z "${pr}" ]]; then
      err "bad pair: ${p}"
      exit 2
    fi
    if [[ "${pr}" =~ [^0-9] ]]; then
      err "PR number must be a positive integer in: ${p}"
      exit 2
    fi
    if [[ "${repo}" != */* ]]; then
      repo="${owner}/${repo}"
    fi
    norm_pairs+=("${repo}:${pr}")
  done

  local prev=""
  local iter=0
  while true; do
    iter=$((iter + 1))

    local out=""
    local all_ready=1
    local fail_pair=""

    for p in "${norm_pairs[@]}"; do
      repo="${p%:*}"
      pr="${p##*:}"

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

      out="${out}${repo}#${pr}: checks=${state} mergeable=${m}"$'\n'

      case "${state}" in
        FAIL) fail_pair="${repo}#${pr}"; all_ready=0 ;;
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

    if [[ -n "${fail_pair}" ]]; then
      printf 'FAIL %s\n' "${fail_pair}"
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
