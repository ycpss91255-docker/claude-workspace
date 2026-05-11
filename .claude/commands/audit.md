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
- [ ] `.template_version` matches latest template tag

### 2. CI/CD
- [ ] release-worker.yaml archive list matches actual files
- [ ] build-worker.yaml build-args are correct for this repo
- [ ] `.hadolint.yaml` included in release archive (if exists)
- [ ] `main.yaml` references current template version `@vX.Y.Z`

### 3. Scripts
- [ ] All scripts (build.sh, run.sh, exec.sh, stop.sh) are symlinks to .base/script/docker/
- [ ] All scripts have `-h`/`--help` support (inherited from template)

### 4. template subtree (all repos using template)
- [ ] `.base/` subtree exists
- [ ] `.template_version` matches main.yaml `@tag` references
- [ ] No stale `docker_setup_helper/` or `docker_.base/` directories

## Cross-repo consistency checks
- [ ] All repos have identical symlinks pointing to .base/script/docker/
- [ ] All repos use the same template version (`.template_version`)
- [ ] No bare `@xxx` in commit messages or PR titles (triggers GitHub mention)

## Output
Report findings as a table:
| Repo | Issue | Severity | File |
|------|-------|----------|------|

Context from user: $ARGUMENTS

Now perform the audit on the specified repos (default: all env repos).
