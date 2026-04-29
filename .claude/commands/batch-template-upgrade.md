Batch-upgrade all downstream repos under `ycpss91255-docker` to a target template tag.

**Scope: workspace cwd only.** The implementation script (`.claude/scripts/batch-template-upgrade.sh`) iterates `<workspace>/<category>/<repo>/` directories that exist as siblings of `template/` in the docker workspace. If running from a per-repo session, refuse and instruct the user to re-open Claude from the docker workspace root.

Use this **after** a new `template` tag has been pushed and the tag's CI is green. This propagates the new template version to all 17 downstream repos (agent / app / env) by opening one PR per repo.

## When to invoke

- A new `template` tag (`vX.Y.Z` or `vX.Y.Z-rcN`) just landed and you want downstreams on it.
- Re-running for repos that failed the previous batch (use `--only`).
- Dry-run inspection before committing to a real run.

## Why a dedicated command (vs `/batch-pr`)

`/batch-pr` is generic — it doesn't know template-subtree mechanics:
- `./template/upgrade.sh <tag>` runs subtree pull + integrity check + `init.sh` + `main.yaml` `@tag` rewrite
- `./template/init.sh` re-runs after subtree pull to resync root symlinks
- Default branch is `main` for all 17 repos, but origin tracking can be stale (uses HTTPS fetch to bypass)

`/release` only covers the upstream tag flow; this is the consumer-side adoption.

## How it runs

The command delegates to `.claude/scripts/batch-template-upgrade.sh`. Designed to run from the **main session** — subagent sandbox blocks `git push`.

### Required arguments

- `<version>` — target tag (e.g. `v0.12.1`)
- One of:
  - `--why-file <path>` — markdown file with PR body Why-section content
  - `--why "<text>"` — inline alternative

### Optional flags

- `--issue <num>` — adds `Closes part of ycpss91255-docker/template#<num>.` to PR body
- `--dry-run` — print plan, no mutation
- `--only <r1,r2,...>` — limit to listed repos (relative paths, e.g. `agent/ai_agent`)
- `--skip <r1,r2,...>` — exclude listed repos (e.g. ones pinned to older tags)
- `--continue-on-error` — keep going past failed repos; print summary

### Examples

Dry-run preview:
```bash
.claude/scripts/batch-template-upgrade.sh v0.12.1 \
  --why-file /tmp/v0.12.1-why.md \
  --issue 151 \
  --dry-run
```

Real run, skipping pinned repos:
```bash
.claude/scripts/batch-template-upgrade.sh v0.12.1 \
  --why-file /tmp/v0.12.1-why.md \
  --issue 151 \
  --skip app/ros1_bridge,env/osrf_ros2_humble \
  --continue-on-error
```

Re-run for one failed repo:
```bash
.claude/scripts/batch-template-upgrade.sh v0.12.1 \
  --why-file /tmp/v0.12.1-why.md \
  --only env/ros_kinetic
```

## After the script

1. Wait for all 17 (or N) PRs' CI to settle. Use `/wait-pr-ci` for batches.
2. Merge each (squash + delete-branch). Per repo:
   ```bash
   gh pr merge <num> -R ycpss91255-docker/<repo> --squash --delete-branch
   ```
3. Verify each downstream main is now at the target tag (`cat template/.version`).

## Repo list

Hardcoded in the script (`DEFAULT_REPOS`). Currently 17 repos:

- `agent/{ai_agent,claude_code,codex_cli,gemini_cli}` (4)
- `app/{realsense_humble,realsense_noetic,ros1_bridge,sick_humble,sick_noetic,urg_node_humble,urg_node_noetic}` (7)
- `env/{osrf_ros2_humble,osrf_ros_kinetic,osrf_ros_noetic,ros2_humble,ros_kinetic,ros_noetic}` (6)

When new repos are added to the org, update the array.

Context from user: $ARGUMENTS
