#!/usr/bin/env bash
# log-allow:script -- emits data-product output (markdown table / next-step hint / Monitor protocol / pass-fail summary) alongside _log_*; per-callsite split deferred until tooling can distinguish.

# wait-release.sh -- poll GitHub releases until a tag matching the pattern
# appears as stable (no `-rc` substring) on the release list.
#
# Sibling to wait-issue-close.sh / wait-tag-ci.sh. Use this when an
# adoption / fanout step is gated on an upstream stable release appearing
# (e.g. waiting for `base v0.32.0` after `v0.32.0-rc1` was cut).
#
# Usage:
#   wait-release.sh --repo <OWNER>/<REPO> --tag-pattern <POSIX-ERE> [options]
#
# Options:
#   --repo <OWNER>/<REPO>     GitHub repo (required)
#   --tag-pattern <ERE>       POSIX ERE matched against each release tagName.
#                             '^v0\.32\.[0-9]+$' matches stable only;
#                             '^v0\.32\.'        matches rc + stable.
#                             (required)
#   --on-stable "<msg>"       Extra message to print after stable snapshot
#   --on-rc "<msg>"           Extra message to print after each RC snapshot
#   --limit <N>               gh release list page size (default 5)
#   --interval <seconds>      Poll interval (default 1800 = 30 min;
#                             0 = no sleep, for tests)
#   --max-iterations <N>      Iteration cap (default 0 = unlimited)
#   -h, --help                Show this help
#
# Exit:
#   0   = stable tag (matches pattern AND no `-rc` substring) detected
#   2   = arg error
#   124 = max-iterations exhausted
#
# Output (per matching tag transition):
#   release: <tag> (stable|rc)
#   ---

set -euo pipefail

_WR_SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
# shellcheck source=lib/log.sh disable=SC1091
source "${_WR_SCRIPT_DIR}/lib/log.sh"

usage() {
  sed -n '/^# Usage:/,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
}

main() {
  local repo=""
  local pattern=""
  local on_stable=""
  local on_rc=""
  local limit=5
  local interval=1800
  local max_iter=0

  while (( $# > 0 )); do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --repo) repo="$2"; shift 2 ;;
      --tag-pattern) pattern="$2"; shift 2 ;;
      --on-stable) on_stable="$2"; shift 2 ;;
      --on-rc) on_rc="$2"; shift 2 ;;
      --limit) limit="$2"; shift 2 ;;
      --interval) interval="$2"; shift 2 ;;
      --max-iterations) max_iter="$2"; shift 2 ;;
      *) _log_fatal wait-release unrecognised_arg arg="${1}"; usage; exit 2 ;;
    esac
  done

  if [[ -z "${repo}" ]]; then
    _log_fatal wait-release precondition_missing arg=--repo
    exit 2
  fi
  if [[ -z "${pattern}" ]]; then
    _log_fatal wait-release precondition_missing arg=--tag-pattern
    exit 2
  fi

  local seen=":"
  local iter=0
  while true; do
    iter=$((iter + 1))

    local s
    s=$(gh release list --repo "${repo}" --limit "${limit}" \
          --json tagName 2>/dev/null \
        || echo '[]')

    local matching
    matching=$(jq -r '.[]?.tagName // empty' <<< "${s}" \
      | grep -E "${pattern}" || true)

    local tag
    while IFS= read -r tag; do
      [[ -z "${tag}" ]] && continue
      case "${seen}" in
        *":${tag}:"*) continue ;;
      esac
      seen="${seen}${tag}:"

      local class
      case "${tag}" in
        *-rc*) class="rc" ;;
        *)     class="stable" ;;
      esac

      printf 'release: %s (%s)\n---\n' "${tag}" "${class}"

      if [[ "${class}" == "stable" ]]; then
        if [[ -n "${on_stable}" ]]; then
          printf '%s\n' "${on_stable}"
        fi
        exit 0
      fi

      if [[ -n "${on_rc}" ]]; then
        printf '%s\n' "${on_rc}"
      fi
    done <<< "${matching}"

    if (( max_iter > 0 && iter >= max_iter )); then
      _log_err wait-release wait_failed reason=max-iterations max="${max_iter}"
      exit 124
    fi

    if (( interval > 0 )); then
      sleep "${interval}"
    fi
  done
}

main "$@"
