# Tests

Single source of truth for test counts and locations. Hooks
(`check_test_md_drift.sh`) compare per-file `@test` counts against the
numbers in this document on every Edit/Write of `*.bats` or `TEST.md`.

All tests run inside Docker via the `.claude/test/Dockerfile` image
(test infra lives under `.claude/test/`):

```bash
make -C .claude/test build       # build the test image (docker_harness-test:local)
make -C .claude/test test        # run all bats specs
make -C .claude/test lint        # shellcheck on all hook + helper scripts
make -C .claude/test hadolint    # hadolint on .claude/test/Dockerfile
make -C .claude/test check       # lint + hadolint + test (full CI gate)
```

Total: **378 tests** (374 smoke + 4 integration) plus shellcheck (21 hook
scripts + 13 helper scripts) plus Hadolint (`.claude/test/Dockerfile`)
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
| git commit with .base/upgrade.sh and no README fires | core script + no README → FIRE |
| git commit with .base/init.sh and no README fires | core script + no README → FIRE |
| git commit with .base/script/docker/setup.sh and no README fires | core script + no README → FIRE |
| git commit with upgrade.sh (template-internal session, no prefix) fires | path without `.base/` prefix still matches → FIRE |
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

### test/smoke/check_readme_framework_spec.bats (20)
| Test | Scenario |
|------|----------|
| silent on a fully aligned English README | all 6 checks pass + 3 translations also aligned → SILENT |
| [1] fires on missing CI badge | English README without `actions/workflows/main.yaml/badge.svg` → FIRE |
| [2] fires on missing 4-language link | no `**[English](README.md)**` → FIRE |
| [3] fires when TL;DR is a blockquote | `> **TL;DR**` legacy quote → FIRE (must be `## TL;DR` H2) |
| [4] fires on stale .base/build.sh symlink target | `build.sh -> .base/build.sh` row → FIRE (canonical: `.base/script/docker/build.sh`) |
| [5] fires on .template_version reference | obsolete root version-pin file mentioned → FIRE (canonical: `.base/.version` since v0.16.0) |
| [6] fires on missing TEST.md link | no `(doc/test/TEST.md)` anywhere → FIRE |
| [drift] fires when a translation has no CI badge while English does | zh-TW empty while English has badge → FIRE |
| [drift] fires when a translation file is missing entirely | doc/README.ja.md missing → FIRE |
| checks a translation file directly with [zh-TW] label | edit doc/README.zh-TW.md, drift → message prefixed `[zh-TW]` |
| silent when editing .base/README.md (the framework reference itself) | path under `.base/` → SILENT (skipped) |
| silent when editing archive/<repo>/README.md (read-only archive) | path under `archive/` → SILENT (skipped) |
| silent when editing a non-README file | unrelated path → SILENT |
| silent on multi_run/README.md when fully aligned | multi_run path with all 4 languages aligned → SILENT |
| [7] silent when every tree path exists on disk (positive control) | Directory Structure tree where every leaf file/dir is materialized → SILENT (refs #65) |
| [7] fires when tree path does not exist on disk (the #65 drift) | flat-layout README after files were moved into a nested subdir → FIRE per stale path |
| [7] ignores ellipsis and pure tree-art lines | tree lines `│`, `├── ...`, `└── ...` → SILENT (no false positives) |
| [7] symlink notation 'build.sh -> .base/...' checks the link not the target | broken-symlink shape: README mentions `build.sh -> ...`; on-disk symlink present (target absent) → SILENT |
| [7] zh-TW heading '## 目錄結構' is recognized | translated heading also enters the tree-walker → FIRE on stale path |
| [7] silent when README has no Directory Structure section | no tree section at all → SILENT (walker no-op) |

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

### test/smoke/remind_tdd_categories_spec.bats (12)
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
| [#75] .sh in downstream repo with only test/smoke/ drops Unit + Integration | repo-detect: ros1_bridge layout → only Smoke + Lint clauses |
| [#75] .sh in repo with full test infra keeps all 4 categories | repo-detect: template layout → all 4 clauses |
| [#75] Dockerfile in repo with only test/smoke/ keeps Smoke + Lint | repo-detect on Dockerfile path |
| [#75] repo without any test/ subdir falls back to all 4 categories | fallback preserves pre-#75 behaviour |

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

### test/smoke/enforce_gh_body_file_spec.bats (33)

Covers `.claude/hooks/enforce_gh_body_file.sh` -- the PreToolUse hook
that BLOCKS gh routing violations from issue #64. Renamed + upgraded
from `remind_use_body_file.sh` (non-blocking remind). 8 rules across
issue/pr create, comment, edit, close, review. 80-char single-line
threshold for short inline bodies.

| Test | Scenario |
|------|----------|
| rule 8: gh issue close --comment "$(cat path)" denied | cat substitution → DENY |
| rule 8: gh pr create --body "$(cat path)" denied | cat substitution → DENY |
| rule 8: gh pr edit --body $(cat path) without quotes denied | unquoted substitution → DENY |
| rule 8: gh pr create --body-file - <<EOF heredoc denied | `--body-file -` heredoc → DENY |
| rule 8: gh issue create --body-file - alone (stdin variant) denied | `--body-file -` alone → DENY |
| rule 1: gh issue create without --body-file denied | inline body present, no `--body-file` → DENY |
| rule 1: gh issue create with --body-file /tmp/x.md allowed (silent) | canonical → SILENT |
| rule 4: gh pr create without --body-file denied (short inline body) | even short `--body "LGTM"` on create → DENY |
| rule 4: gh pr create with --body-file /tmp/x.md allowed | canonical → SILENT |
| rule 4: gh pr create --body-file path with dash-like name allowed | path with `-` but not literal `-` → SILENT |
| rule 3: gh issue close N --comment "..." denied | `--comment` on close → DENY (two-step required) |
| rule 3: gh issue close N -c "..." (short form) denied | short form of `--comment` → DENY |
| rule 3: gh issue close N --reason completed (no comment) allowed | reason-only close → SILENT |
| rule 3: gh issue close N --reason "not planned" allowed | reason-only close with quoted reason → SILENT |
| rule 3: gh issue close N (no args beyond N) allowed | bare close → SILENT |
| rule 6: gh pr edit N --body "inline" denied | edit inline body → DENY |
| rule 6: gh pr edit N --body-file /tmp/x.md allowed | edit via file → SILENT |
| rule 6: gh pr edit N --add-label "x" (no body) allowed | edit without body → SILENT |
| rule 2: gh issue comment N --body "<=80 single-line" allowed | short inline → SILENT |
| rule 2: gh issue comment N --body "<long string>" denied | long inline → DENY |
| rule 5: gh pr comment N --body "<=80" allowed | short inline → SILENT |
| rule 5: gh pr comment N --body "<long>" denied | long inline → DENY |
| rule 7: gh pr review --body "LGTM" allowed | short review → SILENT |
| rule 7: gh pr review --body "<long>" denied | long review → DENY |
| silent on non-gh command using $(cat path) | non-gh → SILENT |
| silent on gh pr view (no body involvement) | read-only subcmd → SILENT |
| silent on gh pr merge --auto (no body) | merge subcmd → SILENT |
| silent on gh run view <id> --json jobs | run-scoped read → SILENT |
| silent on gh api /repos/.../issues/N | raw api read → SILENT |
| silent on empty tool_input | defensive |
| silent on non-Bash tool_input shape (e.g. Edit) | wrong tool → SILENT |
| rule 2: gh issue comment --body "<exactly 80 chars>" allowed | boundary lower side → SILENT |
| rule 2: gh issue comment --body "<81 chars>" denied | boundary upper side → DENY |

### test/smoke/wait_pr_ci_spec.bats (22)

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
| --min-checks 2 with only 1 matching SUCCESS stays pending | subset-rollup race (issue #66) |
| --min-checks default 1 preserves backwards-compatible behaviour | positive control |
| status IN_PROGRESS blocks all-pass even when conclusion field absent | status-guard demotion |
| status COMPLETED + conclusion SUCCESS reaches ALL_DONE | positive control |
| --min-checks non-integer exits 2 | arg validation |
| --min-checks 0 exits 2 (must be positive) | arg validation |
| all-pass with all completedAt predating watch start → pending | stale-rollup completedAt guard (issue #60) |
| all-pass with completedAt newer than watch start → ALL_DONE | positive control for completedAt guard |
| headRefOid change between polls emits [head-moved] and forces pending | headRefOid guard (issue #60) |
| stable headRefOid across polls preserves ALL_DONE path | negative control for headRefOid guard |
| JSON without headRefOid preserves backwards-compatible behaviour | mocks without headRefOid keep working |

### test/smoke/wait_pr_ci_batch_spec.bats (30)

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
| per-repo --check-filter <repo>=<expr> applies only to that repo | per-repo filter map (issue #46) |
| per-repo filter overrides default for one repo, others fall back | mixed per-repo + global default |
| per-repo filter accepts full owner/repo key form | full owner/repo as filter key |
| global --check-filter (no repo prefix) still works as before | backwards-compat global filter |
| per-repo filter with no matching check counts as no-checks | per-repo filter narrowing semantics |
| duplicate --check-filter for same repo: last one wins | last-write-wins map semantic |
| --min-checks 2 with only 1 matching SUCCESS stays pending | subset-rollup race per-pair (issue #66) |
| status IN_PROGRESS blocks all-pass (status guard) | status-guard demotion per-pair |
| per-repo --min-checks <repo>=<N> applies only to that repo | per-repo min-checks map |
| --min-checks default 1 preserves backwards-compatible behaviour | positive control |
| --min-checks non-integer exits 2 | arg validation |
| --min-checks <repo>=<non-int> exits 2 | per-repo arg validation |
| all-pass with completedAt predating watch start → pending (batch) | stale-rollup completedAt guard per-pair (issue #60) |
| headRefOid change between polls emits [head-moved] (batch) | headRefOid guard per-pair (issue #60) |
| stable headRefOid across polls preserves ALL_DONE path (batch) | negative control for headRefOid guard |
| JSON without headRefOid preserves backwards-compatible behaviour (batch) | mocks without headRefOid keep working |

### test/smoke/batch_pr_merge_spec.bats (14)

Covers `.claude/scripts/batch-pr-merge.sh` — squash-merge the N PRs
opened by `batch-template-upgrade.sh` once their CI is green. Mirrors
`wait-pr-ci-batch.sh`'s argument contract (default-owner prefix +
`--owner` override + up-front PR validation) so the next-step block
printed by `batch-template-upgrade.sh` works for both scripts.

| Test | Scenario |
|------|----------|
| --help prints usage and exits 0 | help path |
| no pairs exits 2 | required-arg validation |
| bad pair (no colon) exits 2 | format validation |
| non-numeric PR exits 2 | PR validation up-front (before any gh call) |
| short repo name is normalized to ycpss91255-docker/<repo> | default owner prefix |
| full owner/repo form is accepted (no prefix added) | full form override |
| --owner overrides default for short form | owner flag |
| --dry-run prints planned merges and skips gh invocation | dry-run no-op |
| successful merge invokes gh pr merge with --squash --delete-branch | argv shape |
| gh failure produces summary and exits 1 | failure surfacing |
| mixed success and failure continues and reports both | continue-on-error semantics |
| unknown flag exits 2 | flag validation |
| empty repo in pair exits 2 | empty-repo guard |
| empty PR in pair exits 2 | empty-pr guard |

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
of `.base/.version` for every downstream repo, used during release
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

### test/smoke/ci_wall_time_compare_spec.bats (14)

Covers `.claude/scripts/ci-wall-time-compare.sh` — fetches two
`gh run view --json jobs` payloads, diffs per-job wall time + overall,
and prints a markdown table. Bats stubs `gh` per run-id and asserts
the formatted output / exit codes.

| Test | Scenario |
|------|----------|
| --help prints usage and exits 0 | basic flag handling |
| missing --repo exits 2 | required flag validation |
| missing --baseline exits 2 | required flag validation |
| missing --fixed exits 2 | required flag validation |
| unknown arg exits 2 | reject typos |
| all jobs match, fixed faster -> table with negative deltas | core path, signed delta |
| fixed slower -> positive delta with + prefix | sign formatting |
| job present in only baseline is skipped (no fixed counterpart) | inner join semantics |
| in-progress run (missing completedAt) exits 2 | guard against unfinished baseline |
| in-progress fixed run (missing startedAt) exits 2 | guard against unfinished fixed |
| gh API failure exits 1 | propagate gh error |
| --output writes table to file, stdout is empty | file-output path |
| table header always present even when no jobs match | empty-match still emits header rows |
| equal durations -> +0s (0%) delta | zero-delta formatting |

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

### test/smoke/batch_template_upgrade_spec.bats (7)

Covers `.claude/scripts/batch-template-upgrade.sh` — the implementation
behind `/batch-template-upgrade`. After PR #34 the script self-prints a
copy-pasteable `wait-pr-ci-batch.sh` + `batch-pr-merge.sh` block at the
end of a real run, so sessions that bypass the slash command still see
the next-step path (was the root cause of the v0.15.0 ad-hoc
`/tmp/wait-batch-vX.Y.Z.sh` regression). Specs cover arg validation
plus unit tests of `print_next_step_hint` via source-with-guard.

| Test | Scenario |
|------|----------|
| --help prints usage and exits 0 | help path |
| missing version exits 2 | required-arg validation |
| missing why exits 2 | required-arg validation |
| unknown arg exits 2 | flag validation |
| print_next_step_hint emits both wait + merge commands when pairs given | hint formatting (2+ pairs) |
| print_next_step_hint silent when no pairs | dry-run / all-skipped guard |
| print_next_step_hint preserves single pair | hint formatting (1 pair) |

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

### test/smoke/check_tag_version_consistency_spec.bats (15)

Covers `.claude/hooks/check_tag_version_consistency.sh` — PreToolUse
blocking hook that compares repo root `.version` against the tag name
on `git tag` / `git push <remote> <tag>`. Closes the gap that allowed
template v0.18.0 / v0.18.1 to ship with `.version` still on v0.17.0
(refs issue #36 Ask 1).

| Test | Scenario |
|------|----------|
| blocks git tag -a when .version mismatches | annotated tag path, FAIL → deny |
| blocks lightweight git tag when .version mismatches | bare `git tag <tag>` |
| blocks git push origin <tag> when .version mismatches | push form |
| blocks git push origin refs/tags/<tag> when .version mismatches | refspec form |
| silent when .version matches tag exactly | happy path |
| silent for rc tag matching .version | rc semver in `.version` |
| blocks rc tag when .version still on previous version | rc mismatch |
| silent when no .version at repo root (rule N/A) | template-less repo |
| silent for downstream consumer with .base/.version (no root .version) | downstream tags independent of consumed template version |
| silent on git tag -d (delete) | delete out of scope |
| silent on git push delete (:tag) | colon-delete form |
| silent on git tag listing (no positional tag) | list mode |
| silent on non-git command | unrelated command |
| resolves repo via cd subdir && git tag | cwd-resolution path |
| resolves repo via git -C and blocks mismatch | `-C` resolution path |

### test/smoke/check_prefer_dot_sh_spec.bats (19)

Covers `.claude/hooks/check_prefer_dot_sh.sh` — PreToolUse hook that
detects `docker build/run/exec/stop` and `docker compose <up|down|build|
run|exec>` calls. Denies + points at the matching `.sh` wrapper when
one exists in cwd; forces `ask` prompt when no wrapper is available.
Read-only subs / make-internal calls / already-asked subs (rm/push/...)
stay silent.

| Test | Scenario |
|------|----------|
| deny docker build when build.sh exists | wrapper-present, build path |
| deny docker run when run.sh exists | wrapper-present, run path |
| deny docker exec when exec.sh exists | wrapper-present, exec path |
| deny docker stop when stop.sh exists | wrapper-present, stop path |
| deny docker compose up → run.sh | compose up → run.sh map |
| deny docker compose down → stop.sh | compose down → stop.sh map |
| deny docker compose build → build.sh | compose build map |
| deny docker compose exec → exec.sh | compose exec map |
| deny docker compose run → run.sh | compose run map |
| ask when docker build but no build.sh wrapper | no-wrapper fallback |
| ask when docker compose up but no run.sh wrapper | no-wrapper fallback (compose) |
| silent on read-only docker subcommand (ps) | non-target sub |
| silent on read-only docker subcommand (images) | non-target sub |
| silent on docker pull (download is harmless) | pull is harmless |
| silent on docker rm (already in permissions.ask) | leave to perm rule |
| silent on non-docker command | unrelated cmd |
| silent on make (subprocess docker is not visible to Claude) | wrapper composition |
| strips single env-prefix and matches docker build | env-prefix tolerance |
| strips multiple env-prefixes and matches docker build | multi env-prefix |

### test/smoke/remind_make_first_upgrade_spec.bats (8)

Covers `.claude/hooks/remind_make_first_upgrade.sh` — non-blocking
PreToolUse reminder that nags when the agent runs
`./.base/upgrade.sh` directly while `Makefile.ci upgrade` is
available. Enforces CLAUDE.md「升級一律 make 優先」at the hook layer
(refs issue #36 Ask 2).

| Test | Scenario |
|------|----------|
| fires on ./.base/upgrade.sh when Makefile.ci has upgrade target | trigger path with VERSION arg |
| fires on bare .base/upgrade.sh (no leading ./) | path-prefix variant |
| fires on absolute path .base/upgrade.sh | absolute-path variant |
| silent when Makefile.ci absent (no make wrapper available) | rule N/A |
| silent when Makefile.ci has no upgrade target | rule N/A |
| silent on make -f Makefile.ci upgrade (already going through wrapper) | wrapper path |
| silent on unrelated commands | non-trigger |
| silent on script with similar name (foo/upgrade.sh) | path-prefix discriminator |

### test/smoke/check_no_stale_template_refs_spec.bats (12)
| Test | Scenario |
|------|----------|
| fires on template/script/docker reference in .base/script/docker/*.sh | stale `_lib.sh` source ref → FIRE |
| fires on template/init.sh reference | stale init path → FIRE |
| fires on template/upgrade.sh reference | stale upgrade path → FIRE |
| fires on template/dockerfile/ reference | stale Dockerfile dir → FIRE |
| fires on template/Makefile reference | stale top-level Makefile → FIRE |
| fires on Dockerfile under .base/ | Dockerfile pattern matcher → FIRE |
| silent after s\|template/\|.base/\|g | clean ref → SILENT |
| silent on literal template/ in archive/ (not under .base/) | scope guard (file outside `.base/`) |
| silent on .md file under .base/ (doc may discuss rename) | `.md` skip |
| silent on non-shell file under .base/ | extension matcher → SILENT |
| silent on missing file | defensive |
| silent on empty tool_input | defensive |

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
