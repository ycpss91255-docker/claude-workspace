#!/usr/bin/env bash
# check-log-helper-usage.sh -- enforce lib/log.sh adoption.
#
# Scans `.claude/scripts/*.sh` (excluding `lib/`) for bare `printf` /
# `echo` callsites that should be migrated to `_log_*` from
# `.claude/scripts/lib/log.sh`. Designed for CI lint -- exits
# non-zero on violation so the build fails.
#
# Allowlist (commented next to the offending line / block / file):
#   - `# log-allow:script` on the first non-shebang, non-blank line:
#       skip the whole file (use sparingly; data-product scripts
#       like wait-pr-ci protocol output, build_table markdown
#       writers, etc).
#   - `# log-allow:start` ... `# log-allow:end` block markers:
#       skip printf/echo inside the marked region. Inclusive on
#       both ends. The start marker must appear as a comment line
#       on its own (no trailing tokens).
#   - Inside any `usage()` function body (heuristic: between
#       `^usage\(\)\s*\{` and the matching closing `^}`):
#       always allowed. Help-text heredocs / sed extractions are
#       the documented escape hatch.
#
# Violations include `printf '...'` and `echo '...'` at the start of
# a line (any leading whitespace allowed). Embedded `printf` inside
# a `$(...)` or pipe chain is NOT detected -- the lint is
# line-anchored to keep false positives down. Future scope.
#
# Usage:
#   check-log-helper-usage.sh [--scripts-dir <path>]
#
# Options:
#   --scripts-dir <path>  Override the directory scanned
#                         (default: ${CLAUDE_PROJECT_DIR:-cwd}/.claude/scripts)
#   -h, --help            Show this help.
#
# Exit:
#   0  all callsites within an allowlist marker, usage() body, or
#      use _log_*.
#   1  at least one violation reported (one line per violation on
#      stderr; final summary on stderr too).
#   2  arg / scripts-dir error.

set -euo pipefail

usage() {
  sed -n '/^# Usage:/,/^# Exit:/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  printf '\nAllowlist markers: # log-allow:script (file-wide) / # log-allow:start..end (block); usage() body always allowed.\n' >&2
}

scan_file() {
  local file="$1"
  local rel="${file#"${SCRIPTS_DIR}"/}"
  local lineno=0
  local in_usage=0
  local usage_brace_depth=0
  local in_allow_block=0
  local violations=0

  # File-wide marker check (within the first 10 non-blank lines).
  local probe=0
  while IFS= read -r probe_line; do
    probe=$((probe + 1))
    (( probe > 10 )) && break
    [[ "${probe_line}" =~ ^[[:space:]]*$ ]] && continue
    if [[ "${probe_line}" =~ \#[[:space:]]*log-allow:script ]]; then
      return 0
    fi
  done < "${file}"

  while IFS= read -r line; do
    lineno=$((lineno + 1))

    # Block markers (must be on their own comment line).
    if [[ "${line}" =~ ^[[:space:]]*#[[:space:]]*log-allow:start[[:space:]]*$ ]]; then
      in_allow_block=1
      continue
    fi
    if [[ "${line}" =~ ^[[:space:]]*#[[:space:]]*log-allow:end[[:space:]]*$ ]]; then
      in_allow_block=0
      continue
    fi

    # usage() function detection. Heuristic: line starts with
    # `usage()` (zero or two spaces of indent is fine since
    # functions are top-level by Google Style) and contains an
    # opening brace; track brace depth until we close it.
    if (( in_usage == 0 )) && [[ "${line}" =~ ^[[:space:]]*usage\(\)[[:space:]]*\{ ]]; then
      in_usage=1
      usage_brace_depth=1
      # Same-line `}` would close immediately; check.
      if [[ "${line}" =~ \}[[:space:]]*$ ]] && [[ "${line}" =~ \{.*\}[[:space:]]*$ ]]; then
        in_usage=0
        usage_brace_depth=0
      fi
      continue
    fi
    if (( in_usage )); then
      # Crude brace counting via tr (parameter expansion mishandles
      # bracket classes containing literal `{` / `}`).
      local opens closes
      opens=$(printf '%s' "${line}" | tr -cd '{' | wc -c)
      closes=$(printf '%s' "${line}" | tr -cd '}' | wc -c)
      usage_brace_depth=$(( usage_brace_depth + opens - closes ))
      if (( usage_brace_depth <= 0 )); then
        in_usage=0
        usage_brace_depth=0
      fi
      continue
    fi

    (( in_allow_block )) && continue

    # Detect bare printf / echo at line start (leading whitespace OK).
    if [[ "${line}" =~ ^[[:space:]]*(printf|echo)([[:space:]]|$) ]]; then
      printf '%s:%d: bare %s outside usage() / allowlist marker\n' \
        "${rel}" "${lineno}" "${BASH_REMATCH[1]}" >&2
      violations=$((violations + 1))
    fi
  done < "${file}"

  return "${violations}"
}

main() {
  local scripts_dir=""
  while (( $# > 0 )); do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --scripts-dir) scripts_dir="$2"; shift 2 ;;
      *) printf 'unknown arg: %s\n' "$1" >&2; usage; exit 2 ;;
    esac
  done

  if [[ -z "${scripts_dir}" ]]; then
    scripts_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}/.claude/scripts"
  fi
  if [[ ! -d "${scripts_dir}" ]]; then
    printf 'scripts dir not found: %s\n' "${scripts_dir}" >&2
    exit 2
  fi

  SCRIPTS_DIR="${scripts_dir}"

  local total_violations=0
  local scanned=0
  local file

  while IFS= read -r file; do
    [[ -f "${file}" ]] || continue
    scanned=$((scanned + 1))
    local file_v=0
    scan_file "${file}" || file_v=$?
    total_violations=$(( total_violations + file_v ))
  done < <(find "${scripts_dir}" -maxdepth 1 -type f -name '*.sh' | sort)

  if (( total_violations > 0 )); then
    printf '%d violation(s) across %d script(s) scanned. Migrate to _log_* or add an allowlist marker.\n' \
      "${total_violations}" "${scanned}" >&2
    exit 1
  fi

  printf 'check-log-helper-usage: clean (%d script(s) scanned)\n' "${scanned}"
  exit 0
}

main "$@"
