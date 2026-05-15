Audit repos for inconsistencies, outdated documentation, and defects.

Use this to perform a health check across repos after changes.

Follow this checklist:

## Per-repo checks

For each target repo, verify:

### 1. README accuracy (all language versions)
- [ ] Directory structure matches actual `find . -not -path './.git/*' | sort`
- [ ] Test counts match `grep -c '^@test' test/smoke/*.bats` (or in TEST.md only)
- [ ] All test files mentioned in TEST.md
- [ ] Language switcher links resolve correctly
- [ ] `.base/.version` matches latest base tag

### 2. CI/CD
- [ ] release-worker.yaml archive list matches actual files
- [ ] build-worker.yaml build-args are correct for this repo
- [ ] `.hadolint.yaml` included in release archive (if exists)
- [ ] `main.yaml` references current base version `@vX.Y.Z`

### 3. Scripts
- [ ] All scripts (build.sh, run.sh, exec.sh, stop.sh) are symlinks to .base/script/docker/
- [ ] All scripts have `-h`/`--help` support (inherited from base)

### 4. .base subtree (all repos using the base subtree)
- [ ] `.base/` subtree exists
- [ ] `.base/.version` matches main.yaml `@tag` references
- [ ] No stale `template/` or `docker_setup_helper/` directories

## Cross-repo consistency checks
- [ ] All repos have identical symlinks pointing to .base/script/docker/
- [ ] All repos use the same base version (`.base/.version`)
- [ ] No bare `@xxx` in commit messages or PR titles (triggers GitHub mention)

## Output
Report findings as a table:
| Repo | Issue | Severity | File |
|------|-------|----------|------|

Context from user: $ARGUMENTS

Now perform the audit on the specified repos (default: all env repos).
