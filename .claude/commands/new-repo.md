Create a new Docker container repo under the ycpss91255-docker GitHub organization.

**Scope: workspace cwd only.** This command creates `${CLAUDE_PROJECT_DIR}/<category>/<repo>/` (sibling to the existing 17 sub-repos) and updates `${CLAUDE_PROJECT_DIR}/org-profile/profile/README.md`. If running from a per-repo session, refuse and instruct the user to re-open Claude from the docker workspace root before running `/new-repo` again.

Follow the standard workflow defined in CLAUDE.md. The user will specify the repo type and name.

Repo types:
- **env**: ROS development environment (has template subtree)
- **agent**: AI Agent with DinD (has template subtree, post_setup.sh, encrypt_env.sh)
- **app**: Pre-compiled application runtime (has template subtree)

All repos must use the template architecture.

Workflow:

1. **Create directory**: `mkdir ${CLAUDE_PROJECT_DIR}/<category>/<repo_name>`

2. **Add template subtree**:
   ```
   git subtree add --prefix=template \
       git@github.com:ycpss91255-docker/base.git <latest_tag> --squash
   ```

3. **Create all required files** using existing repos as templates:
   - Dockerfile (multi-stage: bats-src, bats-extensions, lint-tools, sys, base, devel, test)
   - compose.yaml (services: devel, test; optionally devel-gpu, runtime)
   - script/entrypoint.sh (container-internal script)
   - .env.example (IMAGE_NAME=<repo_name>)
   - .hadolint.yaml (custom rules if needed, otherwise symlink to .base/)
   - .template_version (current template version)
   - .gitignore (.env, coverage/)
   - test/smoke/<name>_env.bats (repo-specific smoke tests)
   - .github/workflows/main.yaml (calls template reusable workflows)
   - README.md (English, root directory)
   - doc/README.zh-TW.md + doc/README.zh-CN.md + doc/README.ja.md

4. **Create symlinks**:
   ```
   ln -sf .base/build.sh build.sh
   ln -sf .base/run.sh run.sh
   ln -sf .base/exec.sh exec.sh
   ln -sf .base/stop.sh stop.sh
   ln -sf .base/Makefile Makefile
   ```

5. **Dockerfile smoke test COPY pattern**:
   ```dockerfile
   COPY .base/test/smoke/ /smoke_test/
   COPY test/smoke/ /smoke_test/
   ```
   Note: For headless apps (no GUI), selectively COPY only script_help.bats + test_helper.bash from template (skip display_env.bats).

   Note: Docker COPY does not follow symlinks. Lint COPY must reference .base/ directly:
   ```dockerfile
   COPY .base/build.sh .base/run.sh .base/exec.sh .base/stop.sh /lint/
   COPY script/entrypoint.sh /lint/
   ```

6. **Verify locally**: `./build.sh test` must pass (ShellCheck + Hadolint + Bats)

7. **Create GitHub repo and push**:
   ```
   gh repo create ycpss91255-docker/<repo_name> --public --description "<desc>"
   git remote add origin git@github.com:ycpss91255-docker/<repo_name>.git
   git push -u origin main
   ```

8. **Add to org topic taxonomy**: open a PR in `ycpss91255-docker/.github` that adds the new repo to `topics.yaml` under `repos:`. Pick tags from `allowed.*` only (the lint job will reject unknown tags). Do NOT call `gh repo edit --add-topic` directly — `topics.yaml` is the single source of truth, and after the PR merges run `script/sync-topics.sh --apply` from a `.github` checkout to push the topics live. The weekly drift cron will fail on Monday if this step is skipped.

9. **Enable branch protection**

10. **Update org profile README** at `${CLAUDE_PROJECT_DIR}/org-profile/profile/README.md`

NOTE: All code changes must go through PR workflow (/pr).

Context from user: $ARGUMENTS

Now create the repo following this workflow.
