#!/usr/bin/env bash
# log-allow:script -- emits data-product output (markdown table / next-step hint / Monitor protocol / pass-fail summary) alongside _log_*; per-callsite split deferred until tooling can distinguish.

# log-allow:script -- emits data-product output (markdown table / next-step hint / Monitor protocol / pass-fail summary) alongside _log_*; per-callsite split deferred until tooling can distinguish.

# wait-pr-ci-batch.sh — poll multiple PRs across multiple repos in a
# single Monitor pass. Sibling of wait-pr-ci.sh (single-repo); both
# share output shape and exit codes.
#
# Designed for `/batch-base-upgrade` follow-up: after opening N PRs
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
#   --check-filter <jq-expr>  Global jq inner expression filtering
#                             .statusCheckRollup[]?. Default:
#                             '.name=="test" or (.name|startswith("Integration"))'
#                             For container repos (the typical
#                             batch-base-upgrade case) pass
#                             '.name=="call-docker-build / docker-build"'.
#   --check-filter <repo>=<jq-expr>
#                             Per-repo override applied only when the
#                             pair's repo matches <repo>. <repo> may be
#                             short (`ros_distro`) or full
#                             (`owner/repo`); short matches against the
#                             pair's short repo basename, full matches
#                             the normalized `<owner>/<repo>`. Repeat
#                             the flag for multiple repos; pairs that
#                             do not match any per-repo entry fall back
#                             to the global filter. Detection rule:
#                             LHS of the first `=` must be a pure
#                             identifier (`[A-Za-z0-9_/-]+`) and RHS
#                             must not start with `=`; anything else is
#                             treated as a global jq expression (e.g.
#                             `.name=="..."` — starts with `.`). If the
#                             same repo key is given twice, the last
#                             occurrence wins.
#   --min-checks <N>          Minimum number of filter-matched checks
#                             required before "all-pass" is allowed. Same
#                             semantics as wait-pr-ci.sh's --min-checks
#                             (default 1, backwards-compatible). Per-repo
#                             override via `--min-checks <repo>=<N>` —
#                             detection rule matches `--check-filter`.
#                             Useful when one repo's filter expects 2
#                             checks (template / multi_run) while others
#                             only expect 1 (single-distro container).
#   --interval <seconds>      Poll interval (default 45; 0 for tests)
#   --max-iterations <N>      Iteration cap (default 0 = unlimited; for tests)
#   -h, --help                Show this help
#
# Stale-rollup guards (refs ycpss91255-docker/docker_harness#60). Same
# semantics as wait-pr-ci.sh: a watch-start completedAt comparison
# demotes carry-over rollup results to "pending" instead of "all-pass",
# and a per-pair `headRefOid` change check emits one
# `[head-moved] <owner>/<repo>#<pr> <old7>..<new7>` line on detection
# while forcing that pair's state to "pending" for the same iteration.
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

_WPCB_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
# shellcheck source=lib/log.sh disable=SC1091
source "${_WPCB_SCRIPT_DIR}/lib/log.sh"

readonly DEFAULT_FILTER='.name=="test" or (.name|startswith("Integration"))'
readonly DEFAULT_OWNER='ycpss91255-docker'

# _emit_event <exit_reason> <iter> <watch_start> <head_moves> <norm_pair...>
#
# Aggregate one JSON line per script invocation (refs #175 Phase 1).
# Sibling of wait-pr-ci.sh's _emit_event; emits to the SAME log file
# (`~/.claude/log/wait-pr-ci-events.log`) but with `pairs` array
# instead of `repo` + `prs`. Non-fatal on write failure.
_emit_event() {
  local exit_reason="$1" iter="$2" watch_start="$3" head_moves="$4"
  shift 4
  local log_dir="${HOME}/.claude/log"
  mkdir -p "${log_dir}" 2>/dev/null || return 0
  local ts elapsed pairs_json
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  elapsed=$(( $(date -u +%s) - watch_start ))
  pairs_json="$(printf '%s\n' "$@" \
    | jq -cRn '[inputs | split(":") | {repo:.[0], pr:(.[1]|tonumber)}]' 2>/dev/null \
    || printf '[]')"
  ( printf '{"ts":"%s","script":"wait-pr-ci-batch.sh","pairs":%s,"exit_reason":"%s","iterations":%d,"elapsed_sec":%d,"head_moves":%d}\n' \
      "${ts}" "${pairs_json}" "${exit_reason}" "${iter}" "${elapsed}" "${head_moves}" \
      >> "${log_dir}/wait-pr-ci-events.log" ) 2>/dev/null || true
}

usage() {
  sed -n '/^# Usage:/,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
}

main() {
  local owner="${DEFAULT_OWNER}"
  local check_filter="${DEFAULT_FILTER}"
  local min_checks=1
  local interval=45
  local max_iter=0
  local -a pairs=()
  local -A filter_by_repo=()
  local -A min_checks_by_repo=()

  while (( $# > 0 )); do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --owner) owner="$2"; shift 2 ;;
      --check-filter)
        local raw_filter="$2"
        local lhs rhs
        lhs="${raw_filter%%=*}"
        rhs="${raw_filter#*=}"
        if [[ "${raw_filter}" == *=* \
              && "${lhs}" =~ ^[A-Za-z0-9_/-]+$ \
              && "${rhs}" != =* ]]; then
          filter_by_repo["${lhs}"]="${rhs}"
        else
          check_filter="${raw_filter}"
        fi
        shift 2
        ;;
      --min-checks)
        local raw_min="$2"
        local mlhs mrhs
        mlhs="${raw_min%%=*}"
        mrhs="${raw_min#*=}"
        if [[ "${raw_min}" == *=* \
              && "${mlhs}" =~ ^[A-Za-z0-9_/-]+$ ]]; then
          if ! [[ "${mrhs}" =~ ^[0-9]+$ ]] || (( mrhs < 1 )); then
            _log_fatal wait-pr-ci-batch precondition_missing arg=--min-checks repo="${mlhs}" value="${mrhs}" reason=not-positive-integer
            exit 2
          fi
          min_checks_by_repo["${mlhs}"]="${mrhs}"
        else
          if ! [[ "${raw_min}" =~ ^[0-9]+$ ]] || (( raw_min < 1 )); then
            _log_fatal wait-pr-ci-batch precondition_missing arg=--min-checks value="${raw_min}" reason=not-positive-integer
            exit 2
          fi
          min_checks="${raw_min}"
        fi
        shift 2
        ;;
      --interval) interval="$2"; shift 2 ;;
      --max-iterations) max_iter="$2"; shift 2 ;;
      --) shift; pairs+=("$@"); break ;;
      -*) _log_fatal wait-pr-ci-batch unrecognised_arg arg="${1}"; usage; exit 2 ;;
      *)
        if [[ "$1" != *:* ]]; then
          _log_fatal wait-pr-ci-batch precondition_missing arg="<repo>:<pr>" value="${1}" reason=bad-format
          exit 2
        fi
        pairs+=("$1")
        shift
        ;;
    esac
  done

  if (( ${#pairs[@]} == 0 )); then
    _log_fatal wait-pr-ci-batch precondition_missing arg="<repo>:<pr>" reason=no-pairs
    exit 2
  fi

  # Normalize each pair into "<owner>/<repo>:<pr>".
  local -a norm_pairs=()
  local p repo pr
  for p in "${pairs[@]}"; do
    repo="${p%:*}"
    pr="${p##*:}"
    if [[ -z "${repo}" || -z "${pr}" ]]; then
      _log_fatal wait-pr-ci-batch precondition_missing pair="${p}" reason=bad-format
      exit 2
    fi
    if [[ "${pr}" =~ [^0-9] ]]; then
      _log_fatal wait-pr-ci-batch precondition_missing pair="${p}" reason=non-numeric-pr
      exit 2
    fi
    if [[ "${repo}" != */* ]]; then
      repo="${owner}/${repo}"
    fi
    norm_pairs+=("${repo}:${pr}")
  done

  local watch_start
  watch_start=$(date -u +%s)

  local head_moves_total=0
  local -A head_oid_by_pair=()

  local prev=""
  local iter=0
  while true; do
    iter=$((iter + 1))

    local out=""
    local all_ready=1
    local fail_pair=""
    local fail_reason=""

    for p in "${norm_pairs[@]}"; do
      repo="${p%:*}"
      pr="${p##*:}"

      local s
      s=$(gh pr view "${pr}" --repo "${repo}" \
            --json mergeable,statusCheckRollup,headRefOid,state 2>/dev/null \
          || echo '{}')

      # headRefOid stale-rollup guard, same as wait-pr-ci.sh.
      local current_oid prev_oid head_moved=0
      current_oid=$(jq -r '.headRefOid // ""' <<< "${s}")
      prev_oid="${head_oid_by_pair[${p}]:-}"
      if [[ -n "${prev_oid}" && -n "${current_oid}" \
            && "${current_oid}" != "${prev_oid}" ]]; then
        head_moved=1
        head_moves_total=$((head_moves_total + 1))
        printf '[head-moved] %s#%s %s..%s\n' \
          "${repo}" "${pr}" "${prev_oid:0:7}" "${current_oid:0:7}"
      fi
      head_oid_by_pair["${p}"]="${current_oid}"

      # Terminal-state short circuit (refs #113). See wait-pr-ci.sh for
      # the full rationale; same shape applied per-pair.
      local pr_state
      pr_state=$(jq -r '.state // "?"' <<< "${s}")
      case "${pr_state}" in
        MERGED)
          out="${out}${repo}#${pr}: state=MERGED (auto-merge completed)"$'\n'
          continue
          ;;
        CLOSED)
          out="${out}${repo}#${pr}: state=CLOSED without merge"$'\n'
          fail_pair="${repo}#${pr}"
          fail_reason="closed"
          all_ready=0
          continue
          ;;
      esac

      local short="${repo##*/}"
      local pair_filter="${check_filter}"
      if [[ -n "${filter_by_repo[${repo}]:-}" ]]; then
        pair_filter="${filter_by_repo[${repo}]}"
      elif [[ -n "${filter_by_repo[${short}]:-}" ]]; then
        pair_filter="${filter_by_repo[${short}]}"
      fi

      local pair_min="${min_checks}"
      if [[ -n "${min_checks_by_repo[${repo}]:-}" ]]; then
        pair_min="${min_checks_by_repo[${repo}]}"
      elif [[ -n "${min_checks_by_repo[${short}]:-}" ]]; then
        pair_min="${min_checks_by_repo[${short}]}"
      fi

      # See wait-pr-ci.sh for the rationale of all four guards above
      # `all(.conclusion == "SUCCESS")` — length < min_checks catches
      # GitHub's subset-rollup race, any(.status != "COMPLETED") catches
      # the IN_PROGRESS-with-empty-conclusion case, the nested
      # completedAt < watch_start branch catches stale-rollup carry-over
      # right after a force-push, and head_moved demotes if the head
      # changed on this iteration.
      local state
      state=$(jq -r --argjson min "${pair_min}" \
        --argjson watch_start "${watch_start}" \
        "[.statusCheckRollup[]? | select(${pair_filter})] as \$c | \
        if (\$c | length) == 0 then \"no-checks\" \
        elif (\$c | length) < \$min then \"pending\" \
        elif (\$c | any(.status != null and .status != \"COMPLETED\")) then \"pending\" \
        elif (\$c | all(.conclusion == \"SUCCESS\" or .conclusion == \"SKIPPED\")) then \
          (if (\$c | all(.completedAt != null)) \
              and (\$c | all((.completedAt | fromdateiso8601) < \$watch_start)) \
           then \"pending\" else \"all-pass\" end) \
        elif (\$c | any(.conclusion == \"FAILURE\")) then \"FAIL\" \
        else \"pending\" end" <<< "${s}")

      if (( head_moved )) && [[ "${state}" == "all-pass" ]]; then
        state="pending"
      fi

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
      case "${fail_reason:-}" in
        closed)
          printf 'FAIL %s (state=CLOSED without merge)\n' "${fail_pair}"
          ;;
        *)
          printf 'FAIL %s\n' "${fail_pair}"
          ;;
      esac
      _emit_event FAIL "${iter}" "${watch_start}" "${head_moves_total}" "${norm_pairs[@]}"
      exit 1
    fi

    if (( all_ready )); then
      _emit_event ALL_DONE "${iter}" "${watch_start}" "${head_moves_total}" "${norm_pairs[@]}"
      echo "ALL_DONE"
      exit 0
    fi

    if (( max_iter > 0 && iter >= max_iter )); then
      _log_err wait-pr-ci-batch wait_failed reason=max-iterations max="${max_iter}"
      _emit_event timeout_max_iter "${iter}" "${watch_start}" "${head_moves_total}" "${norm_pairs[@]}"
      exit 124
    fi

    if (( interval > 0 )); then
      sleep "${interval}"
    fi
  done
}

main "$@"
