${ISSUE_LINE}

## Why

${WHY}

## What

Bumps `.base/` subtree to **${VERSION}** via:

```
./.base/upgrade.sh ${VERSION}
./.base/init.sh
```

`upgrade.sh` handles all four steps automatically:

1. `git subtree pull --squash` to ${VERSION}
2. integrity check (template markers present)
3. `init.sh` re-run (symlink resync)
4. `main.yaml` `@tag` references rewritten to `@${VERSION}`

`init.sh` was re-run after the upgrade per the project's `template subtree upgrade` rule (rule lives in CLAUDE.md / memory).

## Verification

```
$ cat .base/.version
${VERSION}
```

Smoke / unit / integration tests run in CI via the standard `call-docker-build` reusable workflow at `@${VERSION}`.
