#!/usr/bin/env bash
# remind_no_chinese_in_git_artifacts.sh — Claude Code PreToolUse hook
# (matcher: Bash, blocking).
#
# Purpose: keep git/GitHub artifacts (commit messages, PR + issue titles
# and bodies, comments) in English. README*.md and i18n files are the
# only places where CJK content is allowed; everything else must be
# ASCII/standard-English typography so commit history, PRs, and issues
# stay searchable, machine-readable, and reviewer-portable.
#
# Triggers (any one of these subcommands):
#   - git commit  with -m / --message / -F / --file
#   - gh pr   create | edit | comment   with --title / --body / --body-file
#   - gh issue create | edit | close | comment   with --title / --body / --body-file / --comment
#
# Detection ranges (each fires a deny):
#   U+4E00-U+9FFF   CJK Unified Ideographs              中文
#   U+3400-U+4DBF   CJK Ext-A                           rare ideographs
#   U+3000-U+303F   CJK Symbols & Punctuation           「」『』、。
#   U+FF00-U+FFEF   Halfwidth & Fullwidth Forms         ，！？fullwidth digits/letters
#
# Allowed (English typography uses these too):
#   U+2013/U+2014   en-dash / em-dash
#   U+2018-U+201D   smart quotes
#   U+2026          ellipsis
#
# Action: returns hookSpecificOutput.permissionDecision = "deny" with a
# reason naming the offending character + its location, so Claude rewrites
# in English on the spot and no force-push / amend is needed afterwards.
#
# File-arg handling: -F / --file / --body-file values are read from disk
# and scanned. Path-based skip — i18n and README*.md files exempt:
#   *README*.md, *.zh-TW.md, *.zh-CN.md, *.ja.md, *.ko.md
#   *i18n*, *.po, *.pot, *.mo

set -uo pipefail

# _scan_text <text> — print "<lineno>:<char>:<snippet>" + exit 1 on first
# disallowed CJK / fullwidth char in <text>; print nothing + exit 0 if
# clean. Text passed via argv (not stdin) because heredoc-supplied python
# programs consume stdin themselves.
_scan_text() {
  python3 -c '
import re, sys
PATTERN = re.compile(
    "["
    "一-鿿"   # CJK Unified Ideographs
    "㐀-䶿"   # CJK Ext-A
    "　-〿"   # CJK Symbols & Punctuation
    "＀-￯"   # Halfwidth/Fullwidth Forms
    "]"
)
text = sys.argv[1]
lines = text.splitlines() or [text]
for lineno, line in enumerate(lines, 1):
    m = PATTERN.search(line)
    if m:
        snippet = line.strip()[:80]
        print(f"{lineno}:{m.group(0)}:{snippet}")
        sys.exit(1)
sys.exit(0)
' "$1" 2>/dev/null
}

# _scan_file <path> — same output shape as _scan_text but reads <path>.
_scan_file() {
  python3 -c '
import re, sys
PATTERN = re.compile(
    "["
    "一-鿿"
    "㐀-䶿"
    "　-〿"
    "＀-￯"
    "]"
)
path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for lineno, line in enumerate(f, 1):
            m = PATTERN.search(line)
            if m:
                snippet = line.rstrip()[:80]
                print(f"{lineno}:{m.group(0)}:{snippet}")
                sys.exit(1)
except OSError:
    pass
sys.exit(0)
' "$1" 2>/dev/null
}

# _is_exempt_path <path> — return 0 if README*-style or i18n / locale.
_is_exempt_path() {
  case "$1" in
    *README*.md|*.zh-TW.md|*.zh-CN.md|*.ja.md|*.ko.md) return 0 ;;
    *i18n*|*.po|*.pot|*.mo) return 0 ;;
  esac
  return 1
}

# _extract_file_args <cmd> — print, one per line, every path passed via
# -F / --file / --body-file in the command. Uses Python shlex for
# quote-aware parsing.
_extract_file_args() {
  python3 -c '
import shlex, sys
cmd = sys.argv[1]
try:
    tokens = shlex.split(cmd)
except ValueError:
    sys.exit(0)
flag_with_value = {"-F", "--file", "--body-file"}
i = 0
while i < len(tokens):
    t = tokens[i]
    if t in flag_with_value and i + 1 < len(tokens):
        print(tokens[i + 1])
        i += 2
        continue
    if "=" in t:
        flag, _, val = t.partition("=")
        if flag in flag_with_value:
            print(val)
    i += 1
' "$1" 2>/dev/null
}

# _is_target_command <cmd> — return 0 if cmd looks like one we should
# enforce: git commit, gh pr (create|edit|comment), gh issue
# (create|edit|close|comment).
_is_target_command() {
  local cmd="$1"
  if printf '%s' "${cmd}" | grep -qE '(^|[[:space:]&|;])git[[:space:]]+commit([[:space:]]|$)'; then
    return 0
  fi
  if printf '%s' "${cmd}" | grep -qE '(^|[[:space:]&|;])gh[[:space:]]+pr[[:space:]]+(create|edit|comment)([[:space:]]|$)'; then
    return 0
  fi
  if printf '%s' "${cmd}" | grep -qE '(^|[[:space:]&|;])gh[[:space:]]+issue[[:space:]]+(create|edit|close|comment)([[:space:]]|$)'; then
    return 0
  fi
  return 1
}

main() {
  local input cmd
  input="$(cat)"
  cmd="$(printf '%s' "${input}" | jq -r '.tool_input.command // empty' 2>/dev/null)"

  [[ -z "${cmd}" ]] && return 0

  _is_target_command "${cmd}" || return 0

  # 1. Scan the inline command string itself — covers -m "..." / --body "..." / --title "..."
  local hit
  hit="$(_scan_text "${cmd}")"

  # 2. Scan referenced files (-F / --file / --body-file). Skip exempt paths.
  if [[ -z "${hit}" ]]; then
    local file_path file_hit
    while IFS= read -r file_path; do
      [[ -z "${file_path}" ]] && continue
      _is_exempt_path "${file_path}" && continue
      [[ -f "${file_path}" ]] || continue
      file_hit="$(_scan_file "${file_path}")"
      if [[ -n "${file_hit}" ]]; then
        hit="${file_path}:${file_hit}"
        break
      fi
    done < <(_extract_file_args "${cmd}")
  fi

  [[ -z "${hit}" ]] && return 0

  local reason
  reason="CJK or fullwidth character detected in git/GitHub artifact (${hit}). CLAUDE.md i18n rule: only README*.md and i18n files may contain Chinese; commit messages, PR + issue titles + bodies + comments must be plain English. Rewrite in ASCII / standard English typography (em-dash and smart quotes remain allowed) and retry."

  jq -n --arg r "${reason}" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $r
    }
  }'
}

main "$@"
