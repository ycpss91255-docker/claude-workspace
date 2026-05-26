#!/usr/bin/env bash
# fix-compose-copy-line.sh — one-off remediation for the v0.12.4 batch
# upgrade. The pre-#172 Dockerfile has `COPY compose.yaml
# /lint/compose.yaml` (dead code: hadolint never looks at it), and #172
# made `compose.yaml` gitignored + `git rm --cached`, so a fresh CI
# checkout lacks the file and `docker/build-push-action` fails on the
# COPY step.
#
# This script patches each affected repo's open
# `chore/base-v0.12.4` branch with a single follow-up commit that
# deletes the offending line and force-pushes to refresh CI.
#
# Usage:
#   .claude/scripts/fix-compose-copy-line.sh
#
# Idempotent: skips repos whose Dockerfile already lacks the line.
#
# Affected repos (10/17 — agent/* + ros1_bridge + ros_noetic +
# urg_node_humble are clean):
#   env/{osrf_ros2_humble,osrf_ros_kinetic,osrf_ros_noetic,
#        ros2_humble,ros_kinetic}
#   app/{realsense_humble,realsense_noetic,sick_humble,sick_noetic,
#        urg_node_noetic}

set -euo pipefail

readonly WORKSPACE="${WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)}"
readonly BRANCH="chore/base-v0.12.4"

readonly -a AFFECTED_REPOS=(
  env/osrf_ros2_humble
  env/osrf_ros_kinetic
  env/osrf_ros_noetic
  env/ros2_humble
  env/ros_kinetic
  app/realsense_humble
  app/realsense_noetic
  app/sick_humble
  app/sick_noetic
  app/urg_node_noetic
)

info() { printf '[fix] %s\n' "$*"; }
err()  { printf '[fix] ERROR: %s\n' "$*" >&2; }

main() {
  local _summary_ok=()
  local _summary_skip=()
  local _summary_fail=()

  local _rel _repo_dir _reponame _origin
  for _rel in "${AFFECTED_REPOS[@]}"; do
    _repo_dir="${WORKSPACE}/${_rel}"
    _reponame="${_rel##*/}"
    _origin="https://github.com/ycpss91255-docker/${_reponame}.git"

    info "[${_reponame}] checking out ${BRANCH}"

    if ! git -C "${_repo_dir}" rev-parse --git-dir >/dev/null 2>&1; then
      err "[${_reponame}] not a git repo at ${_repo_dir}"
      _summary_fail+=("${_rel}")
      continue
    fi

    git -C "${_repo_dir}" fetch "${_origin}" "${BRANCH}" 2>&1 | tail -2 || {
      err "[${_reponame}] fetch failed"
      _summary_fail+=("${_rel}")
      continue
    }
    git -C "${_repo_dir}" checkout -B "${BRANCH}" FETCH_HEAD >/dev/null 2>&1 || {
      err "[${_reponame}] checkout failed"
      _summary_fail+=("${_rel}")
      continue
    }

    if ! grep -qF 'COPY compose.yaml /lint/compose.yaml' \
        "${_repo_dir}/Dockerfile"; then
      info "[${_reponame}] already clean — skip"
      _summary_skip+=("${_rel}")
      continue
    fi

    sed -i '/^COPY compose\.yaml \/lint\/compose\.yaml$/d' \
        "${_repo_dir}/Dockerfile"

    if grep -qF 'COPY compose.yaml /lint/compose.yaml' \
        "${_repo_dir}/Dockerfile"; then
      err "[${_reponame}] sed did not remove the line"
      _summary_fail+=("${_rel}")
      continue
    fi

    git -C "${_repo_dir}" add Dockerfile
    git -C "${_repo_dir}" commit -m \
      "fix(dockerfile): drop dead 'COPY compose.yaml /lint/compose.yaml'

The /lint stage shellcheck'd .sh and hadolint'd Dockerfile but never
read /lint/compose.yaml — the COPY was leftover scaffolding. After
template v0.12.4 (#172) made compose.yaml a derived artifact (gitignored
+ git rm --cached), fresh CI checkouts no longer have the file and
docker/build-push-action's COPY step fails on the build context. Drop
the line so the test stage builds cleanly without depending on a now-
generated runtime artifact." >/dev/null

    git -C "${_repo_dir}" push --force "${_origin}" \
        "${BRANCH}" 2>&1 | tail -2

    _summary_ok+=("${_rel}")
    info "[${_reponame}] patched + pushed"
  done

  echo
  info "summary: patched=${#_summary_ok[@]} skipped=${#_summary_skip[@]} failed=${#_summary_fail[@]}"
  local _r
  for _r in "${_summary_ok[@]}"; do echo "  patched: ${_r}"; done
  for _r in "${_summary_skip[@]}"; do echo "  skipped: ${_r}"; done
  for _r in "${_summary_fail[@]}"; do echo "  FAILED:  ${_r}"; done
  (( ${#_summary_fail[@]} == 0 ))
}

main "$@"
