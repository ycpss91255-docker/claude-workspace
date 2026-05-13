#!/usr/bin/env bash
# ci-wall-time-compare.sh -- diff CI wall time between two runs of the
# same GitHub Actions workflow.
#
# Use case: after a CI-perf PR lands, compare run wall time at the
# baseline (pre-fix) commit against the fixed commit, and present a
# markdown table for the PR body / release notes.
#
# Usage:
#   ci-wall-time-compare.sh --repo <OWNER>/<REPO> \
#                           --baseline <RUN-ID> \
#                           --fixed    <RUN-ID> \
#                           [--output <PATH>]
#
# Exit:
#   0   success, table on stdout (or to --output file)
#   1   gh API error
#   2   bad args / in-progress run (missing startedAt or completedAt)

set -uo pipefail

usage() {
  cat >&2 <<'EOF'
ci-wall-time-compare.sh -- diff CI wall time between two runs of the same workflow.

Usage:
  ci-wall-time-compare.sh --repo <OWNER>/<REPO> --baseline <RUN-ID> --fixed <RUN-ID> [options]

Options:
  --repo <OWNER>/<REPO>     GitHub repo (required)
  --baseline <RUN-ID>       Pre-fix run id (required)
  --fixed <RUN-ID>          Post-fix run id (required)
  --output <PATH>           Write table to PATH (default: stdout)
  -h, --help                Show this help

Notes:
  Jobs are matched by name. Jobs present in only one run are skipped.
  Each row shows baseline duration, fixed duration, signed delta + percent.
  Overall row uses max(completedAt) - min(startedAt) across all jobs.
  In-progress runs (any job missing startedAt or completedAt) exit 2.
EOF
}

# fmt_dur <abs_secs> -- format non-negative seconds as "<m>m<ss>s" or "<s>s".
fmt_dur() {
  local secs="$1" m s
  m=$(( secs / 60 ))
  s=$(( secs % 60 ))
  if (( m > 0 )); then
    printf '%dm%02ds' "${m}" "${s}"
  else
    printf '%ds' "${s}"
  fi
}

# fmt_delta <delta_secs> <base_secs> -- format signed seconds + percent.
fmt_delta() {
  local delta_secs="$1" base_secs="$2" sign abs pct
  if (( delta_secs >= 0 )); then
    sign="+"
    abs="${delta_secs}"
  else
    sign="-"
    abs=$(( -delta_secs ))
  fi
  if (( base_secs > 0 )); then
    pct="$(awk -v d="${delta_secs}" -v b="${base_secs}" 'BEGIN {
      p = (d / b) * 100
      if (p > 0) printf "+%d%%", p + 0.5
      else if (p < 0) printf "%d%%", p - 0.5
      else printf "0%%"
    }')"
  else
    pct="n/a"
  fi
  printf '%s%s (%s)' "${sign}" "$(fmt_dur "${abs}")" "${pct}"
}

# iso_to_epoch <iso-8601> -- print epoch seconds, empty on parse fail.
iso_to_epoch() {
  date -d "$1" +%s 2>/dev/null
}

fetch_run_jobs() {
  local repo="$1" run_id="$2" out
  if ! out="$(gh run view "${run_id}" --repo "${repo}" --json jobs 2>&1)"; then
    echo "gh run view failed for run ${run_id} in ${repo}:" >&2
    echo "${out}" >&2
    return 1
  fi
  printf '%s' "${out}"
}

incomplete_job_names() {
  local baseline_json="$1" fixed_json="$2"
  jq -nr --argjson b "${baseline_json}" --argjson f "${fixed_json}" '
    [($b.jobs[]? // empty), ($f.jobs[]? // empty)]
    | map(select(
        .startedAt == null or .completedAt == null
        or .startedAt == "" or .completedAt == ""
      ))
    | map(.name)
    | unique
    | .[]
  ' 2>/dev/null || true
}

build_table() {
  local baseline_json="$1" fixed_json="$2"
  local b_min_start="" b_max_end="" f_min_start="" f_max_end=""

  echo "| shard | baseline | fixed | delta |"
  echo "| --- | --- | --- | --- |"

  while IFS=$'\t' read -r name b_started b_completed f_started f_completed; do
    [[ -z "${name}" ]] && continue
    local b_start_epoch b_end_epoch f_start_epoch f_end_epoch
    b_start_epoch="$(iso_to_epoch "${b_started}")"
    b_end_epoch="$(iso_to_epoch "${b_completed}")"
    f_start_epoch="$(iso_to_epoch "${f_started}")"
    f_end_epoch="$(iso_to_epoch "${f_completed}")"
    if [[ -z "${b_start_epoch}" || -z "${b_end_epoch}" \
       || -z "${f_start_epoch}" || -z "${f_end_epoch}" ]]; then
      continue
    fi
    local b_secs f_secs delta_secs
    b_secs=$(( b_end_epoch - b_start_epoch ))
    f_secs=$(( f_end_epoch - f_start_epoch ))
    delta_secs=$(( f_secs - b_secs ))
    printf '| %s | %s | %s | %s |\n' \
      "${name}" \
      "$(fmt_dur "${b_secs}")" \
      "$(fmt_dur "${f_secs}")" \
      "$(fmt_delta "${delta_secs}" "${b_secs}")"
    # Track overall bounds.
    if [[ -z "${b_min_start}" || "${b_start_epoch}" -lt "${b_min_start}" ]]; then
      b_min_start="${b_start_epoch}"
    fi
    if [[ -z "${b_max_end}" || "${b_end_epoch}" -gt "${b_max_end}" ]]; then
      b_max_end="${b_end_epoch}"
    fi
    if [[ -z "${f_min_start}" || "${f_start_epoch}" -lt "${f_min_start}" ]]; then
      f_min_start="${f_start_epoch}"
    fi
    if [[ -z "${f_max_end}" || "${f_end_epoch}" -gt "${f_max_end}" ]]; then
      f_max_end="${f_end_epoch}"
    fi
  done < <(jq -nr --argjson b "${baseline_json}" --argjson f "${fixed_json}" '
    $b.jobs[] as $bj
    | $f.jobs[]
    | select(.name == $bj.name)
    | [$bj.name, $bj.startedAt, $bj.completedAt, .startedAt, .completedAt]
    | @tsv
  ')

  if [[ -n "${b_min_start}" && -n "${b_max_end}" \
     && -n "${f_min_start}" && -n "${f_max_end}" ]]; then
    local b_wall f_wall delta_wall
    b_wall=$(( b_max_end - b_min_start ))
    f_wall=$(( f_max_end - f_min_start ))
    delta_wall=$(( f_wall - b_wall ))
    printf '| **total wall** | **%s** | **%s** | **%s** |\n' \
      "$(fmt_dur "${b_wall}")" \
      "$(fmt_dur "${f_wall}")" \
      "$(fmt_delta "${delta_wall}" "${b_wall}")"
  fi
}

main() {
  local repo="" baseline="" fixed="" output=""
  while (( $# > 0 )); do
    case "$1" in
      --repo) repo="${2:-}"; shift 2 ;;
      --baseline) baseline="${2:-}"; shift 2 ;;
      --fixed) fixed="${2:-}"; shift 2 ;;
      --output) output="${2:-}"; shift 2 ;;
      -h|--help) usage; return 0 ;;
      *) echo "unknown arg: $1" >&2; usage; return 2 ;;
    esac
  done
  if [[ -z "${repo}" ]]; then
    echo "missing --repo" >&2
    usage
    return 2
  fi
  if [[ -z "${baseline}" ]]; then
    echo "missing --baseline" >&2
    usage
    return 2
  fi
  if [[ -z "${fixed}" ]]; then
    echo "missing --fixed" >&2
    usage
    return 2
  fi

  local baseline_json fixed_json
  baseline_json="$(fetch_run_jobs "${repo}" "${baseline}")" || return 1
  fixed_json="$(fetch_run_jobs "${repo}" "${fixed}")" || return 1

  local incomplete
  incomplete="$(incomplete_job_names "${baseline_json}" "${fixed_json}")"
  if [[ -n "${incomplete}" ]]; then
    echo "in-progress or incomplete jobs detected (missing startedAt or completedAt):" >&2
    echo "${incomplete}" >&2
    return 2
  fi

  local table
  table="$(build_table "${baseline_json}" "${fixed_json}")"

  if [[ -n "${output}" ]]; then
    printf '%s\n' "${table}" > "${output}"
    echo "wrote table to ${output}" >&2
  else
    printf '%s\n' "${table}"
  fi
}

main "$@"
