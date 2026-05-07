Create a PR for a bug fix, new feature, or refactoring.

IMPORTANT: All code changes (bug fix, new feature, refactoring, file moves, path changes, Dockerfile changes) MUST go through this PR workflow. Only pure documentation updates (README text, CLAUDE.md) can be pushed directly to main.

Follow this workflow:

1. **Create branch** from main:
   - Bug fix: `fix/<short-description>`
   - New feature: `feat/<short-description>`
   - Refactoring: `refactor/<short-description>`

2. **Make changes** (code, tests, docs)
   - Bug fix: MUST include a regression test
   - New feature: include tests if applicable
   - Refactoring: verify existing tests still pass
   - Update README if the change is user-facing

3. **Verify locally**:
   - Run `shellcheck -S warning *.sh` on changed .sh files
   - Run `./build.sh test` if Dockerfile or smoke tests changed
   - Run `make -f Makefile.ci test` if working in template repo

4. **Commit** with conventional message:
   - Bug fix: `fix: <description>`
   - New feature: `feat: <description>`
   - Refactoring: `refactor: <description>`
   - Docs only: `docs: <description>`
   - Do NOT add AI attribution lines (e.g. `Co-Authored-By: Claude ...`, `Generated with Claude Code`); CLAUDE.md「不加 AI 歸屬標記」明文禁止。

5. **Push branch and create PR**:
   ```
   git push -u origin <branch-name>
   gh pr create --title "<type>: <title>" --body "## Summary\n..."
   ```

6. **Wait for CI**, then merge:
   - Use the `wait-pr-ci` skill (`.claude/skills/wait-pr-ci/SKILL.md`) — Monitor + 30s poll loop, emits per-check notifications, ends with `ALL_DONE`. Don't busy-poll with `sleep` or repeat `gh pr checks`.
   - On `ALL_DONE`:
     ```
     gh pr merge <number> --squash --delete-branch
     ```
   - If merge fails with "branch is not up to date" (dependabot batch / main moved), comment `@dependabot rebase` (or rebase locally + force-push) and re-invoke the skill on the same PR.

7. **If this PR was on the `template` repo**: after merge + tag, the
   13 downstream repos need the new template subtree version pulled.
   **Scope: workspace cwd only** — the fanout below assumes
   `${CLAUDE_PROJECT_DIR}` is the workspace dir that contains all 13
   sub-repos. If the current session was started inside a single repo
   (per-repo cwd), skip step 7 entirely and instead run
   `/batch-template-upgrade <vX.Y.Z>` from a workspace session, which
   handles the same fan-out via a permanent script and avoids `cd`
   parser warnings:
   ```
   .claude/scripts/batch-template-upgrade.sh vX.Y.Z --why "..." --issue <num>
   ```
   Manual fan-out (kept for reference; prefer the batch script):
   ```
   for repo in env/ros_distro env/ros2_distro agent/ai_agent agent/claude_code agent/codex_cli agent/gemini_cli app/realsense_humble app/realsense_noetic app/sick_humble app/sick_noetic app/urg_node_noetic app/ros1_bridge app/urg_node_humble; do
     git -C "${CLAUDE_PROJECT_DIR}/$repo" pull
     (cd "${CLAUDE_PROJECT_DIR}/$repo" && ./template/upgrade.sh && git push)
   done
   ```
   For non-template PRs (fix / feat / refactor on a single repo), step 7
   is **N/A** — your work ends at step 6.

Context from user: $ARGUMENTS

Now execute this workflow for the described change.
