#!/usr/bin/env bash
# Shared bats test helpers for .claude/hooks/test/.
#
# Layout:
#   .claude/hooks/
#   ├── *.sh                  # hooks under test
#   └── test/
#       ├── lib/test_helper.bash
#       ├── smoke/*.bats
#       └── integration/*.bats
#
# Paths to bats-support / bats-assert match the Dockerfile.test install
# location (/usr/lib/bats-*). Tests run inside Docker per CLAUDE.md
# "驗證一律走 Docker"; running these specs on the host directly is not
# supported.

# Resolve hook + script directories once. BATS_TEST_DIRNAME is the dir
# of the .bats spec sourcing this helper.
HOOKS_DIR="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
export HOOKS_DIR
SCRIPTS_DIR="$(cd "${BATS_TEST_DIRNAME}/../../../scripts" && pwd)"
export SCRIPTS_DIR

# shellcheck disable=SC1091
load '/usr/lib/bats-support/load'
# shellcheck disable=SC1091
load '/usr/lib/bats-assert/load'

# hook <name> — print absolute path to a hook script.
hook() {
  echo "${HOOKS_DIR}/$1"
}

# script <name> — print absolute path to a permanent helper script under
# .claude/scripts/.
script() {
  echo "${SCRIPTS_DIR}/$1"
}

# assert_silent — assert hook exited 0 and produced no stdout (no fire path).
assert_silent() {
  assert_success
  if [[ -n "${output}" ]]; then
    echo "expected silent, got output: ${output}" >&2
    return 1
  fi
}

# assert_permission_decision <expected> — assert hook exited 0 and stdout
# is JSON whose .hookSpecificOutput.permissionDecision matches <expected>.
# Used for PreToolUse hooks that programmatically allow / deny / ask.
assert_permission_decision() {
  local expected="$1"
  assert_success
  if [[ -z "${output}" ]]; then
    echo "expected permissionDecision='${expected}', got empty output" >&2
    return 1
  fi
  local got
  got="$(echo "${output}" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null || true)"
  if [[ "${got}" != "${expected}" ]]; then
    echo "expected permissionDecision='${expected}', got: '${got}'" >&2
    return 1
  fi
}

# assert_message_contains <needle> — assert hook exited 0 and stdout is JSON
# with .systemMessage containing the needle substring.
assert_message_contains() {
  local needle="$1"
  assert_success
  if [[ -z "${output}" ]]; then
    echo "expected systemMessage containing '${needle}', got empty output" >&2
    return 1
  fi
  local msg
  msg="$(echo "${output}" | jq -r '.systemMessage // empty' 2>/dev/null || true)"
  if [[ "${msg}" != *"${needle}"* ]]; then
    echo "expected systemMessage to contain '${needle}', got: ${msg}" >&2
    return 1
  fi
}

# mktemp_repo [opts] — create a temp git repo and echo its path. opts may
# include "changelog" to seed doc/changelog/CHANGELOG.md.
mktemp_repo() {
  local opts="${1:-}"
  local dir
  dir="$(mktemp -d)"
  (
    cd "${dir}" || exit 1
    git init -q -b main
    git config user.email "t@t"
    git config user.name "t"
    case "${opts}" in
      *changelog*)
        mkdir -p doc/changelog
        echo "# Changelog" > doc/changelog/CHANGELOG.md
        ;;
    esac
    mkdir -p script
    echo "echo init" > script/foo.sh
    git add -A >/dev/null
    git commit -q -m init
  ) >/dev/null
  echo "${dir}"
}

# mktemp_test_md_repo <bats_count> <claimed_count> — create a repo with
# a single bats file holding <bats_count> @test and a TEST.md claiming
# <claimed_count>. Echoes repo path.
mktemp_test_md_repo() {
  local bats_count="$1"
  local claimed_count="$2"
  local dir
  dir="$(mktemp -d)"
  mkdir -p "${dir}/test/unit" "${dir}/doc/test"
  {
    echo '#!/usr/bin/env bats'
    local i=0
    while (( i < bats_count )); do
      echo "@test \"t${i}\" { :; }"
      i=$((i + 1))
    done
  } > "${dir}/test/unit/setup_spec.bats"
  cat > "${dir}/doc/test/TEST.md" <<EOF
# Tests

### test/unit/setup_spec.bats (${claimed_count})
EOF
  echo "${dir}"
}
