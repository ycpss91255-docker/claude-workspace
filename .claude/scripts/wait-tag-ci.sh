#!/usr/bin/env bash
# log-allow:script -- emits data-product output (markdown table / next-step hint / Monitor protocol / pass-fail summary) alongside _log_*; per-callsite split deferred until tooling can distinguish.

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

# _emit_event <exit_reason> <repo> <branch> <iter> <watch_start>
#
# Append one JSON event line per terminal exit (refs #175 Phase 1).
# Same log file as wait-pr-ci.sh / wait-pr-ci-batch.sh; schema uses
# `branch` instead of `prs` / `pairs`. No `head_moves` because tag CI
# does not poll headRefOid. Non-fatal on write failure.
_emit_event() {
  local exit_reason="$1" repo="$2" branch="$3" iter="$4" watch_start="$5"
  local log_dir="${HOME}/.claude/log"
  mkdir -p "${log_dir}" 2>/dev/null || return 0
  local ts elapsed
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  elapsed=$(( $(date -u +%s) - watch_start ))
  ( printf '{"ts":"%s","script":"wait-tag-ci.sh","repo":"%s","branch":"%s","exit_reason":"%s","iterations":%d,"elapsed_sec":%d}\n' \
      "${ts}" "${repo}" "${branch}" "${exit_reason}" "${iter}" "${elapsed}" \
      >> "${log_dir}/wait-pr-ci-events.log" ) 2>/dev/null || true
}

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

  local watch_start
  watch_start=$(date -u +%s)

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
        _emit_event ALL_DONE "${repo}" "${ref}" "${iter}" "${watch_start}"
        echo "ALL_DONE"
        exit 0
      fi
      local first_fail
      first_fail=$(jq -r \
        '[.[] | select(.status == "completed" and .conclusion != "success" and .conclusion != "skipped")][0].name // "?"' \
        <<< "${filtered}")
      printf 'FAIL %s\n' "${first_fail}"
      _emit_event FAIL "${repo}" "${ref}" "${iter}" "${watch_start}"
      exit 1
    fi

    if (( max_iter > 0 && iter >= max_iter )); then
      _log_err wait-tag-ci wait_failed reason=max-iterations max="${max_iter}"
      _emit_event timeout_max_iter "${repo}" "${ref}" "${iter}" "${watch_start}"
      exit 124
    fi

    if (( interval > 0 )); then
      sleep "${interval}"
    fi
  done
}

main "$@"
