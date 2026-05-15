#!/usr/bin/env bash
# instinct-query.sh -- query .claude/instincts.yaml for conventions
# matching a given trigger kind (and optional file path).
#
# Hooks / skills / commands call this instead of grepping CLAUDE.md
# prose. The instincts file is the machine-readable convention store
# (issue #95 pilot); CLAUDE.md keeps the narrative.
#
# Usage:
#   instinct-query.sh <kind> [path]
#   instinct-query.sh --list
#
# Examples:
#   instinct-query.sh file_edit /repo/script/foo.sh
#       -> guidance for shell-style-* instincts (glob matches *.sh)
#   instinct-query.sh git_commit
#       -> commit-title-conventional
#   instinct-query.sh gh_pr_create
#       -> pr-title-conventional + gh-body-file
#   instinct-query.sh --list
#       -> all instinct names with their trigger kinds (for skill index)
#
# Output: per matching instinct,
#   ### <name>  (trigger: <kind>[, glob=<glob>])
#   - <guidance bullet 1>
#   - <guidance bullet 2>
#   refs: <refs>           # only if refs present
#
# Exit:
#   0  one or more instincts matched (or --list ran)
#   1  no instincts matched the trigger
#   2  usage / parse error
#
# Override via env:
#   INSTINCTS_FILE  Path to instincts.yaml (default: $CLAUDE_PROJECT_DIR
#                   /.claude/instincts.yaml; falls back to <script dir>/../instincts.yaml).

set -uo pipefail

readonly DEFAULT_FILE_REL=".claude/instincts.yaml"

usage() {
  sed -n '/^# Usage:/,/^# Override/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
}

resolve_instincts_file() {
  if [[ -n "${INSTINCTS_FILE:-}" ]]; then
    printf '%s\n' "${INSTINCTS_FILE}"
    return
  fi
  if [[ -n "${CLAUDE_PROJECT_DIR:-}" && -f "${CLAUDE_PROJECT_DIR}/${DEFAULT_FILE_REL}" ]]; then
    printf '%s\n' "${CLAUDE_PROJECT_DIR}/${DEFAULT_FILE_REL}"
    return
  fi
  local self_dir
  self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  printf '%s\n' "${self_dir}/../instincts.yaml"
}

main() {
  local kind="" path=""
  local list_mode=0

  while (( $# > 0 )); do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --list) list_mode=1; shift ;;
      --*) echo "unknown arg: $1" >&2; usage; exit 2 ;;
      *)
        if [[ -z "${kind}" ]]; then
          kind="$1"
        elif [[ -z "${path}" ]]; then
          path="$1"
        else
          echo "too many positional args" >&2; usage; exit 2
        fi
        shift ;;
    esac
  done

  if (( list_mode == 0 )) && [[ -z "${kind}" ]]; then
    echo "missing <kind>" >&2
    usage
    exit 2
  fi

  local instincts_file
  instincts_file="$(resolve_instincts_file)"
  if [[ ! -f "${instincts_file}" ]]; then
    echo "instincts file not found: ${instincts_file}" >&2
    exit 2
  fi

  local parser_path
  parser_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_instinct_parser.py"
  if [[ ! -f "${parser_path}" ]]; then
    echo "instinct parser helper missing: ${parser_path}" >&2
    exit 2
  fi

  if (( list_mode )); then
    PYTHONDONTWRITEBYTECODE=1 python3 - "${parser_path}" "${instincts_file}" <<'PY'
import importlib.util
import sys

parser_path, instincts_path = sys.argv[1], sys.argv[2]

spec = importlib.util.spec_from_file_location("_instinct_parser", parser_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
parse_instincts = mod.parse_instincts

data = parse_instincts(instincts_path)

for entry in data:
    name = entry.get("name", "<unnamed>")
    trig = entry.get("trigger", {})
    kind = trig.get("kind", "?")
    glob = trig.get("glob", "")
    if glob:
        print(f"{name}  ({kind}, glob={glob})")
    else:
        print(f"{name}  ({kind})")
PY
    exit 0
  fi

  python3 - "${parser_path}" "${instincts_file}" "${kind}" "${path}" <<'PY'
import fnmatch
import importlib.util
import sys

parser_path = sys.argv[1]
instincts_path, kind, path = sys.argv[2], sys.argv[3], sys.argv[4]

spec = importlib.util.spec_from_file_location("_instinct_parser", parser_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
parse_instincts = mod.parse_instincts

data = parse_instincts(instincts_path)

def glob_match(glob: str, p: str) -> bool:
    if not glob:
        return True
    # Translate `**` into fnmatch-friendly glob: fnmatch already lets `*`
    # cross slashes when combined with full-path patterns we receive, so
    # collapsing `**/` -> `*/` keeps a single-segment matcher working
    # without needing pathlib here. Edge case: `'**/*.sh'` matches both
    # `foo.sh` (top-level) and `dir/foo.sh` (any depth) because we also
    # try the basename.
    return fnmatch.fnmatch(p, glob) or fnmatch.fnmatch(p, glob.replace("**/", "*"))

def negative_glob_match(not_glob: str, p: str) -> bool:
    if not not_glob:
        return False
    return fnmatch.fnmatch(p, not_glob)

hits = []
for entry in data:
    trig = entry.get("trigger", {})
    if trig.get("kind") != kind:
        continue
    glob = trig.get("glob", "")
    not_glob = trig.get("not_glob", "")
    if glob and path:
        if not (glob_match(glob, path) or glob_match(glob, path.split("/")[-1])):
            continue
    if not_glob and path and negative_glob_match(not_glob, path):
        continue
    hits.append(entry)

if not hits:
    sys.exit(1)

for entry in hits:
    name = entry.get("name", "<unnamed>")
    trig = entry.get("trigger", {})
    k = trig.get("kind", "?")
    glob = trig.get("glob", "")
    if glob:
        print(f"### {name}  (trigger: {k}, glob={glob})")
    else:
        print(f"### {name}  (trigger: {k})")
    for bullet in entry.get("guidance", []) or []:
        print(f"  - {bullet}")
    refs = entry.get("refs", "")
    if refs:
        print(f"  refs: {refs}")
    print()
PY
}

main "$@"
