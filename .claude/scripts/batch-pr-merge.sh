#!/usr/bin/env bash
# batch-pr-merge.sh — squash-merge a list of PRs across repos.
#
# Pairs together with batch-template-upgrade.sh — that script opens N
# downstream PRs, this one closes them out once their CI is green.
#
# Usage:
#   batch-pr-merge.sh [options] <repo>:<pr> [<repo>:<pr> ...]
#
# `<repo>` is short (e.g. `ai_agent`) — prefixed with the default owner
# `ycpss91255-docker` — or full (`<owner>/<repo>`). Mirrors
# wait-pr-ci-batch.sh so the next-step copy-paste block printed by
# batch-template-upgrade.sh works for both scripts.
#
# Options:
#   --owner <OWNER>  Default owner for short `<repo>` form
#                    (default: ycpss91255-docker)
#   --dry-run        Print planned merges and exit without invoking gh
#   -h, --help       Show this help
#
# Behaviour:
#   - Squash-merges each PR with --delete-branch (matches the project's
#     branch-protection setup: enforce_admins=true, no force-push, etc.)
#   - On any single-PR failure, prints the gh CLI error and continues
#     with the rest. Prints a summary at the end with merged / failed
#     counts. Non-zero exit if any failure occurred.
#   - PR numbers are validated up-front; a non-numeric PR exits 2 before
#     any gh invocation.

set -euo pipefail

readonly DEFAULT_OWNER='ycpss91255-docker'

usage() {
  sed -n '/^# Usage:/,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
}

err() {
  printf '[batch-pr-merge] %s\n' "$*" >&2
}

main() {
  local dry_run=0
  local owner="${DEFAULT_OWNER}"
  local -a pairs=()

  while (( $# > 0 )); do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --dry-run) dry_run=1; shift ;;
      --owner) owner="$2"; shift 2 ;;
      --)
        shift
        pairs+=("$@")
        break
        ;;
      *)
        case "$1" in
          *:*) pairs+=("$1"); shift ;;
          *) err "unknown arg: $1"; usage; exit 2 ;;
        esac
        ;;
    esac
  done

  if (( ${#pairs[@]} == 0 )); then
    err "no <repo>:<pr> pairs given"
    usage
    exit 2
  fi

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

  local merged=0
  local failed=0
  local -a failed_pairs=()

  for p in "${norm_pairs[@]}"; do
    repo="${p%:*}"
    pr="${p##*:}"

    if (( dry_run )); then
      printf '[batch-pr-merge] dry-run: would merge %s#%s\n' "${repo}" "${pr}"
      continue
    fi

    printf '[batch-pr-merge] merging %s#%s ... ' "${repo}" "${pr}"
    if gh pr merge "${pr}" -R "${repo}" --squash --delete-branch 2>&1; then
      printf '[batch-pr-merge]   ok\n'
      merged=$((merged + 1))
    else
      printf '[batch-pr-merge]   FAILED\n'
      failed=$((failed + 1))
      failed_pairs+=("${p}")
    fi
  done

  printf '\n[batch-pr-merge] summary: merged=%d failed=%d\n' "${merged}" "${failed}"
  if (( failed > 0 )); then
    printf '  failed: %s\n' "${failed_pairs[@]}"
    exit 1
  fi
}

main "$@"
