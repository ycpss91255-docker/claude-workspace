# claude-workspace

Workspace-level Claude Code configuration that applies across the
sub-repos checked out under this directory (template, agent/*, env/*,
app/*, multi_run, etc.). Tracks:

- `CLAUDE.md` — workspace-wide rules and project layout.
- `.claude/hooks/` — 10 PreToolUse / PostToolUse hooks enforcing those
  rules (no emoji, no AI attribution, no coverage excl, CHANGELOG /
  TEST.md drift, TDD reminders, docker-for-lint, subtree init,
  PR-wait-CI).
- `.claude/commands/` — slash commands (`/audit /batch-pr /doc-sync
  /new-repo /pr /release /safe-delete`).
- `.claude/skills/` — `/wait-pr-ci` skill.

Sub-repos in this workspace are managed independently and excluded via
`.gitignore`.

## Quick start

Open Claude Code at the workspace root so the hooks and slash commands
load:

```bash
cd /path/to/your/workspace
claude
```

Hook configuration lives in `.claude/settings.json`. Personal
permissions go in `.claude/settings.local.json` (gitignored).

## Testing

All validation runs inside Docker so behaviour matches CI exactly
(CLAUDE.md「驗證一律走 Docker」):

```bash
make build       # build the test image (claude-workspace-test:local)
make test        # run all bats specs
make lint        # shellcheck on all hook scripts
make hadolint    # hadolint on Dockerfile.test
make check       # lint + hadolint + test (full CI gate)
```

See [`doc/test/TEST.md`](doc/test/TEST.md) for the test catalog and
[`doc/changelog/CHANGELOG.md`](doc/changelog/CHANGELOG.md) for release
notes.

## Layout

```
docker/                       # workspace root
├── CLAUDE.md                 # workspace rules
├── README.md                 # this file
├── Makefile                  # build / test / lint entry point
├── Dockerfile.test           # bats + shellcheck test image
├── .github/workflows/        # claude-workspace CI
├── .claude/
│   ├── settings.json         # hook + tool registration
│   ├── hooks/                # *.sh hook scripts + test/ specs
│   ├── commands/             # slash commands
│   └── skills/               # custom skills
├── doc/
│   ├── test/TEST.md          # test single source of truth
│   └── changelog/CHANGELOG.md
├── agent/  app/  env/        # sub-repos (independent)
├── template/  multi_run/     # sub-repos (independent)
└── org-profile/              # local checkout of ycpss91255-docker/.github
```

## License

Internal tooling. No external license; treat as part of the
ycpss91255-docker organisation.
