Create and manage PRs across multiple repos in batch.

**Scope: workspace cwd only.** This command iterates `${CLAUDE_PROJECT_DIR}/<category>/<repo>` paths and only works when the session was started from the docker workspace root. If running from a per-repo session (e.g. `cd template && claude`), refuse and instruct the user to either: (a) re-open Claude from the workspace root, or (b) for a single-repo PR use `/pr` instead.

Use this when the same change needs to be applied to multiple repos (e.g., all env repos, all agent repos).

Follow this workflow:

1. **Identify target repos** from the argument or context:
   - `env`: ros_noetic, ros_kinetic, ros2_humble, osrf_ros_noetic, osrf_ros_kinetic, osrf_ros2_humble
   - `agent`: ai_agent, claude_code, gemini_cli, codex_cli
   - `app`: ros1_bridge, urg_node2
   - `all`: all of the above
   - Or specify individual repos

2. **Use a representative repo first** (default: ros_noetic for env, ai_agent for agent):
   - Make the change manually and verify it works
   - Then apply to remaining repos (copy if identical, or adapt per repo)

3. **For each repo**, run sequentially:
   ```bash
   cd ${CLAUDE_PROJECT_DIR}/<category>/<repo>
   git checkout -b <branch-name>
   git add <files>
   git commit -m "<message>"
   git push -u origin <branch-name>
   gh pr create --title "<title>" --body "<body>"
   ```

4. **Check CI status** for all PRs:
   ```bash
   for repo in <repos>; do
     gh pr view <number> -R "ycpss91255-docker/${repo}" --json statusCheckRollup --jq '...'
   done
   ```

5. **Merge all** when CI passes:
   ```bash
   for repo in <repos>; do
     gh pr merge <number> -R "ycpss91255-docker/${repo}" --squash --delete-branch
   done
   ```

6. **Pull main** in all repos after merge:
   ```bash
   for repo in <repos>; do
     cd ${CLAUDE_PROJECT_DIR}/<category>/${repo}
     git checkout main && git pull
   done
   ```

IMPORTANT:
- Each repo may have different test counts, ROS distros, image names — do NOT blindly copy files without checking
- Use `grep -c '^@test'` to verify test counts per repo
- Check `diff` between repos before assuming they are identical

Context from user: $ARGUMENTS

Now execute this workflow.
