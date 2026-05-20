# ADR-00000007: Documented Slash Commands / Skills Take Precedence Over Ad-Hoc Invocations

- **Date:** 2026-05-20
- **Status:** Accepted

## Context

The repo accumulates `.claude/commands/*.md` (slash commands like
`/release`, `/pr`, `/batch-template-upgrade`, `/issue-fix`,
`/new-repo`, `/doc-sync`, `/safe-delete`, `/verify`) and
`.claude/skills/*/SKILL.md` (e.g. `wait-pr-ci`, `gh-artifact-format`,
`semver-bump`) as multi-step workflows mature. Each documented
entry encodes the full sequence: pre-flight checks, the main
operation, and post-flight follow-ups (CHANGELOG promotion,
`.version` bump, init.sh resync, etc.).

The problem these address: contributors -- human and agent -- can
*almost* perform the workflow ad-hoc but miss the periphery.
Issue #36 was the trigger:

- `template v0.18.0` was released by invoking `git tag v0.18.0`
  directly, skipping `/release`'s chore-PR step.
- `/release`'s chore-PR step bumps `.version` and promotes the
  `[Unreleased]` CHANGELOG entries to `[v0.18.0]`.
- Skipping it left `.version` at the old value and `[Unreleased]`
  un-promoted.
- Every downstream `make upgrade-check` permanently reported
  "upgrade available" because the version pin lagged the actual
  released tag.

Hook layer alone can't catch these workflows -- the rule isn't
"don't run `git tag`", it's "run `git tag` only via `/release`,
which also bumps `.version`". The discipline must be: prefer
the documented entry; deviate only with explicit reason.

## Decision

**Documented slash commands and skills take precedence over
ad-hoc git / gh / make / script invocations** for any multi-step
mutating flow they cover. Concretely:

| Operation | Canonical entry |
|---|---|
| Tag a release | `/release` (chore-PR + tag + `wait-tag-ci`) |
| Open a PR | `/pr` (branch + commit + push + create + `wait-pr-ci`) |
| Batch upgrade downstream `.base/` | `/batch-template-upgrade` |
| Fix an open issue | `/issue-fix <repo> [<num>\|all]` |
| Create a new repo | `/new-repo` |
| Pre-commit doc check | `/doc-sync` or `/verify` |
| Wait for PR CI | `wait-pr-ci` skill |
| Wait for non-CI state | `wait-gh-state` skill |
| Tag bump (X/Y/Z + RC) | `semver-bump` skill + `release-tag.sh` |

**Exceptions** (ad-hoc is fine):

- **Trivial one-off reads**: `gh pr view`, `git log -1`,
  `gh issue view`, plain `Read` -- no state change, no risk
  of skipping a follow-up.
- **Explicit user request**: when the user says "run this raw
  step, don't go through `/release`", the agent obeys but
  records "skipped /release because user asked" in the message
  so the conversation log shows the deviation.

**Enforcement** is layered:

- `enforce_semver_tag_via_script.sh` PreToolUse hook BLOCKs
  raw `git tag v*` / `git push.*v[0-9]`, forcing the caller
  through `.claude/scripts/release-tag.sh` (which
  `/release` invokes).
- Hooks for the other multi-step flows are intentionally
  *advisory* (reminders, not blocks). The blocking hook is
  reserved for cases where slipping the workflow has caused
  recurring breakage (release versioning).

## Alternatives

Three alternatives were considered and rejected:

1. **Treat slash commands as optional convenience; allow ad-hoc
   freely.** Rejected: issue #36 is the failure mode. Without a
   convention, the slip is silent until downstream consequences
   surface, and by then the fix is more expensive.

2. **Make every slash command a blocking hook on its underlying
   tools.** Rejected: over-enforcement. Many slash-command
   workflows have legitimate ad-hoc variants for exotic cases
   (e.g. `gh pr create` direct usage for a doc-only PR with no
   CI to wait on). Blocking all ad-hoc creates friction without
   commensurate safety.

3. **Document the convention but rely on memory / convention
   alone.** Rejected: the agent's memory is not persistent across
   sessions. A convention recorded only in chat doesn't survive
   a `/compact` or a session boundary. CLAUDE.md + this ADR are
   the durable record.

## Consequences

- **`/release` is the only path to a tag.** Hook enforces.
  The chore-PR step (`.version` bump + `[Unreleased]`
  promotion) cannot be skipped.

- **Slash command bodies are contracts.** Each command's
  `.md` body lists steps verbatim; future drift between
  steps and reality is the command's responsibility to
  reconcile. New steps land in the command body, not in
  Slack DMs or one-off notes.

- **Skills are referenced, not inlined.** `wait-pr-ci` is
  the canonical "wait for CI" recipe. Re-inventing it in a
  Monitor body (with attendant parser-fallback risks) is an
  anti-pattern.

- **Deviation must be logged.** When the user explicitly
  asks for an ad-hoc step that bypasses a slash command,
  the agent records the deviation in its message ("skipped
  `/release` chore-PR step because user requested").

- **New workflows get a slash command.** When the agent
  notices an `n>=3` recurring multi-step pattern, the
  "main-task-end skill-ification proposal" convention from
  CLAUDE.md kicks in: propose a slash command + script
  instead of repeating the ad-hoc steps.

## References

- Issue ycpss91255-docker/docker_harness#119 (this ADR's
  tracking issue; Tier 1 of #116).
- Issue ycpss91255-docker/docker_harness#36 (the
  `template v0.18.0` / `v0.18.1` versioning incident).
- `.claude/hooks/enforce_semver_tag_via_script.sh` -- the
  one blocking enforcement.
- `.claude/commands/release.md`,
  `.claude/commands/pr.md`,
  `.claude/commands/batch-template-upgrade.md`,
  `.claude/commands/issue-fix.md`,
  `.claude/skills/wait-pr-ci/SKILL.md`,
  `.claude/skills/semver-bump/SKILL.md` -- the canonical
  entries.
