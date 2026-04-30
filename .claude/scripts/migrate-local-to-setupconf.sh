#!/usr/bin/env bash
#
# migrate-local-to-setupconf.sh — one-shot fanout for issue #201.
#
# Pre-#201 layout: <repo>/setup.conf was a derived snapshot (gitignored)
# and <repo>/setup.conf.local was the committed user override.
# Post-#201 layout: <repo>/setup.conf is the committed user override
# (no longer gitignored), .local is gone.
#
# This script handles the transition for the 17 ycpss91255-docker
# downstream repos. For each repo:
#   1. If setup.conf.local exists, mv to setup.conf (overwriting any
#      old gitignored snapshot). The .local content is the source of
#      truth; the old setup.conf snapshot is reproducible from
#      template/setup.conf + .local merge.
#   2. Stage setup.conf (no longer gitignored after the next template
#      upgrade applies the new lib/gitignore.sh canonical list).
#   3. .gitignore canonical sync runs separately via init.sh on the
#      same upgrade — that pass adds setup.conf.local to canonical
#      gitignore. We do NOT edit .gitignore here; init.sh's resync
#      handles it.
#
# Idempotent: re-running on a repo that has already been migrated
# (setup.conf committed, no .local) is a no-op.
#
# DELETE THIS SCRIPT after the v0.16.x cycle: by then every downstream
# is migrated and the script has no recurring purpose.
#
# Usage:
#   .claude/scripts/migrate-local-to-setupconf.sh [--dry-run] <repo-path>...
#
# Examples:
#   # Single repo, dry-run
#   .claude/scripts/migrate-local-to-setupconf.sh --dry-run env/ros_noetic
#
#   # Validate on two repos first
#   .claude/scripts/migrate-local-to-setupconf.sh env/ros_noetic app/ros1_bridge
#
#   # Org-wide rollout
#   .claude/scripts/migrate-local-to-setupconf.sh agent/* app/* env/*

set -euo pipefail

_DRY_RUN=0
_REPOS=()

usage() {
  cat >&2 <<'EOF'
Usage: migrate-local-to-setupconf.sh [--dry-run] <repo-path>...

Migrate per-repo setup.conf.local to setup.conf for the post-#201
2-file model. One-shot: delete this script after v0.16.x cycle.

Options:
  --dry-run       Print planned actions without modifying anything.
  -h, --help      Show this help.

EOF
}

main() {
  while (( $# > 0 )); do
    case "$1" in
      --dry-run) _DRY_RUN=1; shift ;;
      -h|--help) usage; exit 0 ;;
      --) shift; _REPOS+=("$@"); break ;;
      -*)
        printf '[migrate] unknown flag: %s\n' "$1" >&2
        usage
        exit 2
        ;;
      *) _REPOS+=("$1"); shift ;;
    esac
  done

  if (( ${#_REPOS[@]} == 0 )); then
    printf '[migrate] no repos given\n' >&2
    usage
    exit 2
  fi

  local _migrated=0 _skipped=0 _errors=0
  local _repo
  for _repo in "${_REPOS[@]}"; do
    if ! _migrate_one "${_repo}"; then
      _errors=$((_errors + 1))
      continue
    fi
    if [[ -f "${_repo}/setup.conf" && ! -f "${_repo}/setup.conf.local" ]]; then
      _migrated=$((_migrated + 1))
    else
      _skipped=$((_skipped + 1))
    fi
  done

  printf '\n[migrate] summary: migrated=%d skipped=%d errors=%d\n' \
    "${_migrated}" "${_skipped}" "${_errors}" >&2

  (( _errors == 0 ))
}

_migrate_one() {
  local _repo="$1"
  if [[ ! -d "${_repo}" ]]; then
    printf '[migrate] %s: not a directory, skip\n' "${_repo}" >&2
    return 1
  fi
  if [[ ! -d "${_repo}/.git" ]] && ! git -C "${_repo}" rev-parse --git-dir >/dev/null 2>&1; then
    printf '[migrate] %s: not a git repo, skip\n' "${_repo}" >&2
    return 1
  fi

  local _local="${_repo}/setup.conf.local"
  local _conf="${_repo}/setup.conf"

  if [[ ! -f "${_local}" ]]; then
    if [[ -f "${_conf}" ]]; then
      printf '[migrate] %s: already migrated (setup.conf present, no .local)\n' "${_repo}"
    else
      printf '[migrate] %s: nothing to migrate (no .local, no setup.conf)\n' "${_repo}"
    fi
    return 0
  fi

  printf '[migrate] %s: setup.conf.local → setup.conf' "${_repo}"
  if [[ -f "${_conf}" ]]; then
    printf ' (overwriting existing snapshot)'
  fi
  printf '\n'

  if (( _DRY_RUN )); then
    printf '         [dry-run] mv %s %s\n' "${_local}" "${_conf}"
    # shellcheck disable=SC2016  # literal backticks in informational dry-run text
    printf '         [dry-run] sed -i remove obsolete `setup.conf` line from %s/.gitignore\n' "${_repo}"
    printf '         [dry-run] git -C %s add setup.conf .gitignore\n' "${_repo}"
    printf '         [dry-run] git -C %s rm --cached setup.conf.local (if tracked)\n' "${_repo}"
    return 0
  fi

  mv -f "${_local}" "${_conf}"

  # Remove the stale `setup.conf` line from .gitignore. Pre-v0.16.0
  # template's lib/gitignore.sh listed `setup.conf` as canonical;
  # post-#201 it's been removed. _sync_gitignore on upgrade only ADDs
  # missing entries — it never removes obsolete ones — so this script
  # has to clean the line up by hand. Without this step, `git add
  # setup.conf` is silently dropped because gitignore still matches.
  local _gitignore="${_repo}/.gitignore"
  if [[ -f "${_gitignore}" ]] && grep -qE '^setup\.conf$' "${_gitignore}"; then
    sed -i.bak '/^setup\.conf$/d' "${_gitignore}"
    rm -f "${_gitignore}.bak"
  fi

  git -C "${_repo}" add setup.conf .gitignore

  # The pre-#201 .local was committed. Drop it from the index so the
  # user's commit reflects the rename. The working-tree file already
  # vanished via mv above.
  if git -C "${_repo}" ls-files --error-unmatch setup.conf.local >/dev/null 2>&1; then
    git -C "${_repo}" rm --cached --quiet setup.conf.local
  fi
}

main "$@"
