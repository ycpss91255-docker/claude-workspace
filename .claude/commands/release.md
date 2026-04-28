Tag and release repos following the project's semantic versioning and RC workflow.

Follow this workflow:

1. **Determine version** from the argument:
   - MAJOR.MINOR.0: new feature or behavior change
   - MAJOR.MINOR.PATCH: bug fix or documentation fix
   - Include `-rcN` suffix for release candidates

2. **Identify target repos** from the argument:
   - `env`: ros_noetic, ros_kinetic, ros2_humble, osrf_ros_noetic, osrf_ros_kinetic, osrf_ros2_humble
   - `agent`: ai_agent, claude_code, gemini_cli, codex_cli
   - `app`: ros1_bridge, urg_node_humble, urg_node_noetic, realsense_humble, realsense_noetic, sick_humble, sick_noetic
   - `template`: template repo (uses its own version line)
   - Or specify individual repos

3. **Tag RC first**:
   ```bash
   for repo in <repos>; do
     cd ${CLAUDE_PROJECT_DIR}/<category>/${repo}
     git tag -a <version>-rc1 -m "<version>-rc1: <description>"
     git push origin <version>-rc1
   done
   ```

4. **Wait for CI** on all repos:
   ```bash
   for repo in <repos>; do
     gh run list -R "ycpss91255-docker/${repo}" -L 1 --json status,conclusion,headBranch \
       --jq '.[] | {branch: .headBranch, conclusion}'
   done
   ```

5. **If RC passes → tag official release**:
   ```bash
   for repo in <repos>; do
     cd ${CLAUDE_PROJECT_DIR}/<category>/${repo}
     git tag -a <version> -m "<version>: <description>"
     git push origin <version>
   done
   ```

6. **If RC fails → fix, then tag rc2** (do NOT reuse rc1)

IMPORTANT:
- RC tags automatically become prerelease on GitHub (release-worker.yaml checks for `-` in tag name)
- template uses its own version line (e.g., v0.6.x), separate from other repos
- After tagging template, run `./template/upgrade.sh` in each of the 17 other repos
  to pull the new subtree version (or use the loop in `pr.md` step 7)
- Commit messages and PR titles MUST use backtick to wrap `@xxx` patterns
  (e.g., `` `@default:` ``) — bare `@xxx` triggers GitHub @mention parsing

Context from user: $ARGUMENTS

Now execute this workflow.
