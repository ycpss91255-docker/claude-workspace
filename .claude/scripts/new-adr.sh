#!/usr/bin/env bash
# log-allow:script -- emits data-product output (markdown table / next-step hint / Monitor protocol / pass-fail summary) alongside _log_*; per-callsite split deferred until tooling can distinguish.

# new-adr.sh -- create a new Architecture Decision Record (ADR) under
# the current repo's `doc/adr/` directory.
#
# Naming convention: `doc/adr/NNNNNNNN-<slug>.md` (8-digit zero-padded
# number, kebab-case slug). Numbers auto-increment from the existing
# max; never reused once assigned. Superseded ADRs stay in place with
# `Status: Superseded by ADR-NNNNNNNN` on the old one.
#
# Usage:
#   new-adr.sh <slug> [--dry-run] [-h|--help]
#
# Exit:
#   0  ADR created (or --dry-run preview)
#   1  filesystem failure (mkdir / write)
#   2  argument or validation error
#
# Refs: issue ycpss91255-docker/docker_harness#97.

set -uo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: new-adr.sh <slug> [options]

Positional:
  <slug>          Kebab-case identifier (a-z, 0-9, dash). 1-80 chars.
                  Example: `entrypoint-single-file`.

Options:
  --dry-run       Print planned path + body; do not write.
  -h, --help      Show this help.

The script creates `doc/adr/NNNNNNNN-<slug>.md` in the current cwd,
where NNNNNNNN is one greater than the max numbered ADR already in
the directory (or `00000001` for the first ADR).

See .claude/commands/adr.md for the full /adr slash-command workflow.
EOF
}

err() { printf '%s\n' "$*" >&2; }

# next_adr_number — echo the next ADR number as 8-digit zero-padded.
# Scans `doc/adr/[0-9]*.md` for the max numeric prefix; returns 1 if
# none exist.
next_adr_number() {
  local adr_dir="$1"
  if [[ ! -d "${adr_dir}" ]]; then
    printf '00000001\n'
    return 0
  fi

  local max=0 file basename num
  for file in "${adr_dir}"/[0-9]*.md; do
    [[ -e "${file}" ]] || continue
    basename="${file##*/}"
    if [[ "${basename}" =~ ^([0-9]+)- ]]; then
      num="${BASH_REMATCH[1]}"
      # Strip leading zeros for arithmetic (10# forces base-10).
      num=$((10#${num}))
      (( num > max )) && max=${num}
    fi
  done

  printf '%08d\n' "$((max + 1))"
}

# render_template <number> <slug> <date>
render_template() {
  local number="$1" slug="$2" date="$3"
  local title
  # Title-case the slug: foo-bar -> Foo Bar.
  title="$(printf '%s\n' "${slug}" | awk -F'-' '{
    for (i=1; i<=NF; i++) {
      $i = toupper(substr($i,1,1)) substr($i,2)
    }
    print
  }' OFS=' ')"

  cat <<EOF
# ADR-${number}: ${title}

- **Date:** ${date}
- **Status:** Accepted

## Context

<Why this decision was needed. What problem prompted the discussion?
What constraints / forces are in play?>

## Decision

<What did we choose? State it in one or two sentences first, then
elaborate.>

## Alternatives

<What other options were considered, and why were they rejected?
Capture rationale here so a future reader does not have to re-derive
the trade-offs.>

## Consequences

<What changes as a result of this decision? What new costs do we
take on, and what costs do we avoid? Are any follow-ups blocked or
unblocked?>
EOF
}

main() {
  local slug="" dry_run=0
  while (( $# > 0 )); do
    case "$1" in
      -h|--help) usage; return 0 ;;
      --dry-run) dry_run=1; shift ;;
      -*) err "unknown flag: $1"; return 2 ;;
      *)
        if [[ -z "${slug}" ]]; then
          slug="$1"; shift
        else
          err "unexpected arg: $1"; return 2
        fi ;;
    esac
  done

  if [[ -z "${slug}" ]]; then
    err "missing <slug>"
    usage
    return 2
  fi

  # Slug shape: kebab-case, 1-80 chars, no leading / trailing / double
  # dash.
  if ! [[ "${slug}" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
    err "invalid slug: '${slug}'"
    err "  Expected kebab-case (a-z, 0-9, single dashes; no leading/"
    err "  trailing/double dash). Example: 'entrypoint-single-file'."
    return 2
  fi
  if (( ${#slug} > 80 )); then
    err "slug too long (${#slug} chars; max 80)"
    return 2
  fi

  local repo_root adr_dir number date file body
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  adr_dir="${repo_root}/doc/adr"
  number="$(next_adr_number "${adr_dir}")"
  date="$(date -u +%Y-%m-%d)"
  file="${adr_dir}/${number}-${slug}.md"
  body="$(render_template "${number}" "${slug}" "${date}")"

  if (( dry_run )); then
    printf '[dry-run] would create: %s\n' "${file}"
    printf '%s\n---\n%s\n---\n' "[dry-run] body:" "${body}"
    return 0
  fi

  if ! mkdir -p "${adr_dir}" 2>/dev/null; then
    err "mkdir failed: ${adr_dir}"
    return 1
  fi

  if [[ -e "${file}" ]]; then
    err "ADR already exists: ${file}"
    err "  Pick a different slug or supersede the existing entry."
    return 2
  fi

  if ! printf '%s\n' "${body}" > "${file}"; then
    err "write failed: ${file}"
    return 1
  fi

  printf 'created %s\n' "${file}"
  # shellcheck disable=SC2016
  printf '\nNext step: fill in the Context / Decision / Alternatives /\n'
  # shellcheck disable=SC2016
  printf 'Consequences sections, then: git add %s && git commit\n' \
    "${file}"
}

main "$@"
