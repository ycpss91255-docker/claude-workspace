# Changelog

All notable changes to claude-workspace are documented here. This file
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
- `wait-pr-ci` skill: Monitor body extracted into permanent
  `.claude/scripts/wait-pr-ci.sh` so the inline loop disappears.
  Script CLI (`--repo`, `--prs <CSV>`, `--check-filter`, `--interval`,
  `--max-iterations`) supports template / container / org-profile
  check filters; SKILL.md is now a thin Monitor wrapper. Closes #4.
  Also avoids the `Contains simple_expansion` warning that hit
  parameter expansions like `${pair%:*}` in the inline form.
- 11 new smoke tests in `test/smoke/wait_pr_ci_spec.bats` (mocking
  `gh` via PATH stub). Total bumps from 73 → 84 (80 smoke + 4
  integration). `Dockerfile.test` now also COPYs `.claude/scripts/`
  and `make lint` extends shellcheck to `.claude/scripts/*.sh`.
- `CLAUDE.md` 「## 跨 repo 批次 mutation 規範」 new section: any
  state change (commit/push/`git reset --hard`/`git branch -D`/issue
  or PR close/merge) over ≥2 repos must go through a documented
  slash command or `.claude/scripts/` script — no ad-hoc
  for-loops. Reason: a 15-iteration loop fires the user-confirm
  prompt 15 times → yes-fatigue → effectively bypasses the `ask`
  rules. Read-only loops (e.g. `gh pr view --json state` across
  repos) remain allowed.
