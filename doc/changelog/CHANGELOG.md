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
- `wait-pr-ci` SKILL.md: example loop uses `case` patterns instead of
  `[[ a != b ]]`. The Monitor tool's eval wrapper escapes `!` to `\!`
  ("history-expansion guard"), which broke the `!=` comparison with
  `conditional binary operator expected`. `set +H` did not save it.
  A separate follow-up issue tracks extracting the Monitor body into
  a permanent script to also avoid the `Contains simple_expansion`
  warning on parameter expansions.
