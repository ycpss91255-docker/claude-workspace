#!/usr/bin/env bash
#
# batch-template-v0.21.1-stage-rename.sh
#
# One-time rollout script for the v0.21.0 -> v0.21.1 stage rename
# (template#243 + template#250). Each downstream repo's Dockerfile
# must rename `base` -> `devel-base` and `test` -> `devel-test`
# atomically with the subtree pull, otherwise CI's new
# `target: devel-test` step fails on stage-not-found.
#
# Repos with a `runtime` stage additionally get a new `runtime-test`
# block appended (template v0.21.0+ #243 framework). Default smoke
# is install-check style (`whoami && bash --version` via sh -c
# wrapper -- bare `RUN ${ARG}` word-splits operators per
# template#250).
#
# Repos without a runtime stage (agent/*) skip the runtime-test
# block; build-worker.yaml's `if: build_runtime` gate handles the
# CI side.
#
# Validation manually proven on app/sick_humble (PR #44, merged).
# This script automates the same flow for the 12 remaining active
# repos. After all 12 PRs open, wait CI green via wait-pr-ci-batch.sh
# then merge via batch-pr-merge.sh.
#
# Usage:
#   .claude/scripts/batch-template-v0.21.1-stage-rename.sh \
#     [--dry-run] [--only <r1,r2>] [--skip <r1,r2>] [--continue-on-error]
#
# Run from docker_harness workspace root (sibling of the 13 repo
# checkouts). Refuses if cwd lacks `agent/` `app/` `env/`
# subdirectories. Subagent sandbox blocks git push, so this MUST
# run from the main session.

set -euo pipefail

readonly ORG="ycpss91255-docker"
readonly TARGET_VERSION="v0.21.1"

# Repos to migrate. sick_humble excluded (PR #44 already merged as
# manual proof-of-concept).
readonly DEFAULT_REPOS=(
  agent/ai_agent
  agent/claude_code
  agent/codex_cli
  agent/gemini_cli
  app/realsense_humble
  app/realsense_noetic
  app/ros1_bridge
  app/sick_noetic
  app/urg_node_humble
  app/urg_node_noetic
  env/ros_distro
  env/ros2_distro
)

usage() {
  sed -n '/^# Usage:/,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
}

err() {
  printf '[batch-rollout] ERROR: %s\n' "$*" >&2
}

info() {
  printf '[batch-rollout] %s\n' "$*"
}

# rename_dockerfile_stages <dockerfile_path>
#
# Renames the v0.21.0 baseline triplet:
#   FROM sys AS base       -> FROM sys AS devel-base
#   FROM base AS devel     -> FROM devel-base AS devel
#   FROM devel AS test     -> FROM devel AS devel-test
# Plus the section-header comments matching `### base ###`,
# `### test ###` patterns that exist in most downstream Dockerfiles.
#
# Idempotent: running twice is a no-op (sed doesn't match
# already-renamed lines).
rename_dockerfile_stages() {
  local _df="$1"
  [[ -f "${_df}" ]] || { err "Dockerfile not found: ${_df}"; return 1; }
  sed -i \
    -e 's|^FROM sys AS base$|FROM sys AS devel-base|' \
    -e 's|^FROM base AS devel$|FROM devel-base AS devel|' \
    -e 's|^FROM devel AS test$|FROM devel AS devel-test|' \
    -e 's|^############################## base \(##*\)$|############################## devel-base \1|' \
    -e 's|^############################## test \(.*\)$|############################## devel-test \1|' \
    "${_df}"
}

# has_runtime_stage <dockerfile_path>
#
# Returns 0 if the Dockerfile defines a `runtime` stage (i.e. has a
# line `FROM <X> AS runtime`). 1 otherwise. Used to gate whether to
# append the runtime-test block.
has_runtime_stage() {
  local _df="$1"
  [[ -f "${_df}" ]] || return 1
  grep -qE '^FROM [^[:space:]#]+ AS runtime$' "${_df}"
}

# already_has_runtime_test <dockerfile_path>
#
# Returns 0 if the Dockerfile already has a runtime-test stage (so
# we don't append a duplicate block). 1 otherwise.
already_has_runtime_test() {
  local _df="$1"
  [[ -f "${_df}" ]] || return 1
  grep -qE '^FROM runtime AS runtime-test$' "${_df}"
}

# append_runtime_test_block <dockerfile_path>
#
# Appends the v0.21.1 runtime-test stage at the end of the
# Dockerfile. Uses the `sh -c "${ARG}"` wrapper form (template#250)
# so shell operators / nested quotes parse correctly. Default smoke
# is install-check style; downstream override via
# build_args: RUNTIME_SMOKE_CMD=<command>.
append_runtime_test_block() {
  local _df="$1"
  cat >> "${_df}" <<'DOCKERFILE_EOF'

############################## runtime-test (ephemeral) ##############################
# Install-check smoke for the runtime image (template v0.21.1+ #243).
# Default smoke verifies USER + bash on PATH. Override per-repo via
# build_args: RUNTIME_SMOKE_CMD=<command> (constraint: CLI-only, no
# GUI binaries that init Qt / OGRE on --version / --help).
#
# `sh -c` wrapper required: bare `RUN ${ARG}` word-splits operators
# (&&, ||) and nested quotes. The wrapper passes the value as a
# single string for sh to parse normally.
FROM runtime AS runtime-test

ARG RUNTIME_SMOKE_CMD='whoami && bash --version'
RUN sh -c "${RUNTIME_SMOKE_CMD}"
DOCKERFILE_EOF
}

# pr_body <repo>
#
# Emits the PR body for a given repo. Tailored note about whether
# the repo got the runtime-test block or skipped it.
pr_body() {
  local _repo="$1"
  local _has_runtime="$2"
  local _runtime_note=""
  if [[ "${_has_runtime}" == "1" ]]; then
    _runtime_note="3. **Local Dockerfile runtime-test stage** added (template v0.21.0+
   #243 framework, with the v0.21.1 #250 \`sh -c\` wrapper fix).
   Default install-check smoke; no per-repo \`RUNTIME_SMOKE_CMD\`
   override yet (Issue B territory)."
  else
    _runtime_note="3. **No runtime-test block** (this repo has no \`runtime\` stage;
   \`build_runtime: false\` in main.yaml means CI's new
   \`target: runtime-test\` step is gated off cleanly)."
  fi
  cat <<EOF
## Summary

Atomic rollout of template \`v0.21.1\` to \`${_repo}\`. Part of the
12-repo wave following sick_humble's manual proof-of-concept (PR #44).

Three coordinated changes (atomic per repo):

1. **Template subtree** pulled to \`v0.21.1\` (\`template/.version\`
   bumped, \`main.yaml\` \`@tag\` references updated).
2. **Local Dockerfile stage rename** for v0.21.0+ alignment:
   - \`FROM sys AS base\` -> \`FROM sys AS devel-base\`
   - \`FROM base AS devel\` -> \`FROM devel-base AS devel\`
   - \`FROM devel AS test\` -> \`FROM devel AS devel-test\`
${_runtime_note}

## Test plan

- [ ] CI green on this PR.
- [ ] After merge: ${_repo}'s main runs the new
      \`target: devel-test\` (and \`target: runtime-test\` if runtime
      stage present) build steps cleanly.

## Coordination

This is one of 12 PRs opened by
\`.claude/scripts/batch-template-v0.21.1-stage-rename.sh\`. After
all 12 settle CI green, batch merge via \`batch-pr-merge.sh\`.

## Related

- Builds on: ycpss91255-docker/template \`v0.21.1\` (#243 / #244
  / #250).
- ros_distro / ros2_distro absorption issues (ros_distro#5 /
  ros2_distro#5) track the parallel ROS bashrc absorption work.
EOF
}

main() {
  local dry_run=0
  local continue_on_error=0
  local only_csv=""
  local skip_csv=""

  while (( $# > 0 )); do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      --dry-run) dry_run=1; shift ;;
      --continue-on-error) continue_on_error=1; shift ;;
      --only) only_csv="$2"; shift 2 ;;
      --skip) skip_csv="$2"; shift 2 ;;
      *) err "Unknown arg: $1"; usage; exit 2 ;;
    esac
  done

  # Sanity check: must run from docker_harness workspace root.
  if [[ ! -d "agent" || ! -d "app" || ! -d "env" ]]; then
    err "Must run from docker_harness workspace root (sibling of agent/ app/ env/)."
    exit 2
  fi

  # Build the working repo list.
  local -a repos=()
  if [[ -n "${only_csv}" ]]; then
    IFS=',' read -ra repos <<< "${only_csv}"
  else
    repos=("${DEFAULT_REPOS[@]}")
  fi

  if [[ -n "${skip_csv}" ]]; then
    local -a filtered=()
    local _r _s _skip
    IFS=',' read -ra _skip_arr <<< "${skip_csv}"
    for _r in "${repos[@]}"; do
      _skip=0
      for _s in "${_skip_arr[@]}"; do
        [[ "${_r}" == "${_s}" ]] && _skip=1 && break
      done
      (( _skip == 0 )) && filtered+=("${_r}")
    done
    repos=("${filtered[@]}")
  fi

  info "version=${TARGET_VERSION} dry_run=${dry_run} repos=${#repos[@]}"

  local -a opened=() skipped=() failed=()
  local repo repo_dir branch_name short_name has_runtime_int
  branch_name="chore/template-${TARGET_VERSION}"

  for repo in "${repos[@]}"; do
    info "=== [${repo}] ==="
    repo_dir="${PWD}/${repo}"
    short_name="${repo##*/}"

    if [[ ! -d "${repo_dir}/.git" ]]; then
      err "[${repo}] not a git repo at ${repo_dir}"
      failed+=("${repo}")
      (( continue_on_error == 1 )) || return 1
      continue
    fi

    # Fetch fresh main.
    git -C "${repo_dir}" fetch \
      "https://github.com/${ORG}/${short_name}.git" main >/dev/null 2>&1 || {
        err "[${repo}] fetch failed"
        failed+=("${repo}")
        (( continue_on_error == 1 )) || return 1
        continue
      }

    if (( dry_run == 1 )); then
      info "[${repo}] dry-run: would worktree from origin/main, upgrade to ${TARGET_VERSION}, sed Dockerfile, append runtime-test if applicable, push, PR"
      opened+=("${repo}")
      continue
    fi

    # Worktree from current origin/main.
    local worktree_path
    worktree_path="${PWD}/worktree/${short_name}-rollout"
    if [[ -d "${worktree_path}" ]]; then
      err "[${repo}] worktree already exists at ${worktree_path}; remove it first"
      failed+=("${repo}")
      (( continue_on_error == 1 )) || return 1
      continue
    fi
    git -C "${repo_dir}" worktree add "${worktree_path}" -b "${branch_name}" FETCH_HEAD >/dev/null

    # Run upgrade.sh inside the worktree.
    (cd "${worktree_path}" && ./template/upgrade.sh "${TARGET_VERSION}") > /dev/null 2>&1 || {
      err "[${repo}] template/upgrade.sh failed"
      failed+=("${repo}")
      (( continue_on_error == 1 )) || return 1
      continue
    }

    # Apply Dockerfile rename.
    rename_dockerfile_stages "${worktree_path}/Dockerfile"

    # Append runtime-test block if the repo has a runtime stage and
    # doesn't already have a runtime-test stage.
    has_runtime_int=0
    if has_runtime_stage "${worktree_path}/Dockerfile"; then
      has_runtime_int=1
      if ! already_has_runtime_test "${worktree_path}/Dockerfile"; then
        append_runtime_test_block "${worktree_path}/Dockerfile"
      fi
    fi

    # Commit Dockerfile changes.
    git -C "${worktree_path}" add Dockerfile
    git -C "${worktree_path}" commit -m "feat(dockerfile): adopt v0.21.1 stage rename + runtime-test smoke" >/dev/null

    # Push.
    git -C "${worktree_path}" push -u \
      "https://github.com/${ORG}/${short_name}.git" "${branch_name}" >/dev/null 2>&1 || {
        err "[${repo}] push failed"
        failed+=("${repo}")
        (( continue_on_error == 1 )) || return 1
        continue
      }

    # Open PR.
    local body_file pr_url
    body_file="$(mktemp -t batch-rollout-pr-body.XXXXXX.md)"
    pr_body "${repo}" "${has_runtime_int}" > "${body_file}"
    pr_url="$(gh pr create -R "${ORG}/${short_name}" \
      --base main \
      --head "${branch_name}" \
      --title "chore: upgrade template subtree to ${TARGET_VERSION} + adopt devel-base/devel-test rename$( ((has_runtime_int==1)) && printf ' + runtime-test stage')" \
      --body-file "${body_file}" 2>&1 | tail -1)"
    rm -f "${body_file}"
    info "[${repo}] PR: ${pr_url}"
    opened+=("${repo}:${pr_url}")
  done

  printf '\n[batch-rollout] summary: opened=%d skipped=%d failed=%d\n' \
    "${#opened[@]}" "${#skipped[@]}" "${#failed[@]}"
  local _r
  for _r in "${opened[@]}"; do printf '  opened:  %s\n' "${_r}"; done
  for _r in "${skipped[@]}"; do printf '  skipped: %s\n' "${_r}"; done
  for _r in "${failed[@]}"; do printf '  failed:  %s\n' "${_r}"; done

  return 0
}

main "$@"
