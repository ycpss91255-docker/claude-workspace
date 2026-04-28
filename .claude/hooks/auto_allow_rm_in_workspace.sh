#!/usr/bin/env bash
# auto_allow_rm_in_workspace.sh — Claude Code PreToolUse hook (matcher: Bash)
#
# Auto-allow `rm <paths>` invocations whose path arguments are all
# confined to ${CLAUDE_PROJECT_DIR} or /tmp, bypassing the catch-all
# `Bash(rm:*)` ask rule. Anything outside falls through silently so
# the normal ask rule prompts the user.
#
# Why: Bash(rm:*) in ask catches `rm /etc/passwd` and friends, but in
# day-to-day workflow most `rm` targets workspace files (build
# artifacts, /tmp scripts) — those don't need a prompt. This hook lets
# the user keep the catch-all ask without yes-fatigue on routine rm.
#
# Decision matrix:
#   - command not starting with `rm` → silent (let normal rules act)
#   - command contains `&&` / `||` / `;` / `|` → silent (chain too risky to blanket-allow)
#   - any path arg contains `$` / backtick / `~` → silent (can't statically resolve)
#   - any path arg has `..` segment → silent (path-traversal risk)
#   - any absolute path arg outside ${CLAUDE_PROJECT_DIR}/ or /tmp/ → silent
#   - all path args safe → emit permissionDecision: allow

set -uo pipefail

main() {
  local input cmd workspace
  input="$(cat)"
  cmd="$(printf '%s' "${input}" | jq -r '.tool_input.command // empty' 2>/dev/null)"

  [[ -z "${cmd}" ]] && return 0

  workspace="${CLAUDE_PROJECT_DIR:-}"
  [[ -z "${workspace}" ]] && return 0

  # First token must be exactly `rm`.
  local first_word
  first_word=$(printf '%s' "${cmd}" | awk '{print $1}')
  [[ "${first_word}" != "rm" ]] && return 0

  # Reject chains / pipes — too risky to blanket-allow.
  if printf '%s' "${cmd}" | grep -qE '[|;&]'; then
    return 0
  fi

  # Word-split args after `rm`. We've already rejected anything fancy
  # (chains, $-expansions, etc.) above, so naive whitespace split is OK.
  local -a args
  read -ra args <<< "${cmd}"
  unset 'args[0]'

  local saw_dashdash=0 arg
  for arg in "${args[@]:-}"; do
    [[ -z "${arg}" ]] && continue

    if [[ "${arg}" == "--" ]]; then
      saw_dashdash=1
      continue
    fi

    # Pre-`--`, args starting with `-` are flags.
    if (( !saw_dashdash )) && [[ "${arg}" == -* ]]; then
      continue
    fi

    # Reject anything we can't statically resolve.
    case "${arg}" in
      *'$'*|*'`'*|*'~'*) return 0 ;;
    esac

    # Reject `..` path-traversal.
    if [[ "${arg}" =~ (^|/)\.\.(/|$) ]]; then
      return 0
    fi

    # Absolute path: must be under workspace or /tmp.
    if [[ "${arg}" == /* ]]; then
      case "${arg}" in
        "${workspace}"|"${workspace}/"*) ;;
        /tmp|/tmp/*) ;;
        *) return 0 ;;
      esac
    fi
    # Relative paths: rely on cwd being inside workspace (Claude Code
    # default). If a workflow ever needs to cd outside, add an
    # explicit guard upstream.
  done

  jq -n --arg ws "${workspace}" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow",
      permissionDecisionReason: ("rm targets confined to " + $ws + " + /tmp")
    }
  }'

  return 0
}

main "$@"
