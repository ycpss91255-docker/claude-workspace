# Tests

Single source of truth for test counts and locations. Hooks
(`check_test_md_drift.sh`) compare per-file `@test` counts against the
numbers in this document on every Edit/Write of `*.bats` or `TEST.md`.

All tests run inside Docker via the `.claude/test/Dockerfile` image
(test infra lives under `.claude/test/`):

```bash
make -C .claude/test build       # build the test image (claude-workspace-test:local)
make -C .claude/test test        # run all bats specs
make -C .claude/test lint        # shellcheck on all hook + helper scripts
make -C .claude/test hadolint    # hadolint on .claude/test/Dockerfile
make -C .claude/test check       # lint + hadolint + test (full CI gate)
```

Total: **208 tests** (204 smoke + 4 integration) plus shellcheck (16 hook
scripts + 9 helper scripts) plus Hadolint (`.claude/test/Dockerfile`)
plus a CLAUDE.md `.claude/` tree audit (`make tree-check` —
`.claude/scripts/check-claude-md-tree.sh`).

## 4-category coverage

Per CLAUDE.md「測試分類（TDD 必須涵蓋的 4 個面向）」:

| # | Category | Where | What it covers |
|---|----------|-------|----------------|
| 1 | Smoke | `test/smoke/*_spec.bats` | Each hook fires on its trigger and stays silent otherwise |
| 2 | Unit | n/a (hooks are linear single-function scripts) | Smoke covers what unit would |
| 3 | Integration | `test/integration/chain_spec.bats` | Multi-hook scenarios where the same tool input drives several hooks |
| 4 | Lint | `make -C .claude/test lint` (shellcheck) + `make -C .claude/test hadolint` | All `.sh` hooks + helper scripts pass shellcheck; `.claude/test/Dockerfile` passes Hadolint |

## Smoke specs

Every `.bats` file targets a single hook (or a script under
`.claude/scripts/`). Each test pipes a sample JSON tool-input on
stdin and asserts one of three behaviours:

- **FIRE** — emits JSON with `.systemMessage` (reminder hooks like
  `remind_*.sh` / `check_*.sh`). Use `assert_message_contains`.
- **ALLOW** — emits JSON with `.hookSpecificOutput.permissionDecision`
  (programmatic auto-allow hooks like
  `auto_allow_rm_in_workspace.sh`). Use `assert_permission_decision`.
- **SILENT** — exits 0 with no stdout (no action taken). Use
  `assert_silent`.

### test/smoke/auto_allow_rm_in_workspace_spec.bats (18)
| Test | Scenario |
|------|----------|
| allows rm <relative file> (workspace cwd assumed) | relative path → ALLOW |
| allows rm subdir/file.txt | nested relative → ALLOW |
| allows rm /tmp/foo.sh | absolute under /tmp → ALLOW |
| allows rm -rf /tmp/dir | flag + /tmp path → ALLOW |
| allows rm /home/yunchien/workspace/docker/foo.txt (under workspace) | absolute under workspace → ALLOW |
| allows rm -- --weird-name (after -- separator) | `--` separator handling |
| silent on rm /etc/passwd (outside workspace) | absolute outside → SILENT (falls through to ask) |
| silent on rm /usr/bin/foo (outside workspace) | absolute outside → SILENT |
| silent on rm /home/yunchien/.bashrc (home outside workspace) | home dotfile → SILENT |
| silent on rm ~/.ssh/id_rsa (~ rejected) | tilde-expansion guard |
| silent on rm $HOME/.bashrc ($ rejected) | shell-var guard |
| silent on rm \`pwd\`/file (backtick rejected) | command-substitution guard |
| silent on rm ../../etc/passwd (.. traversal rejected) | path-traversal guard |
| silent on rm /tmp/foo && rm /etc/passwd (chain rejected) | command-chain guard |
| silent on rm /tmp/foo \| xargs (pipe rejected) | pipe guard |
| silent on non-rm command (ls -la) | matcher narrowed to rm |
| silent on rmdir (different command) | exact `rm` match, not prefix |
| silent on empty CLAUDE_PROJECT_DIR (defensive) | refuses to act without anchor |

### test/smoke/check_changelog_drift_spec.bats (6)
| Test | Scenario |
|------|----------|
| fires when code staged without CHANGELOG | code-only staged, no `doc/changelog/CHANGELOG.md` in commit → FIRE |
| silent when code AND CHANGELOG staged together | both staged → SILENT |
| silent when only docs staged | only `*.md` staged → SILENT |
| silent on --amend | `--amend` skips the rule → SILENT |
| silent in repo without doc/changelog/CHANGELOG.md (rule N/A) | rule does not apply → SILENT |
| resolves repo via cd subdir && git commit | `cd <repo> && git commit` parses correct repo → FIRE |

### test/smoke/remind_readme_on_core_script_spec.bats (13)
| Test | Scenario |
|------|----------|
| non-git-commit command is silent | `ls -la` → SILENT |
| git status is silent (not a commit) | `git status` → SILENT |
| git commit --amend is silent | `--amend` skips the rule → SILENT |
| git commit with no staged files is silent | empty index → SILENT |
| git commit with only README staged is silent | only `README.md` staged → SILENT |
| git commit with build.sh (non-core script) is silent | `build.sh` is not a core install/upgrade script → SILENT |
| git commit with template/upgrade.sh and no README fires | core script + no README → FIRE |
| git commit with template/init.sh and no README fires | core script + no README → FIRE |
| git commit with template/script/docker/setup.sh and no README fires | core script + no README → FIRE |
| git commit with upgrade.sh (template-internal session, no prefix) fires | path without `template/` prefix still matches → FIRE |
| git commit with core script + README is silent | both staged → SILENT |
| git commit with core script + translated README is silent | `README.zh-TW.md` counts → SILENT |
| git -C <path> commit resolves work dir from -C | parses `-C <repo>` to find correct repo → FIRE |

### test/smoke/check_no_ai_attribution_spec.bats (4)
| Test | Scenario |
|------|----------|
| fires on Co-Authored-By: Claude | content has `Co-Authored-By: Claude` → FIRE |
| fires on Generated with [Claude Code] | content has bracketed marker → FIRE |
| fires on Generated with Claude Code (no brackets) | content has plain marker → FIRE |
| silent on clean file | no markers → SILENT |

### test/smoke/check_no_coverage_excl_spec.bats (5)
| Test | Scenario |
|------|----------|
| fires on LCOV_EXCL_LINE | inline comment → FIRE |
| fires on LCOV_EXCL_START / STOP block | block markers → FIRE |
| fires on kcov-excl | kcov marker → FIRE |
| silent on clean file | no markers → SILENT |
| silent on .md file (skip) | `.md` is skipped by hook → SILENT |

### test/smoke/check_no_emoji_spec.bats (6)
| Test | Scenario |
|------|----------|
| fires when file contains emoji | emoji codepoint present → FIRE |
| silent on clean ASCII file | no emoji → SILENT |
| silent when file does not exist | file path missing → SILENT |
| silent when file is binary | binary file detected → SILENT |
| silent on meta-doc CLAUDE.md (legitimate emoji quoting) | rule-describing CLAUDE.md → SILENT |
| silent on .claude/commands/*.md meta-doc (rule description) | command markdown → SILENT |

### test/smoke/check_test_md_drift_spec.bats (5)
| Test | Scenario |
|------|----------|
| fires when TEST.md count > actual @test count | TEST.md claims more → FIRE |
| fires when TEST.md count < actual @test count | TEST.md claims fewer → FIRE |
| silent when counts match | counts equal → SILENT |
| fires when TEST.md lists missing bats file | bats file missing → FIRE |
| silent when edited file is not .bats or TEST.md | not a tracked file type → SILENT |

### test/smoke/remind_docker_for_lint_spec.bats (12)
| Test | Scenario |
|------|----------|
| fires on standalone shellcheck | bare `shellcheck ...` → FIRE |
| fires on standalone bats | bare `bats ...` → FIRE |
| fires on standalone hadolint | bare `hadolint ...` → FIRE |
| silent inside docker run wrapper | `docker run ... shellcheck ...` → SILENT |
| silent inside ./build.sh test wrapper | `./build.sh test` → SILENT |
| silent inside make -f Makefile.ci wrapper | `make -f Makefile.ci lint` → SILENT |
| silent on unrelated command containing the word bats in path | `ls /usr/lib/bats-core` → SILENT |
| silent inside make -C .claude/test wrapper (default list) | `make -C .claude/test test` → SILENT |
| lint_wrappers.txt overrides default list | sibling file lists custom wrapper → matches custom, SILENT |
| lint_wrappers.txt override drops the default docker pattern | with override list = `make -C .claude`, `docker run ...; bats foo` → FIRE |
| lint_wrappers.txt ignores blank and # comment lines | non-content lines skipped during parse |
| missing CLAUDE_PROJECT_DIR falls back to default list | unset env, `docker run ... shellcheck ...` → SILENT |

### test/smoke/remind_no_ai_attribution_spec.bats (5)
| Test | Scenario |
|------|----------|
| fires on git commit -m with Co-Authored-By: Claude | inline marker → FIRE |
| fires on gh pr create with Generated with [Claude Code] | inline marker → FIRE |
| fires on gh issue comment with attribution | inline marker → FIRE |
| silent on git commit without attribution | clean message → SILENT |
| silent on non-git/gh command containing attribution string | `echo Co-Authored-By: Claude` → SILENT |

### test/smoke/remind_pr_wait_ci_spec.bats (5)
| Test | Scenario |
|------|----------|
| fires on gh pr create | direct invocation → FIRE |
| fires on chained command containing gh pr create | `... && gh pr create` → FIRE |
| silent on gh pr list | non-create gh command → SILENT |
| silent on unrelated command | `echo hello` → SILENT |
| silent on empty command | empty input → SILENT |

### test/smoke/remind_subtree_init_spec.bats (4)
| Test | Scenario |
|------|----------|
| fires on git subtree pull ... template | template subtree pull → FIRE |
| silent on git subtree pull without template keyword | other subtree → SILENT |
| silent on git pull (not subtree) | non-subtree git pull → SILENT |
| silent on make upgrade (recommended path) | `make ... upgrade` → SILENT |

### test/smoke/remind_tdd_categories_spec.bats (8)
| Test | Scenario |
|------|----------|
| fires on .sh file edit | shell logic → FIRE |
| fires on Dockerfile edit | Dockerfile → FIRE |
| fires on compose.yaml edit | compose → FIRE |
| fires on entrypoint.sh edit | entrypoint specific reminder → FIRE |
| fires on .hadolint.yaml edit | lint rule edit → FIRE |
| silent on .md edit | docs → SILENT |
| silent on .bats edit | test file → SILENT |
| silent on .claude/ internals | hook self-edits → SILENT |

### test/smoke/remind_no_heredoc_redirect_spec.bats (10)
| Test | Scenario |
|------|----------|
| fires on cat <<'EOF' > /path | quoted heredoc to file → FIRE |
| fires on cat << EOF > /path (no quotes) | unquoted heredoc → FIRE |
| fires on cat <<-EOF > /path (dash form) | tab-stripping heredoc → FIRE |
| fires on cat <<EOF >> /path (append redirect) | append `>>` form → FIRE |
| silent on plain echo > file (no heredoc) | simple redirect → SILENT |
| silent on cat /file > /other (no heredoc) | file-to-file copy → SILENT |
| silent on heredoc piped to command (no file redirect) | `cat <<EOF \| sh` → SILENT |
| silent on git commit message describing the pattern (false-positive guard) | `git commit -m "...cat <<EOF > path..."` → SILENT |
| silent on bash -c "cat <<EOF > path" (allowed wrapper) | `bash -c` wraps the heredoc → SILENT |
| fires on chained command: git status && cat <<EOF > /path | command-position heredoc after `&&` → FIRE |

### test/smoke/remind_no_chinese_in_git_artifacts_spec.bats (11)

Covers `.claude/hooks/remind_no_chinese_in_git_artifacts.sh` — blocking
PreToolUse hook that DENIES `git commit` and `gh pr|issue` commands when
the commit message / PR or issue title / body / comment contains CJK
ideographs (U+4E00-9FFF / Ext-A) or fullwidth punctuation + ASCII forms
(U+3000-303F / U+FF00-FFEF). README*.md and i18n / locale files are
exempt from `--body-file` scanning.

| Test | Scenario |
|------|----------|
| denies git commit -m with CJK ideograph | inline CJK in commit message → DENY |
| denies gh pr create --body with fullwidth comma | fullwidth punctuation in PR body → DENY |
| denies gh issue create --body with fullwidth digit | fullwidth digit in issue body → DENY |
| denies gh issue close --comment with CJK punctuation | CJK fullstop in --comment → DENY |
| denies gh pr comment --body-file pointing at file with CJK | file body with CJK → DENY |
| silent on gh pr create --body-file pointing at README.zh-TW.md (exempt) | exempt file → SILENT |
| silent on gh issue create --body-file pointing at i18n.sh (exempt) | i18n exempt file → SILENT |
| silent on git commit -m with plain English | no CJK → SILENT |
| silent on git commit -m with em-dash and smart quotes (English typography) | allowed non-ASCII typography → SILENT |
| silent on non-git/gh command containing CJK | matcher narrows to git/gh subcommands → SILENT |
| silent on gh pr list --json (no body/title editing) | non-editing gh subcommand → SILENT |

### test/smoke/remind_test_tools_smoke_sync_spec.bats (7)
| Test | Scenario |
|------|----------|
| fires on Dockerfile.test-tools edit, listing apk packages and smoke commands | edit Dockerfile.test-tools → FIRE with both lists |
| lists every package on the final stage apk add line | final-stage parsing covers full payload |
| ignores apk add lines from non-final stages | only final stage is parsed |
| silent when sibling release-test-tools.yaml is missing | YAML missing → SILENT |
| silent on unrelated Dockerfile | non-target Dockerfile → SILENT |
| silent when Dockerfile.test-tools has no final-stage apk add | no final apk → SILENT |
| handles empty smoke step gracefully | YAML run block empty → no crash |

### test/smoke/remind_use_body_file_spec.bats (9)
| Test | Scenario |
|------|----------|
| fires on gh issue close --comment "$(cat path)" | gh + comment substitution → FIRE |
| fires on gh pr create --body "$(cat path)" | gh + body substitution → FIRE |
| fires on gh pr edit --body $(cat path) without quotes | unquoted substitution → FIRE |
| silent on gh ... --body-file already | already canonical form → SILENT |
| silent on gh ... --body "inline string" | inline body → SILENT |
| silent on non-gh command using $(cat path) | non-gh substitution → SILENT |
| fires on gh pr create --body-file - <<EOF (heredoc stdin) | `--body-file -` heredoc variant → FIRE |
| fires on gh issue create --body-file - alone (stdin variant) | `--body-file -` followed by EOL → FIRE |
| silent on --body-file with non-dash path that happens to start with dash-like name | path containing `-` but not literal `-` → SILENT |

### test/smoke/wait_pr_ci_spec.bats (11)

Covers `.claude/scripts/wait-pr-ci.sh` (the PR-scoped polling loop extracted
out of the wait-pr-ci skill so the Monitor body becomes a single command, no
parser warnings). `gh` is stubbed via PATH so the loop sees canned
`gh pr view --json` output.

| Test | Scenario |
|------|----------|
| --help prints usage and exits 0 | help path |
| missing --repo exits 2 | required arg validation |
| missing --prs exits 2 | required arg validation |
| unknown arg exits 2 | unknown flag |
| all-pass + MERGEABLE single PR exits 0 with ALL_DONE | happy path |
| any FAILURE check exits 1 with FAIL <pr> | fail-fast on FAILURE |
| multiple PRs all-pass + MERGEABLE exits 0 | CSV PR batching |
| custom --check-filter narrows to a non-default check name | filter override (container-repo / org-profile usage) |
| max-iterations exits 124 when stuck pending | iteration cap |
| no matching checks counts as no-checks (not all-pass) and loops | empty filter result ≠ green |
| all-pass but UNKNOWN mergeable does not exit ALL_DONE | mergeable gate |

### test/smoke/wait_pr_ci_batch_spec.bats (14)

Covers `.claude/scripts/wait-pr-ci-batch.sh` — multi-repo flavour for
`/batch-template-upgrade` follow-up. Same Monitor pattern + output
shape as `wait-pr-ci.sh`, but takes positional `<repo>:<pr>` pairs
and aggregates all PRs into one stream.

| Test | Scenario |
|------|----------|
| --help prints usage and exits 0 | help path |
| no pairs exits 2 | required-arg validation |
| bad pair (no colon) exits 2 | format validation |
| non-numeric PR exits 2 | PR validation |
| unknown flag exits 2 | flag validation |
| all-pass single short-form pair exits 0 with ALL_DONE | happy path + default owner prefix |
| full owner/repo form is accepted (no prefix added) | full form override |
| --owner overrides default for short form | owner flag |
| any FAILURE check exits 1 with FAIL <repo>#<pr> | failure surfacing |
| multiple pairs all-pass + MERGEABLE exits 0 | batch happy path |
| custom --check-filter narrows to a non-default check name | container-repo filter usage |
| max-iterations exits 124 when stuck pending | iteration cap |
| no matching checks counts as no-checks (not all-pass) and loops | empty filter result ≠ green |
| all-pass but UNKNOWN mergeable does not exit ALL_DONE | mergeable gate |

### test/smoke/wait_tag_ci_spec.bats (10)

Covers `.claude/scripts/wait-tag-ci.sh` (the sibling script for
tag/branch-triggered workflows — `gh run list --branch <ref>` instead of
`gh pr view`). Same Monitor-wrap shape, same exit codes. `gh` is stubbed
via PATH.

| Test | Scenario |
|------|----------|
| --help prints usage and exits 0 | help path |
| missing --repo exits 2 | required arg validation |
| missing --branch exits 2 | required arg validation |
| unknown arg exits 2 | unknown flag |
| all runs completed + success exits 0 with ALL_DONE | happy path |
| any completed run with conclusion != success exits 1 with FAIL <name> | fail on completed-non-success |
| any in_progress run keeps polling and hits max-iterations 124 | partial completion stays pending |
| empty run list (tag just pushed) keeps polling and hits max-iterations 124 | total==0 ≠ green |
| custom --check-filter narrows to a specific run name | filter ignores out-of-scope in-progress runs |
| cancelled conclusion counts as failure | non-success conclusion handling |

### test/smoke/check_template_versions_spec.bats (7)

Covers `.claude/scripts/check-template-versions.sh` (read-only HTTPS fetch
of `template/.version` for every downstream repo, used during release
verification). Replaces an ad-hoc multi-repo for-loop curl pattern that
trips the bash AST parser. `curl` is stubbed via PATH so the script runs
without network.

| Test | Scenario |
|------|----------|
| --help prints usage and exits 0 | help path |
| unknown arg exits 2 | unknown flag |
| --only narrows to listed repos and prints versions | scope filter |
| missing version maps to MISSING | non-zero curl exit handling |
| --expect matches all → exit 0 | release-verify happy path |
| --expect mismatch → exit 1 | release-verify partial-rollout failure |
| --skip removes listed repo from default iteration | exclusion filter |

### test/smoke/batch_gitignore_add_line_spec.bats (7)

Covers `.claude/scripts/batch-gitignore-add-line.sh` (generic sister
of `batch-gitignore-fix.sh` that **appends** an arbitrary line to each
downstream `.gitignore` if absent — idempotent, mirrors the same
`--why` / `--only` / `--skip` / `--dry-run` / `--continue-on-error`
shape). Smoke-only; no network in tests.

| Test | Scenario |
|------|----------|
| --help prints usage and exits 0 | help path |
| missing --line exits 2 | required-arg validation |
| missing --why-file and --why exits 2 | required-arg validation |
| unknown arg exits 2 | unknown flag |
| --dry-run prints would-do line per repo without mutating | dry-run path |
| --only narrows to listed repos in dry-run | scope filter |
| branch name slugifies the --line value | safe branch-name derivation |

### test/smoke/batch_gitignore_fix_spec.bats (5)

Covers `.claude/scripts/batch-gitignore-fix.sh` (one-shot helper that
opens one chore PR per downstream repo to replace `.claude/` with
`.claude` in `.gitignore`, so per-repo Claude session symlinks no
longer pollute `git status`). Smoke-only; no network in tests.

| Test | Scenario |
|------|----------|
| --help prints usage and exits 0 | help path |
| missing --why-file and --why exits 2 | required-arg validation |
| unknown arg exits 2 | unknown flag |
| --dry-run prints would-do line per repo without mutating | dry-run path |
| --only narrows to listed repos in dry-run | scope filter |

### test/smoke/run_bats_in_compose_spec.bats (14)

Covers `.claude/scripts/run-bats-in-compose.sh` — wrapper around
`docker compose run --entrypoint bash <service> -c '<inline>'` that
side-steps the Claude bash AST parser fallback "Unhandled node type:
string" by exposing atomic flags (`--service`, `--suite`, `--grep`,
`--tail`, `--head`, `--compose-file`) instead of an inline shell body.
Stubs `docker` + `id` and asserts the inner shell command Claude's
parser never sees is composed correctly.

| Test | Scenario |
|------|----------|
| --help prints usage and exits 0 | help path |
| unknown arg exits 2 | unknown flag |
| missing compose.yaml exits 2 | required-file validation |
| single-quote in --grep is rejected | guard against quoting injection |
| default suite=all targets unit + integration dirs | path-resolution default |
| --suite unit narrows to /source/test/unit/ | suite kind handling |
| --suite integration narrows to /source/test/integration/ | suite kind handling |
| --suite <path> uses literal /source/<path> | escape hatch for arbitrary path |
| default --grep produces inner cmd with grep filter pipe | grep wiring |
| --grep '' disables filter (full output) | empty pattern disables grep |
| --service overrides default service name | flag override |
| --compose-file overrides default compose.yaml | flag override |
| HOST_UID / HOST_GID env values come from id stub | env propagation |
| --head N caps output to first N lines | head/tail mutual exclusion |

### test/smoke/check_claude_md_tree_spec.bats (8)

Covers `.claude/scripts/check-claude-md-tree.sh` — CI lint that parses
the `.claude/` tree listing in CLAUDE.md and diffs against filesystem.
Builds a fake repo with a synthetic CLAUDE.md per case and asserts the
audit's exit code + output. Honours folded subdirs (e.g. `└── test/`
under hooks/) so they don't false-positive.

| Test | Scenario |
|------|----------|
| --help prints usage and exits 0 | help path |
| missing CLAUDE.md exits 2 | required-file validation |
| missing .claude/ exits 2 | required-dir validation |
| aligned tree exits 0 | happy path |
| extra file in fs (missing from tree) exits 1 with + entry | drift: fs has more |
| extra entry in tree (missing from fs) exits 1 with - entry | drift: tree has more |
| folded subdir (test/) is honoured — no false positive | placeholder honoured |
| drift in two dirs reports both | multi-dir drift |

## Integration specs

### test/integration/chain_spec.bats (4)
| Test | Scenario |
|------|----------|
| git commit with Co-Authored-By: Claude AND code-only stage fires both pre-tool hooks | `remind_no_ai_attribution` + `check_changelog_drift` both FIRE on the same input |
| gh pr create with attribution body fires both pre-tool hooks | `remind_pr_wait_ci` + `remind_no_ai_attribution` both FIRE |
| editing a Dockerfile fires only the TDD reminder, not content-scan hooks | `remind_tdd_categories` FIRE; emoji/AI-attribution/coverage-excl SILENT |
| subtree pull command does not trigger PR-wait or attribution hooks | `remind_subtree_init` FIRE; PR-wait + attribution SILENT |

## Lint

`make -C .claude/test lint` runs `shellcheck` against every top-level
`.sh` in `.claude/hooks/` and `.claude/scripts/`. `make -C .claude/test
hadolint` lints `.claude/test/Dockerfile`. Both are part of `make -C
.claude/test check` and the CI workflow at `.github/workflows/test.yaml`.
