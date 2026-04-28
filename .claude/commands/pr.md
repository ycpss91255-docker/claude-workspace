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

7. **If template repo**: after merge + tag, run `./template/upgrade.sh` in each
   of the 17 other repos to pull the new template subtree version:
   ```
   for repo in env/ros_noetic env/ros_kinetic env/ros2_humble env/osrf_ros_noetic env/osrf_ros_kinetic env/osrf_ros2_humble agent/ai_agent agent/claude_code agent/codex_cli agent/gemini_cli app/realsense_humble app/realsense_noetic app/sick_humble app/sick_noetic app/urg_node_noetic app/ros1_bridge app/urg_node_humble; do
     cd ${CLAUDE_PROJECT_DIR}/$repo
     ./template/upgrade.sh
     git push
   done
   ```

Context from user: $ARGUMENTS

Now execute this workflow for the described change.
