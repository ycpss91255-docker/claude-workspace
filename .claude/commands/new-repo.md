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
       git@github.com:ycpss91255-docker/template.git <latest_tag> --squash
   ```

3. **Create all required files** using existing repos as templates:
   - Dockerfile (multi-stage: bats-src, bats-extensions, lint-tools, sys, base, devel, test)
   - compose.yaml (services: devel, test; optionally devel-gpu, runtime)
   - script/entrypoint.sh (container-internal script)
   - .env.example (IMAGE_NAME=<repo_name>)
   - .hadolint.yaml (custom rules if needed, otherwise symlink to template/)
   - .template_version (current template version)
   - .gitignore (.env, coverage/)
   - test/smoke/<name>_env.bats (repo-specific smoke tests)
   - .github/workflows/main.yaml (calls template reusable workflows)
   - README.md (English, root directory)
   - doc/README.zh-TW.md + doc/README.zh-CN.md + doc/README.ja.md

4. **Create symlinks**:
   ```
   ln -sf template/build.sh build.sh
   ln -sf template/run.sh run.sh
   ln -sf template/exec.sh exec.sh
   ln -sf template/stop.sh stop.sh
   ln -sf template/Makefile Makefile
   ```

5. **Dockerfile smoke test COPY pattern**:
   ```dockerfile
   COPY template/test/smoke/ /smoke_test/
   COPY test/smoke/ /smoke_test/
   ```
   Note: For headless apps (no GUI), selectively COPY only script_help.bats + test_helper.bash from template (skip display_env.bats).

   Note: Docker COPY does not follow symlinks. Lint COPY must reference template/ directly:
   ```dockerfile
   COPY template/build.sh template/run.sh template/exec.sh template/stop.sh /lint/
   COPY script/entrypoint.sh /lint/
   ```

6. **Verify locally**: `./build.sh test` must pass (ShellCheck + Hadolint + Bats)

7. **Create GitHub repo and push**:
   ```
   gh repo create ycpss91255-docker/<repo_name> --public --description "<desc>"
   git remote add origin git@github.com:ycpss91255-docker/<repo_name>.git
   git push -u origin main
   ```

8. **Set topics**: `gh repo edit ycpss91255-docker/<repo_name> --add-topic docker,<category>,<extras>`

9. **Enable branch protection**

10. **Update org profile README** at `${CLAUDE_PROJECT_DIR}/org-profile/profile/README.md`

NOTE: All code changes must go through PR workflow (/pr).

Context from user: $ARGUMENTS

Now create the repo following this workflow.
