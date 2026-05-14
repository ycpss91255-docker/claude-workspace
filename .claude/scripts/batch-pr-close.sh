#!/usr/bin/env bash
# batch-pr-close.sh — close a list of PRs across repos with a single reason.
#
# Sibling of batch-pr-merge.sh. Use when a batch of in-flight PRs has been
# superseded by a newer iteration and must be retired in favour of fresh
# PRs (e.g. v0.28.1 fanout PRs superseded by v0.28.2 after a hotfix
# landed). Single-prompt batch mutation, avoiding the yes-fatigue
# anti-pattern flagged in CLAUDE.md's cross-repo batch rule.
#
# Usage:
#   batch-pr-close.sh [options] --reason "<msg>" <repo>:<pr> [<repo>:<pr> ...]
#
# `<repo>` is short (e.g. `ai_agent`) — prefixed with the default owner
# `ycpss91255-docker` — or full (`<owner>/<repo>`). Mirrors
# batch-pr-merge.sh / wait-pr-ci-batch.sh.
#
# Options:
#   --reason <msg>       Required. Comment posted on each PR before close,
#                        explaining the supersession. Visible to reviewers.
#   --owner <OWNER>      Default owner for short `<repo>` form
#                        (default: ycpss91255-docker)
#   --no-delete-branch   Keep the source branch after close (default deletes).
#   --dry-run            Print planned closes and exit without invoking gh.
#   -h, --help           Show this help.
#
# Behaviour:
#   - Posts the reason as a comment first (so it survives even if close
#     fails), then closes the PR with --delete-branch (unless suppressed).
#   - On any single-PR failure, prints the gh CLI error and continues
#     with the rest. Prints a summary at the end with closed / failed
#     counts. Non-zero exit if any failure occurred.
#   - PR numbers are validated up-front; a non-numeric PR exits 2 before
#     any gh invocation.

set -euo pipefail

readonly DEFAULT_OWNER='ycpss91255-docker'

usage() {
  sed -n '/^# Usage:/,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
}

err() {
  printf '[batch-pr-close] %s\n' "$*" >&2
}

main() {
  local dry_run=0
  local delete_branch=1
  local owner="${DEFAULT_OWNER}"
  local reason=""
  local -a pairs=()

  while (( $# > 0 )); do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --dry-run) dry_run=1; shift ;;
      --no-delete-branch) delete_branch=0; shift ;;
      --owner) owner="$2"; shift 2 ;;
      --reason) reason="$2"; shift 2 ;;
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

  if [[ -z "${reason}" ]]; then
    err "--reason is required (visible PR comment explaining the close)"
    usage
    exit 2
  fi

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

  local closed=0
  local failed=0
  local -a failed_pairs=()

  for p in "${norm_pairs[@]}"; do
    repo="${p%:*}"
    pr="${p##*:}"

    if (( dry_run )); then
      printf '[batch-pr-close] dry-run: would comment+close %s#%s\n' "${repo}" "${pr}"
      continue
    fi

    printf '[batch-pr-close] closing %s#%s ... ' "${repo}" "${pr}"

    local close_args=("${pr}" "-R" "${repo}" "--comment" "${reason}")
    if (( delete_branch )); then
      close_args+=("--delete-branch")
    fi

    if gh pr close "${close_args[@]}" 2>&1; then
      printf '[batch-pr-close]   ok\n'
      closed=$((closed + 1))
    else
      printf '[batch-pr-close]   FAILED\n'
      failed=$((failed + 1))
      failed_pairs+=("${p}")
    fi
  done

  printf '\n[batch-pr-close] summary: closed=%d failed=%d\n' "${closed}" "${failed}"
  if (( failed > 0 )); then
    printf '  failed: %s\n' "${failed_pairs[@]}"
    exit 1
  fi
}

main "$@"
