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
#   --min-checks <N>          Minimum number of filter-matched checks
#                             required before "all-pass" is allowed.
#                             Default 1 (backwards-compatible). Set to the
#                             count of required-check names the workflow
#                             ought to register to guard against GitHub's
#                             PR rollup briefly returning a SUBSET of
#                             expected checks right after PR creation
#                             (e.g. for the default filter `test +
#                             Integration ...` use --min-checks 2). When
#                             length < N the state is "pending", not
#                             "all-pass".
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
  local min_checks=1
  local interval=45
  local max_iter=0

  while (( $# > 0 )); do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --repo) repo="$2"; shift 2 ;;
      --prs) prs_csv="$2"; shift 2 ;;
      --check-filter) check_filter="$2"; shift 2 ;;
      --min-checks) min_checks="$2"; shift 2 ;;
      --interval) interval="$2"; shift 2 ;;
      --max-iterations) max_iter="$2"; shift 2 ;;
      *) err "unknown arg: $1"; usage; exit 2 ;;
    esac
  done

  if ! [[ "${min_checks}" =~ ^[0-9]+$ ]] || (( min_checks < 1 )); then
    err "--min-checks must be a positive integer (got: ${min_checks})"
    exit 2
  fi

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

      # Two guards above the original `all(.conclusion == "SUCCESS")` to fix
      # premature ALL_DONE seen in practice (refs ycpss91255-docker/docker_harness#XX):
      #
      #  (a) `length < min_checks`  — GitHub's PR rollup briefly returns a
      #      SUBSET of expected checks right after PR creation; if all visible
      #      ones happen to be SUCCESS, jq's `all([SUCCESS]) == true` reports
      #      false all-pass. Caller passes --min-checks to assert the
      #      filter-matched count.
      #  (b) `any(.status != "COMPLETED")` — when a check is registered but
      #      still IN_PROGRESS / QUEUED, .conclusion is "" so the original
      #      `all(.conclusion == "SUCCESS")` correctly reports false; but
      #      this guard catches the same case earlier and produces a more
      #      meaningful "pending" label. The `.status != null` precondition
      #      preserves backward compatibility with mocks that only set
      #      .conclusion (real GitHub API always populates .status).
      local state
      state=$(jq -r --argjson min "${min_checks}" \
        "[.statusCheckRollup[]? | select(${check_filter})] as \$c | \
        if (\$c | length) == 0 then \"no-checks\" \
        elif (\$c | length) < \$min then \"pending\" \
        elif (\$c | any(.status != null and .status != \"COMPLETED\")) then \"pending\" \
        elif (\$c | all(.conclusion == \"SUCCESS\")) then \"all-pass\" \
        elif (\$c | any(.conclusion == \"FAILURE\")) then \"FAIL\" \
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
