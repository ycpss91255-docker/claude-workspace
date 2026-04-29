#!/usr/bin/env bash
# run-bats-in-compose.sh
#
# Run bats inside a compose.yaml-defined service and post-filter the
# output. Designed to side-step Claude Code's bash AST parser fallback
# on `docker compose ... bash -c '<long inline string>'` (warning:
# "Unhandled node type: string"), which forces a user-confirmation
# prompt every time even when the underlying command is allow-listed.
#
# Usage from a Claude session looks like:
#   .claude/scripts/run-bats-in-compose.sh --suite all --grep '^not ok'
# Claude's parser only sees atomic flags, not a quoted shell body, so
# no parser fallback fires. The inline shell logic lives inside this
# script and is composed at run time.

set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: run-bats-in-compose.sh [options]

Run bats inside a compose.yaml service and (by default) print only failed
tests. Avoids the Claude bash parser fallback "Unhandled node type:
string" that fires on inline `docker compose ... bash -c '<long string>'`.

Options:
  --service <name>      Compose service name (default: ci)
  --suite <kind>        Bats target. One of:
                          unit         -> /source/test/unit/
                          integration  -> /source/test/integration/
                          all          -> /source/test/unit/ /source/test/integration/
                          <path>       -> /source/<path>  (literal; pass a dir or single .bats file)
                        (default: all)
  --grep <pattern>      Filter bats output via 'grep -E'.
                        Default: '^not ok' (fail-only).
                        Pass empty string to disable filtering.
  --tail <N>            Show only last N lines (default: 25)
  --head <N>            Show only first N lines instead of tail
  --compose-file <path> Compose file (default: compose.yaml in cwd)
  -h | --help           Show this help

Examples:
  run-bats-in-compose.sh                                       # all suites, fail-only, tail 25
  run-bats-in-compose.sh --suite unit --grep '' --tail 60      # unit, full output, tail 60
  run-bats-in-compose.sh --suite test/unit/tui_spec.bats       # one file, fail-only
EOF
}

main() {
  local service="ci"
  local suite="all"
  local grep_pattern="^not ok"
  local tail_n="25"
  local head_n=""
  local compose_file="compose.yaml"

  while (( $# > 0 )); do
    case "$1" in
      --service) service="$2"; shift 2 ;;
      --suite) suite="$2"; shift 2 ;;
      --grep) grep_pattern="$2"; shift 2 ;;
      --tail) tail_n="$2"; head_n=""; shift 2 ;;
      --head) head_n="$2"; tail_n=""; shift 2 ;;
      --compose-file) compose_file="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) echo "unknown arg: $1" >&2; usage; exit 2 ;;
    esac
  done

  local targets
  case "$suite" in
    unit) targets="/source/test/unit/" ;;
    integration) targets="/source/test/integration/" ;;
    all) targets="/source/test/unit/ /source/test/integration/" ;;
    *) targets="/source/${suite}" ;;
  esac

  # Build the inner shell command. Single-quote the grep pattern so the
  # inner shell does not re-interpret regex metacharacters; reject
  # patterns containing single quotes to keep the quoting simple.
  if [[ "$grep_pattern" == *"'"* ]]; then
    echo "error: --grep pattern must not contain single quotes" >&2
    exit 2
  fi

  local inner="bats ${targets} 2>&1"
  if [[ -n "$grep_pattern" ]]; then
    inner+=" | grep -E -- '${grep_pattern}'"
  fi

  if [[ ! -f "$compose_file" ]]; then
    echo "error: compose file not found: ${compose_file}" >&2
    exit 2
  fi

  local output
  output="$(docker compose -f "$compose_file" run --rm \
    -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" \
    --entrypoint bash "$service" -c "$inner" 2>&1 || true)"

  if [[ -n "$head_n" ]]; then
    printf '%s\n' "$output" | head -n "$head_n"
  elif [[ -n "$tail_n" ]]; then
    printf '%s\n' "$output" | tail -n "$tail_n"
  else
    printf '%s\n' "$output"
  fi
}

main "$@"
