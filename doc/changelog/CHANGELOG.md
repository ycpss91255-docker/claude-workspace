# Changelog

All notable changes to claude-workspace are documented here. This file
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- `.claude/scripts/batch-pr-merge.sh` now mirrors `wait-pr-ci-batch.sh`'s
  argument contract: short `<repo>` form is auto-prefixed with the default
  owner `ycpss91255-docker`, full `<owner>/<repo>` form is accepted
  unchanged, and a `--owner <OWNER>` flag overrides the default. PR
  numbers are validated up-front (non-numeric rejects with exit 2 before
  any `gh` invocation). Previously, the next-step copy-paste block printed
  by `batch-template-upgrade.sh` worked for `wait-pr-ci-batch.sh` but
  failed across all 17 pairs for `batch-pr-merge.sh` because the latter
  required the explicit owner prefix. The next-step block now works
  verbatim for both. 14 new bats specs in
  `.claude/hooks/test/smoke/batch_pr_merge_spec.bats` covering arg
  parsing, normalization, dry-run, gh failure handling, and mixed
  success/failure batches.

### Fixed
- `.claude/settings.json` `sandbox` block now declares
  `excludedCommands: ["docker *", "make *", "./build.sh *",
  "./run.sh *", "./exec.sh *", "./stop.sh *"]`. Closes #39 — the
  long-standing conflict where the project's "all verification via
  Docker" rule was incompatible with sandbox's blocking of
  `connect(AF_UNIX, /var/run/docker.sock)`. Anthropic's official
  sandboxing docs explicitly recommend listing docker in
  `excludedCommands`; the wildcard pattern (`docker *`) follows the
  same prefix-match syntax used by `permissions.allow`. With this
  fix, `make -C .claude/test check` / `docker version` /
  `docker ps` / `./build.sh test` etc. all run unsandboxed without
  needing per-call `dangerouslyDisableSandbox: true`. Verified
  locally: 257-test hook suite passes plain `make -C .claude/test
  check` (no disable flag).

### Changed
- CLAUDE.md「Sandbox baseline」section updated to document the new
  4th key (`excludedCommands`) alongside `enabled` /
  `autoAllowBashIfSandboxed` / `filesystem.allowWrite`. Previous
  text claimed "3 lines"; now "4 keys" with the rationale and link
  to issue #39 for posterity.
- `.claude/settings.json` permission rules normalized to colon form
  (`Bash(<prefix>:<args>)`). Four entries were still using the
  space-arg form (`Bash(npm list *)`, `Bash(npm root *)`,
  `Bash(npm config *)`, `Bash(bash -c *)`); now all entries use the
  same colon-form for grep-ability and consistency with the rest of
  the file. Behaviour is unchanged — both forms match identically at
  the perm-parser layer. Closes the (5) follow-up from issue #7.
- `.claude/settings.json` is now the **single source of truth** for
  Claude Code settings. Permissions (`allow` / `ask`), `sandbox`
  config, and `prefersReducedMotion` previously lived in the
  gitignored `.claude/settings.local.json`; they are now committed
  in `settings.json` so a fresh clone / new machine inherits the
  full setup without manually re-approving every command. The local
  override file is no longer used by this repo. CLAUDE.md「Sandbox
  baseline」section retitled accordingly.
- `.claude/settings.json` `permissions.ask` extended with
  state-changing docker subcommands: `docker build/run/exec/start/
  stop/restart/compose:*`. Combined with the new
  `check_prefer_dot_sh.sh` hook below, this enforces "use ./build.sh
  / ./run.sh / ./exec.sh / ./stop.sh wrappers, not raw docker"
  across the org's container repos.
- `.claude/settings.json` allow list reduced from ~95 entries to 45
  by removing (a) read-only commands already covered by
  `autoAllowBashIfSandboxed`, (b) duplicate absolute-path forms of
  `.claude/scripts/*.sh`, (c) stale `worktree/template-{199,207,210}`
  paths, (d) redundant hook-script self-invocations, (e) one-shot
  curl probes, (f) `Bash(bash -c *)` (moved to ask — was a permission
  bypass for narrower destructive rules), (g) frozen
  `APT_MIRROR_DEBIAN=...` make variants (let `.env` provide the
  value to docker compose; `Bash(make:*)` covers the bare form).

### Added
- New PreToolUse hook `.claude/hooks/check_prefer_dot_sh.sh` —
  detects `docker build/run/exec/stop` and `docker compose
  <up|down|build|run|exec>` calls. When the cwd has the matching
  `.sh` wrapper (`./build.sh` / `./run.sh` / `./exec.sh` /
  `./stop.sh`), DENIES with a message pointing at the wrapper
  (going through the wrapper picks up `setup.sh` `.env` / compose
  refresh + language env + GPU/GUI detection). When no wrapper is
  available, forces `ask` prompt rather than letting the broader
  `Bash(docker:*)` allow rule pass. Read-only subs (ps / images /
  inspect / logs / pull / ...), make-internal docker compose calls
  (subprocess; not visible to Claude), and destructive subs already
  in `permissions.ask` (rm / rmi / push / kill / ...) stay silent.
  19 bats specs cover the wrapper-present / wrapper-absent / silent
  matrix plus env-prefix stripping (`BUILDKIT_PROGRESS=plain docker
  build ...`). Codifies the user feedback: "build/run/exec/stop 一律
  走 .sh wrapper; 沒 wrapper 要詢問 user; user 沒明確同意一律禁止".
- New PreToolUse hook `.claude/hooks/check_tag_version_consistency.sh`
  blocks `git tag -a v*` / `git tag v*` (lightweight) /
  `git push <remote> v*` / `git push <remote> refs/tags/v*` when the
  repo root has a `.version` file whose content does not match the
  tag name. Closes the gap that allowed template v0.18.0 / v0.18.1
  to ship with `.version` still on `v0.17.0` — `make upgrade-check`
  in downstream repos kept reporting upgrade-available because the
  metadata was wrong. Skips deletes (`-d` / `:tag`), tag listing,
  `git push --tags` (bulk; out of scope), and downstream consumer
  repos that only have `template/.version` (their tags are
  independent of the consumed template version). 15 bats specs cover
  the full matrix. Refs issue #36 (Ask 1).
- New PreToolUse hook `.claude/hooks/remind_make_first_upgrade.sh`
  emits a non-blocking reminder when the agent runs
  `./template/upgrade.sh` directly while `Makefile.ci` declares an
  `upgrade:` target. Make wrapper internally calls the same .sh but
  also runs `init.sh` symlink resync + `main.yaml @tag` rewrite, so
  going through it lowers the chance of half-upgrades. Hook silent
  when no Makefile.ci, no `upgrade:` target, or the wrapper is
  already in use. 8 bats specs cover trigger paths + silence cases.
  Codifies CLAUDE.md「升級一律 make 優先」at the hook layer. Refs
  issue #36 (Ask 2).

### Documentation
- `CLAUDE.md` new section "Process discipline — slash command / skill
  優先於 ad-hoc 執行" — explicit rule that documented entry points
  (`.claude/commands/` + `.claude/skills/`) are the contract for
  multi-step mutating flows; ad-hoc execution is allowed only for
  trivial read-only checks. Lists the v0.18.0 / v0.18.1 release
  incident as the motivating case (`/release` was bypassed, the
  chore-PR step that bumps `.version` got skipped, hook layer had no
  fallback). Cross-links to the two new hooks above. Refs issue #36
  (Ask 2).

### Changed
- `.claude/scripts/batch-template-upgrade.sh` now self-prints a
  copy-pasteable next-step block at end of every real run:
  `wait-pr-ci-batch.sh <pairs> --check-filter ...` followed by
  `batch-pr-merge.sh <pairs>`, with the exact `<reponame>:<pr_num>`
  pairs captured from each successful `gh pr create`. Sessions that
  bypass `/batch-template-upgrade.md` and call the script directly
  now still see the productized waiter — fixes the v0.15.0 rollout
  regression where a session fell back to the old ad-hoc
  `/tmp/wait-batch-vX.Y.Z.sh` pattern (file didn't exist; only an
  error log left behind). 7 new bats specs cover arg validation
  (`--help` / missing version / missing why / unknown arg) plus
  three unit tests of `print_next_step_hint` (multi-pair / single
  pair / silent on empty).
- `remind_docker_for_lint.sh` wrapper list now configurable per repo
  via sibling `.claude/lint_wrappers.txt` (one substring pattern per
  line; blank / `#`-prefixed lines skipped). When the file is present
  it FULLY REPLACES the default list, not appends. Useful for
  downstream forks that wrap lint differently — coreSAM (#7) needs
  `make -C .claude` instead of this repo's `make -f Makefile.ci`.
  Default list also extended to include `make -C .claude/test`
  (already used in this repo for the test infra Makefile but missing
  from the previous hardcoded list). 5 new bats specs cover the
  default fallback + file override + comment/blank line skipping +
  missing `CLAUDE_PROJECT_DIR` defensive path; existing 7 specs
  remain. Addresses #7 (2).

### Documentation
- `CLAUDE.md` new section "Sandbox baseline (settings.local.json)" —
  explains the `sandbox.enabled` + `autoAllowBashIfSandboxed` +
  `filesystem.allowWrite` combination and what it lets the
  `permissions.allow` list shed. Tables out the per-key semantics and
  notes when sandbox isn't enough (parser fallback fires before
  sandbox eval). Onboarding aid for newcomers grappling with bloated
  allow lists; addresses #7 (1) (CoreSAM downstream port feedback).

### Added
- `.claude/scripts/wait-pr-ci-batch.sh` — multi-repo PR-scoped sibling
  of `wait-pr-ci.sh`, aggregating N PRs across N repos into one
  Monitor stream. Args: positional `<repo>:<pr>` pairs (short form
  auto-prefixed with `ycpss91255-docker/` via `--owner` default).
  Same output shape, exit codes, `--check-filter`, `--interval`,
  `--max-iterations` semantics as the single-repo flavour. Resolves
  the "spawn one Monitor per repo" guidance for N=15+ batches that
  produces noisy parallel notification streams. Closes #16.
- `.claude/scripts/check-claude-md-tree.sh` — CI lint that parses the
  `.claude/` tree listing in `CLAUDE.md` and diffs against the
  filesystem under `.claude/commands/`, `.claude/scripts/`,
  `.claude/hooks/`. Exits 1 on drift with `+` / `-` entry diff;
  exits 2 on usage / parse error. Honours folded subdirs
  (`└── test/` placeholder under `hooks/`) so they don't false
  positive. Wired into `.claude/test/Makefile` as a new `tree-check`
  target (also added to `check`) and into `.github/workflows/test.yaml`
  as a CI step. Background: PR #29 caught up 7 entries that drifted in
  one week of feature work; this lint prevents recurrence by failing
  the build instead of relying on memory or `/doc-sync`. 8 bats specs
  cover help / missing inputs / aligned / fs-drift / tree-drift /
  folded subdir handling / multi-dir drift.

### Changed
- `.claude/skills/wait-pr-ci/SKILL.md` documents the new third
  flavour (multi-repo batch). Replaces the previous "spawn one
  Monitor per repo in parallel" guidance with: N=2-3 use single-repo
  Monitors, N=4+ use `wait-pr-ci-batch.sh`.
- `.claude/commands/batch-template-upgrade.md` "After the script"
  section now points at `wait-pr-ci-batch.sh` for the wait step and
  `batch-pr-merge.sh` for the merge step (was an ad-hoc `gh pr merge`
  per-repo block — exactly the loop pattern the CLAUDE.md cross-repo
  batch-mutation rule rules out). Closes #17.

### Documentation
- Catch up `CLAUDE.md` `.claude/` directory tree drift (audit found 7
  entries added in past PRs but never synced into the tree listing):
  - `hooks/`: + `remind_no_chinese_in_git_artifacts.sh` (PR #20),
    + `remind_test_tools_smoke_sync.sh`
  - `scripts/`: + `batch-gitignore-fix.sh` (PR #21),
    + `batch-gitignore-add-line.sh` (PR #23),
    + `batch-pr-merge.sh`,
    + `check-template-versions.sh` (PR #18),
    + `fix-compose-copy-line.sh`
  No code change. Follow-up `.claude/scripts/check-claude-md-tree.sh`
  CI lint planned to prevent recurrence (drift accumulated ~7 entries
  in roughly one week of feature work).

### Changed
- `/issue-fix` now auto-merges PRs on CI green (matching `/pr.md` and
  `wait-pr-ci` skill defaults) instead of leaving them for human merge.
  Step 7 ALL_DONE handler now runs `gh pr merge --squash --delete-branch`
  + `git fetch` + `git worktree remove` inline; CI red still halts (no
  auto-merge, worktree left for inspection). The "Never auto-merge"
  note in the original `/issue-fix` was inconsistent with the rest of
  the project's PR workflow — `/pr.md` step 6 and the `wait-pr-ci`
  skill's "Pairing with merge" section both auto-merge on `ALL_DONE`.
  Branch protection (`enforce_admins=true` + `required_status_checks`
  strict) still applies, so `gh pr merge` refuses if CI didn't really
  pass or the branch is stale.

### Added
- New helper script `.claude/scripts/run-bats-in-compose.sh` — wraps
  `docker compose run --entrypoint bash <service> -c '<inline>'` so
  Claude's bash AST parser sees only atomic flags (`--service`,
  `--suite`, `--grep`, `--tail`, `--head`, `--compose-file`), not a
  quoted shell body. Avoids the "Unhandled node type: string" fallback
  that fires on `docker compose ... bash -c '<long string>'` patterns
  even when `Bash(docker:*)` is allow-listed (the parser fallback is
  pre-allowlist). Default behaviour: `--suite all`, `--grep '^not ok'`
  (fail-only), `--tail 25`. Composable: `--suite <kind>` accepts
  `unit` / `integration` / `all` / arbitrary path under `/source`,
  `--grep ''` disables filter for full output. 14 bats specs cover
  flag parsing, suite resolution, grep-pipe composition, env
  propagation, --head / --tail mutual exclusion, and quoting-injection
  rejection.

### Changed
- `/issue-fix` second arg now accepts `all` (or omitted) for batch mode —
  iterates every open issue on `<repo>` serially, oldest first (FIFO),
  pre-filtering out issues with open linked PRs / `wontfix` / `invalid` /
  `duplicate` / `do-not-merge` / `discussion` / `question` labels and
  any issue already carrying a `Reviewed by /issue-fix automation`
  comment. New `--limit N` flag truncates the post-filter list. Each
  surviving issue runs the full single-issue flow (reasonableness check
  → reject + comment, or worktree + PR + CI wait); the batch stops on
  the first CI red but continues through reject / scope-exceeded
  outcomes per issue. Ends with a Traditional Chinese summary block
  listing accepted / rejected / scope-exceeded / skipped counts plus
  the stop reason. Single-issue mode (when `<issue_num>` is a positive
  integer) preserves the original behaviour.

### Added
- New PreToolUse Bash hook `.claude/hooks/remind_readme_on_core_script.sh` —
  fires before `git commit` when staged files include template's core
  install/upgrade scripts (`template/upgrade.sh`, `template/init.sh`,
  `template/upgrade-check.sh`, `template/script/docker/setup.sh`, or the
  same paths from a template-internal session without the `template/`
  prefix) but no `README*.md` is in the same commit. Advisory only —
  emits a `systemMessage` reminder, does not block. Closes the gap where
  README's "Upgrading" / "Configuration" sections drift from upgrade.sh
  internals (e.g. implicit-downgrade refusal, `_warn_config_drift`,
  config/ preservation all shipped without README mention). Skips
  `--amend` / `--allow-empty`. 13 bats specs cover non-commit / amend /
  no-stage / readme-only / build.sh / each core script path / both
  prefixes / core+readme together / `git -C <path>`.
- New slash command `/issue-fix <repo> <issue_num> [--dry-run]` —
  delegates auto-fixing one open `ycpss91255-docker/<repo>` issue to the
  agent when scope is reasonable; rejects (with one explanatory comment
  on the issue) when not. Reasonableness gate covers: thin body, pure
  question, architectural decision, cross-repo coordinated change,
  destructive migration, >200-line diff estimate, conflicting reports.
  On accept: opens a worktree per the worktree workflow, writes a
  regression test first (TDD), implements the minimal fix, runs the
  repo's standard Docker-based test runner, opens a PR with
  `Closes #<num>`, then waits for CI to settle via `wait-pr-ci` skill
  (B2 — block until green). Never auto-merges. If diff exceeds 200
  lines mid-implementation, comments on the issue and leaves the
  worktree for human inspection. Per-repo `--check-filter` for
  `wait-pr-ci.sh` documented in the command (template / multi_run
  default; claude-workspace `bats + shellcheck + hadolint`; container
  repos `call-docker-build / docker-build`). Pairs with the
  read-only `/issue-check`.
- `CLAUDE.md` new section "git worktree 用法（強制）": for any new
  branch / WIP / chore PR on any of the 18 git repos, use
  `git worktree add <workspace>/worktree/<repo>-<N> -b <branch> main`.
  Standard location `<workspace>/worktree/` is already gitignored at
  workspace level. Existing 18 main checkouts (workspace + 17
  downstream + template) stay fixed at origin/main — no branches, no
  WIP commits, no dirty working tree. Multiple worktrees can coexist
  for parallel sessions on the same repo. Cross-repo batch scripts
  (`batch-template-upgrade.sh` etc.) are exempt — they manage their
  own fetch / branch flow internally. On a fresh machine without
  `<workspace>/worktree/`, Claude must ask the user where to place
  worktrees rather than guess. Closes part of #22.
- New helper script `.claude/scripts/batch-gitignore-add-line.sh` —
  generic sister of `batch-gitignore-fix.sh` that **appends** an
  arbitrary line to each downstream `.gitignore` if not already
  present. Mirrors the `--why-file` / `--why` / `--only` / `--skip` /
  `--dry-run` / `--continue-on-error` shape. Idempotent (skip if line
  already exists). 7 bats specs cover help / required-arg /
  unknown-arg / dry-run / scope filter / branch-name slugification.
  First use case: add `CLAUDE.md` to each downstream `.gitignore` so
  per-repo `<repo>/CLAUDE.md → ../<n>/CLAUDE.md` symlinks (issue #22)
  don't leak into git status.

### Changed
- Slash commands made cwd-aware so they degrade gracefully when invoked
  from per-repo sessions (e.g. `cd template && claude`) instead of the
  workspace root:
  - `/doc-sync` default path changed from hardcoded
    `/home/yunchien/workspace/docker` to `${CLAUDE_PROJECT_DIR}`. From
    workspace cwd it covers all sub-repos as before; from per-repo cwd
    it scopes to that single repo. Removes a user-specific path that
    would have failed on any other machine.
  - `/pr` step 7 (template-merge fanout to 17 downstream repos) now
    explicitly notes "Scope: workspace cwd only" and points at
    `/batch-template-upgrade` for the per-repo session case. Manual
    fanout block kept for reference but `(cd ... && cmd)` subshell
    replaces the bare `cd` to avoid session cwd pollution.
  - `/batch-pr`, `/new-repo`, `/batch-template-upgrade` each gain a
    `Scope: workspace cwd only` block at the top — these commands
    iterate `${CLAUDE_PROJECT_DIR}/<category>/<repo>` paths and only
    work from the docker workspace root. Per-repo session use should
    fail loudly with a clear redirect to `/pr` (single-repo) or
    workspace re-entry.
- `check_no_emoji.sh` skip list extended to mirror
  `check_no_ai_attribution.sh`: meta-doc files (`CLAUDE.md`,
  `.claude/commands/*.md`, `.claude/skills/*/SKILL.md`,
  `doc/test/TEST.md`, `doc/changelog/CHANGELOG.md`) that legitimately
  quote the rules they enforce are no longer flagged. Surfaced when
  doc-sync.md `🤖 Generated` (a forbidden-pattern reference, not a
  violation) caused the hook to fire on every edit. 2 new bats specs.
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
- New blocking PreToolUse hook
  `remind_no_chinese_in_git_artifacts.sh` enforces English-only commit
  messages, PR + issue titles, bodies, and comments. Detects CJK
  Unified Ideographs (U+4E00-9FFF), CJK Ext-A (U+3400-4DBF), CJK
  Symbols & Punctuation (U+3000-303F: corner brackets, fullstop,
  enumeration comma), and Halfwidth / Fullwidth forms (U+FF00-FFEF:
  fullwidth comma, exclamation, question mark, fullwidth digits and
  letters). En-dash / em-dash / smart quotes / ellipsis stay allowed
  (English typography uses these). Triggers on `git commit -m / -F`,
  `gh pr create | edit | comment` with `--title / --body / --body-file`,
  `gh issue create | edit | close | comment` with the same flags +
  `--comment`. `--body-file` referenced paths are read and scanned;
  README\*.md and i18n / locale files (`*.zh-TW.md`, `*.zh-CN.md`,
  `*.ja.md`, `*.ko.md`, `*i18n*`, `*.po*`, `*.mo`) are exempt.
  Returns `permissionDecision: "deny"` rather than a non-blocking
  systemMessage so the offending command never reaches GitHub —
  no `git commit --amend` / `gh pr edit` cleanup needed afterwards.
  11 bats specs cover ideograph + fullwidth punctuation + fullwidth
  digit + CJK in `--body-file` (with exempt-path skip) + English
  typography passthrough + non-target commands.
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
- New helper script `.claude/scripts/batch-gitignore-fix.sh` — opens
  one chore PR per downstream repo (17 + template) to replace
  `.claude/` with `.claude` in each repo's `.gitignore`. The trailing
  slash form only matches a real directory; the docker monorepo
  creates `<repo>/.claude` as a relative symlink to the workspace
  `.claude/` for per-repo Claude sessions, which leaks into
  `git status` as `?? .claude` under the old pattern. Mirrors
  `batch-template-upgrade.sh` shape (`--why-file` / `--why` /
  `--only` / `--skip` / `--dry-run` / `--continue-on-error`),
  idempotent (skip if `.claude/` line already absent), no code or
  build impact in any downstream repo (gitignore-only). 5 bats specs
  (--help / required-arg / unknown-arg / dry-run / --only filter).
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
