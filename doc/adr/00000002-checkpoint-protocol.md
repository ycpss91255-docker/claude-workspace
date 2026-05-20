# ADR-00000002: /tmp Checkpoint Protocol for E2 Enforcement Hooks

- **Date:** 2026-05-20
- **Status:** Accepted

## Context

A subset of `.claude/hooks/` (the "E2" tier in CLAUDE.md issue #116
parlance) needs to gate commands that have a documented canonical path
the agent should be taking instead. Examples staged for Tier 2:

- `enforce_make_first_upgrade.sh` — block raw `./.base/upgrade.sh`,
  point at `make -f Makefile.ci upgrade`.
- `enforce_batch_via_script.sh` — block ad-hoc cross-repo for-loops,
  point at `.claude/scripts/batch-*.sh`.
- `enforce_worktree_for_branch.sh` — block `git checkout -B` in the
  main checkout, point at `git worktree add`.
- `enforce_slash_command_first.sh` — block raw `gh release create` /
  `gh pr merge --auto` patterns covered by a slash command.

The naive choice — return `permissionDecision: deny` with a long
`permissionDecisionReason` and call it done — produces two failure
modes in practice:

1. **No clean re-entry.** The agent reads the deny reason, possibly
   adjusts, then re-issues the command. The hook fires again, prints
   the same long reason again, and burns context. Worse, the agent
   may try variations (different flag order, different wrapper script)
   that still hit the deny, looping.
2. **No user-controlled override.** Sometimes the agent's command is
   correct and the hook is wrong (e.g. the canonical path is broken,
   or the agent has context the hook lacks). With pure deny + reason,
   the only escape is editing `.claude/settings.json` to remove the
   hook entry, which is heavy.

What the four hooks need is a **checkpoint** abstraction: deny the
first attempt, surface the rationale + canonical path + a one-line
ack command, then allow the second attempt of the same command to
proceed silently once the user touches the ack file. The state lives
in `$TMPDIR/claude-checkpoint-<slug>-<session>-<hash>.{md,ack}` —
ephemeral (cleared on machine reboot), session-scoped (different
sessions don't share acks), and command-scoped (different commands
get different checkpoints).

The companion piece is `auto_allow_touch_ack.sh`, a PreToolUse hook
that programmatically allows `touch` of paths matching the ack glob.
Without it, every ack would land in the generic `Bash(touch:*)` ask
flow, defeating the one-click design.

## Decision

Adopt a five-section markdown checkpoint format, rendered by a
shared helper module `.claude/scripts/lib/checkpoint.sh`, plus a
matching `auto_allow_touch_ack.sh` PreToolUse Bash hook that
auto-allows the ack `touch`.

**Checkpoint shape:**

```markdown
# Checkpoint: <hook_slug>

## 1. Attempted
<verbatim command>

## 2. Why gated
<one-paragraph reason from the hook>

## 3. Canonical path
<documented entry the agent should use instead>

## 4. Acknowledge
touch $TMPDIR/claude-checkpoint-<slug>-<session>-<hash>.ack

## 5. Re-run
<re-issue the original command after ack>
```

**Helper API:**

- `write_checkpoint <slug> <cmd> <reason> <canonical> <ack_hint>` —
  renders the markdown file, echoes the absolute path.
- `is_acked <slug> <cmd>` — returns 0 (and echoes the ack path) if
  the matching ack exists, 1 otherwise. Hooks call this at the top
  of `main()` to short-circuit.

**Ack file naming:**
`$TMPDIR/claude-checkpoint-<hook_slug>-<session_id>-<cmd_hash>.ack`

- `<hook_slug>` — short identifier per hook (`make-upgrade`,
  `batch-script`, `worktree-branch`, `slash-first`).
- `<session_id>` — `$CLAUDE_SESSION_ID` if set, else `nosession`.
  Keeps unrelated sessions from sharing acks.
- `<cmd_hash>` — first 16 hex chars of `sha256(cmd)`. Different
  commands → different hashes; identical commands → same hash
  (idempotent lookup).

**Auto-allow guard rails** (`auto_allow_touch_ack.sh`):

- First token must be exactly `touch`.
- No `&&` / `||` / `;` / `|` chains.
- Exactly one path argument.
- No `..` segments.
- Path matches `^(/tmp|\$TMPDIR)/claude-checkpoint-[A-Za-z0-9_-]+\.ack$`.

Anything else falls through silently so the normal ask rule applies.

## Alternatives

Three alternatives were considered and rejected:

1. **Raw deny + long `permissionDecisionReason`.** Rejected: no
   clean re-entry (the agent loops on the same deny), and no user
   override short of editing `settings.json`. The point of the
   checkpoint is to acknowledge once and proceed; raw deny has no
   "acknowledge" affordance.

2. **State file in `.claude/state/<hook>.json`.** Rejected: lives
   in the repo, so acks would be checkpointed into git history,
   leak across sessions / machines, and require explicit cleanup.
   The `/tmp` location is the right scope — session-ephemeral and
   machine-local, which matches the acknowledgment semantics (this
   user, this session, this command).

3. **Always-prompt via `permissionDecision: ask`.** Rejected:
   defeats the gate. The hook only fires because the command needs
   a deliberate "are you sure" beat, and `ask` would let the agent
   one-click through every time. The checkpoint forces an out-of-
   band action (`touch <ack>`) that the user has to type, which
   makes ignoring the gate require more friction than honouring it.

## Consequences

- **New file under `$TMPDIR` per gated command per session.** Cheap
  on disk; ephemeral. No cleanup needed — `/tmp` gets wiped on
  reboot, and old checkpoints from earlier sessions are inert
  (the cmd hash will only match if the user issues the identical
  command from a session with the same `CLAUDE_SESSION_ID`, which
  is monotonically unique per session start).
- **One new PreToolUse hook in the Bash matcher chain.** Adds a
  small cost (one `cat | jq | awk` invocation) per Bash call;
  short-circuits on non-`touch` first token, so the overhead is
  measured in microseconds.
- **Four downstream E2 hooks gain a shared deny / ack contract.**
  They source `lib/checkpoint.sh`, call `is_acked` at the top of
  `main()`, render via `write_checkpoint` on miss, and return
  `deny` with the path embedded in the reason. The lib enforces
  identical wording across the four; no drift.
- **Documentation pointer.** `CLAUDE.md` "Process discipline"
  section gains a one-line link to this ADR so future hooks
  adopting the pattern know where the canonical shape lives.
- **Future hooks reusing the same pattern.** This ADR's helper is
  intentionally agnostic to which hook is calling it; any new
  enforce_* hook follows the same `(slug, cmd, reason, canonical,
  ack_hint)` shape. No copy-paste between hooks.

## References

- Issue ycpss91255-docker/docker_harness#117 (this ADR's tracking
  issue; Tier 0 of #116).
- Issue ycpss91255-docker/docker_harness#116 (umbrella; lists the
  four Tier 2 hooks that consume this foundation).
- `.claude/hooks/auto_allow_rm_in_workspace.sh` — closest existing
  pattern for "auto-allow by path glob".
- `.claude/hooks/enforce_gh_body_file.sh` — `deny` + JSON output
  shape mirrored by the future E2 hooks.
- `.claude/scripts/lib/checkpoint.sh` — the helper module.
- `.claude/hooks/auto_allow_touch_ack.sh` — the companion
  PreToolUse hook.
