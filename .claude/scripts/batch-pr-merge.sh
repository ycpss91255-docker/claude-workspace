#!/usr/bin/env bash
# batch-pr-merge.sh — squash-merge a list of PRs across repos.
#
# Pairs together with batch-template-upgrade.sh — that script opens N
# downstream PRs, this one closes them out once their CI is green.
#
# Usage:
#   batch-pr-merge.sh [--dry-run] <repo>:<pr> [<repo>:<pr> ...]
#
# Behaviour:
#   - Squash-merges each PR with --delete-branch (matches the project's
#     branch-protection setup: enforce_admins=true, no force-push, etc.)
#   - On any single-PR failure, prints the gh CLI error and continues
#     with the rest. Prints a summary at the end with merged / failed
#     counts. Non-zero exit if any failure occurred.
#   - --dry-run prints the planned merges but executes nothing.

set -euo pipefail

usage() {
  sed -n '/^# Usage:/,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
}

main() {
  local dry_run=0
  local -a pairs=()

  while (( $# > 0 )); do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --dry-run) dry_run=1; shift ;;
      *)
        case "$1" in
          *:*) pairs+=("$1"); shift ;;
          *) printf '[batch-pr-merge] unknown arg: %s\n' "$1" >&2; usage; exit 2 ;;
        esac
        ;;
    esac
  done

  if (( ${#pairs[@]} == 0 )); then
    printf '[batch-pr-merge] no <repo>:<pr> pairs given\n' >&2
    usage
    exit 2
  fi

  local merged=0
  local failed=0
  local -a failed_pairs=()

  local pair repo pr
  for pair in "${pairs[@]}"; do
    repo="${pair%:*}"
    pr="${pair#*:}"

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
      failed_pairs+=("${pair}")
    fi
  done

  printf '\n[batch-pr-merge] summary: merged=%d failed=%d\n' "${merged}" "${failed}"
  if (( failed > 0 )); then
    printf '  failed: %s\n' "${failed_pairs[@]}"
    exit 1
  fi
}

main "$@"
