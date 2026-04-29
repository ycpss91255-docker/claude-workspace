# Changelog

All notable changes to claude-workspace are documented here. This file
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- `release` slash command rewritten to match the actual
  ycpss91255-docker repo convention. Previously the skill said "tag and
  push" only; the real flow used by v0.12.0 → v0.12.3 is **branch →
  bump `.version` + CHANGELOG → chore PR → CI → merge → annotated tag
  on the merge commit → push tag → wait tag-triggered workflows**. The
  new doc has 9 numbered steps, RC failure handling (never re-tag the
  same RC), and points at `/batch-template-upgrade` for downstream
  propagation. PATCH releases (vX.Y.PATCH) skip RC; MINOR / MAJOR keep
  the RC dance via `-rcN` suffix on the same chore-PR pipeline.
- `CLAUDE.md` Bash parser-limit cheat sheet: new row covering
  `docker run ... bash -c '<長 inline 字串>'` (multi-line shell logic
  wrapped in quotes triggers `Unhandled node type: string` regardless
  of allowlist). Canonical replacement: write the body to `/tmp/<name>.sh`
  via the Write tool, then `docker run -v "$PWD":/source ... bash
  /source/<rel-path>/<name>.sh`. Generalises the existing rule for
  `gh ... --body "$(cat)"` — long quoted bodies always extract to
  files, never inline.
- `CLAUDE.md` `gh ... --body "$(cat path)"` row strengthened to also
  cover `gh ... --body-file - <<'EOF'` (heredoc-into-stdin), which
  trips either `Unhandled node type: string` or `Contains zsh =cmd
  equals expansion` depending on body content. Canonical fix is the
  same: write body to `/tmp/<name>.md` via Write, then
  `gh ... --body-file /tmp/<name>.md`. The single-row update keeps the
  cheat sheet consolidated rather than splitting into two near-duplicate
  entries.
- `CLAUDE.md` cheat sheet adds a row for `gh pr merge N --repo X` from
  a foreign cwd. Claude Code's built-in state-changing safety check
  fires regardless of allowlist or `autoAllowBashIfSandboxed` — this is
  intentional, not a parser limit, and not bypassable via `-R X` short
  form or `(cd path && ...)` subshell (the `docker` monorepo carries
  `ycpss91255-docker/template` only as a git subtree, not a separate
  checkout, so there's no template-rooted cwd to cd into). Captured to
  CLAUDE.md so Claude expects the prompt and accepts it instead of
  retrying alternative shapes.
- `remind_use_body_file.sh` hook extended to also detect
  `gh ... --body-file -` (stdin variant, typically `--body-file - <<EOF`).
  Previously the hook only caught `--body|--comment "$(cat path)"`,
  letting the heredoc-stdin variant slip through and re-prompt the
  user (observed during the v0.12.2 / v0.12.3 release cycle where
  release-PR creation kept hitting `Unhandled node type: string` or
  `Contains zsh =cmd equals expansion` despite the existing rule).
  Detection regex looks for `--body-file -` terminated by whitespace,
  end-of-string, or shell operator; silent on `--body-file <real-path>`.
  3 new bats specs (FIRE on heredoc, FIRE on bare `-`, SILENT on a
  path containing `-`).

### Added
- New PostToolUse hook `remind_test_tools_smoke_sync.sh` fires on Edit
  / Write to `dockerfile/Dockerfile.test-tools` and prints the alpine
  packages on the final-stage `apk add --no-cache` line alongside the
  tools verified by the sibling `release-test-tools.yaml` smoke step,
  so a missing `--version` / `--help` check shows up as a visible
  diff before commit. Surfaced as a recurring pain during #168: each
  Dockerfile rebase that added a new package (parallel → git →
  git-subtree → grep / coreutils) needed a matching smoke-step row,
  and 3 of 4 were caught reactively (CI fail) instead of proactively.
  The hook does NOT enforce a strict 1:1 mapping — packages without a
  single probe binary (ca-certificates, coreutils) are intentionally
  left for human judgment. Includes 7 bats specs covering fire /
  silent / final-stage-only parsing paths; registered in
  `.claude/settings.json` PostToolUse next to `remind_tdd_categories.sh`.
- New helper script `.claude/scripts/check-template-versions.sh` —
  read-only HTTPS fetch of `template/.version` from main for every
  downstream repo (17 repos in `DEFAULT_REPOS`, mirroring
  `batch-template-upgrade.sh`). Used during release verification to
  confirm `/batch-template-upgrade <vX.Y.Z>` PRs have all merged.
  Replaces the ad-hoc `for repo in ...; do curl ...; done` pattern that
  trips Claude Code's bash AST parser (`Unhandled node type: string`).
  Supports `--only` / `--skip` filters and `--expect <vX.Y.Z>` (exit 1
  on any mismatch). 7 bats specs stub `curl` via PATH for offline
  testing; registered in `.claude/settings.local.json` allow list and
  documented in `doc/test/TEST.md`.
- Hook test infrastructure relocated to `.claude/test/` so the workspace
  root is no longer polluted with Claude-only files. `Dockerfile.test`
  → `.claude/test/Dockerfile`; root `Makefile` → `.claude/test/Makefile`.
  Build context is repo root (so `COPY .claude/hooks/` paths still
  resolve); invocation becomes `make -C .claude/test <target>`. CI
  workflow `.github/workflows/test.yaml` gains a job-level
  `working-directory: .claude/test`. Reason: `Dockerfile.test` is purely
  meta-repo test infra (only COPYs `.claude/hooks/` + `.claude/scripts/`,
  zero overlap with downstream repo Dockerfiles), so it belongs inside
  `.claude/`. `.hadolint.yaml` comment + README + CLAUDE.md tree +
  TEST.md commands all updated to match.

### Added
- Three new hooks:
  - `check_changelog_drift.sh` (PreToolUse Bash) — flags `git commit`
    when staged code/config files are not accompanied by a
    `doc/changelog/CHANGELOG.md` update.
  - `check_no_ai_attribution.sh` (PostToolUse Edit/Write) — scans
    touched files for `Co-Authored-By: Claude` / `Generated with Claude
    Code` boilerplate.
  - `remind_no_ai_attribution.sh` (PreToolUse Bash) — flags inline
    attribution markers embedded in `git commit -m` / `gh pr create
    --body` / similar commands.
- Hook test infrastructure under `.claude/hooks/test/`:
  - `lib/test_helper.bash` shared helpers (bats-support / bats-assert,
    `mktemp_repo`, `assert_message_contains`, `assert_silent`).
  - 53 smoke tests across 10 specs (one per hook).
  - 4 integration tests in `chain_spec.bats` covering multi-hook
    scenarios.
- `Dockerfile.test` (bats 1.11 + shellcheck on Alpine) and `Makefile`
  with `build` / `test` / `lint` / `hadolint` / `check` targets — all
  validation runs inside Docker per CLAUDE.md「驗證一律走 Docker」.
- `.github/workflows/test.yaml` — GitHub Actions CI running
  shellcheck + Hadolint + bats on every PR and push to `main`.
- `doc/test/TEST.md` test catalog (single source of truth) and this
  CHANGELOG.
- `/issue-check` slash command (`.claude/commands/issue-check.md`):
  scans open issues across the `ycpss91255-docker` org and groups them
  by actionability (進行中 / 可 merge / 卡住 / 停滯 / 待分類 / 孤兒).
  Read-only; output in Traditional Chinese.
- `/batch-template-upgrade` slash command + implementation script and
  PR body template:
  - `.claude/commands/batch-template-upgrade.md` — workflow doc.
  - `.claude/scripts/batch-template-upgrade.sh` — parameterized impl
    (`<version>` + `--why-file` / `--why` / `--issue` / `--dry-run` /
    `--only` / `--skip` / `--continue-on-error`). Iterates 17
    hardcoded `DEFAULT_REPOS`, fetches `main` via HTTPS, runs
    `./template/upgrade.sh + ./template/init.sh`, opens one PR per
    repo. Designed for the main session (subagent sandbox blocks
    `git push`).
  - `.claude/scripts/batch-template-pr-body.template.md` — PR body
    template rendered via `envsubst` with `${VERSION}` / `${WHY}` /
    `${ISSUE_LINE}`.

### Changed
- `check_test_md_drift.sh` now resolves drift in pure bash; the
  previous gawk-only `match($0, /re/, arr)` 3-arg form silently
  mis-ran under mawk / POSIX awk.
- `check_no_emoji.sh`, `check_no_coverage_excl.sh`,
  `check_no_ai_attribution.sh` skip `.claude/hooks/test/*` so test
  fixtures can legitimately contain the forbidden patterns.
- `check_no_ai_attribution.sh` additionally skips meta-doc files
  (`CLAUDE.md`, `.claude/commands/*.md`, `.claude/skills/*/SKILL.md`,
  `doc/test/TEST.md`, `doc/changelog/CHANGELOG.md`) that legitimately
  quote the rules they enforce.
- `.claude/commands/*.md`: replaced hard-coded
  `/home/yunchien/Desktop/docker` paths with `${CLAUDE_PROJECT_DIR}`
  for cross-machine portability; `pr.md` no longer recommends adding
  AI attribution lines (contradicted CLAUDE.md).
- `CLAUDE.md`: git-config example uses `<your-name>` /
  `<your-email>` placeholders; the `.github/` directory in the
  workspace tree is now `org-profile/` (local checkout) so
  claude-workspace can own `.github/workflows/` for its own CI.
- Two PreToolUse Bash hooks to nudge Claude away from
  parser-failing command shapes:
  - `remind_no_heredoc_redirect.sh` — fires on `cat <<EOF > path`
    redirects (which trigger Claude Code's `Unhandled node type:
    file_redirect` warning); reminds to use the Write tool instead.
  - `remind_use_body_file.sh` — fires on `gh ... --body|--comment
    "$(cat path)"` (which triggers `Unhandled node type: string`);
    reminds to use `--body-file <path>` (gh CLI native).
- 16 new smoke tests covering the two hooks (10 + 6), bumping the
  total from 57 to 73 (69 smoke + 4 integration). The heredoc hook
  anchors `cat` to a command-start position (`^` or after `;|&|`)
  so descriptions of the pattern in quoted strings (e.g. a git
  commit message documenting the rule) do not trigger.
- `CLAUDE.md` 「## Bash 命令寫法的 parser 限制」 section: catalogs
  six command patterns that fall back to a user prompt regardless of
  allowlist / `autoAllowBashIfSandboxed` (heredoc-to-file, `$(cat
  path)`, complex for-loops with `${var%:*}`, Monitor inline bodies,
  `cd path && git ...`, `[[ a != b ]]` inside Monitor) along with
  their canonical replacements.
- `CLAUDE.md` 「## 主動優化建議」 adds a "任務結束時主動列 skill 化候選"
  sub-section: at PR-merge / task wrap-up, surface ad-hoc scripts in
  `/tmp` or repeated complex bash pipelines as skill candidates so they
  don't get lost or rewritten next time.
- `wait-pr-ci` SKILL.md: example loop uses `case` patterns instead of
  `[[ a != b ]]`. The Monitor tool's eval wrapper escapes `!` to `\!`
  ("history-expansion guard"), which broke the `!=` comparison with
  `conditional binary operator expected`. `set +H` did not save it.
- `wait-pr-ci` skill: Monitor body extracted into permanent scripts
  so the inline loop disappears. Two siblings sharing the same CLI
  shape (`--repo`, `--check-filter`, `--interval`,
  `--max-iterations`):
  - `.claude/scripts/wait-pr-ci.sh` — PR-scoped (`gh pr view --json
    statusCheckRollup`); `--prs <CSV>`; supports template /
    container / org-profile check filters. Closes #4.
  - `.claude/scripts/wait-tag-ci.sh` — tag/branch-scoped (`gh run
    list --branch <ref>`); `--branch <tag-or-branch>`,
    `--limit <N>`. Used after `git push origin <tag>` to wait on
    `on: push: tags:` workflows.
  SKILL.md reframed to cover both flavours; documents per-repo
  filter table, anti-patterns, and merge/release pairing.
- 21 new smoke tests across `wait_pr_ci_spec.bats` (11) and
  `wait_tag_ci_spec.bats` (10), mocking `gh` via PATH stub.
  Total bumps from 73 → 94 (90 smoke + 4 integration).
  `Dockerfile.test` now COPYs `.claude/scripts/` and `make lint`
  extends shellcheck to `.claude/scripts/*.sh`.
- `CLAUDE.md` 「## 跨 repo 批次 mutation 規範」 new section: any
  state change (commit/push/`git reset --hard`/`git branch -D`/issue
  or PR close/merge) over ≥2 repos must go through a documented
  slash command or `.claude/scripts/` script — no ad-hoc
  for-loops. Reason: a 15-iteration loop fires the user-confirm
  prompt 15 times → yes-fatigue → effectively bypasses the `ask`
  rules. Read-only loops (e.g. `gh pr view --json state` across
  repos) remain allowed.
- `CLAUDE.md` Bash parser-limit cheat sheet: Monitor row now points
  to both `wait-pr-ci.sh` (PR) and `wait-tag-ci.sh` (tag/branch)
  as the canonical replacements for inline Monitor poll loops.
- `auto_allow_rm_in_workspace.sh` (PreToolUse Bash) — first hook
  using `hookSpecificOutput.permissionDecision` instead of a
  `systemMessage` reminder. Auto-allows `rm` invocations whose
  path arguments are all confined to `${CLAUDE_PROJECT_DIR}` or
  `/tmp`; anything outside falls through silently so the existing
  `Bash(rm:*)` ask rule still catches `rm /etc/passwd` etc.
  Static-resolution guards: rejects `$` / backtick / `~` / `..`
  expansions, command chains (`&&` / `||` / `;` / `|`), and
  outside-zone absolute paths. Eliminates yes-fatigue on routine
  workspace cleanups while keeping the catch-all safety net.
- 18 smoke tests in `test/smoke/auto_allow_rm_in_workspace_spec.bats`
  covering ALLOW / SILENT decisions across relative paths, /tmp,
  workspace absolutes, flags, `--` separator, expansion guards,
  traversal, chains, pipes, and defensive fallbacks.
  `test_helper.bash` gains `assert_permission_decision <expected>`
  for asserting `hookSpecificOutput.permissionDecision`. TEST.md
  Smoke-spec preamble reframed for three behaviours
  (FIRE / ALLOW / SILENT). Total: 94 → 112.
- `CLAUDE.md` Bash parser-limit cheat sheet: new row covering
  `until ... $(cat <pidfile>) ...; do sleep N; done` background-task
  poll loops (triggers `Contains command_substitution`). Canonical
  replacement is the `Bash` tool's `run_in_background` parameter
  (runtime auto-notifies on completion); GitHub CI keeps using
  `wait-pr-ci.sh` / `wait-tag-ci.sh`. Avoids yes-fatigue when
  Claude waits on a long-running local process it just spawned.
