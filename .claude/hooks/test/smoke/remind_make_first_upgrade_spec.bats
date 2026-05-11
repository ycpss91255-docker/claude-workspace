#!/usr/bin/env bats

load '../lib/test_helper'

setup() {
  REPO="$(mktemp -d)"
  cd "${REPO}"
  git init -q -b main
  git config user.email t@t
  git config user.name t
  mkdir -p .base
  cat > Makefile.ci <<'EOF'
.PHONY: upgrade

upgrade:
	./.base/upgrade.sh $(VERSION)
EOF
  cat > .base/upgrade.sh <<'EOF'
#!/usr/bin/env bash
echo "stub upgrade.sh"
EOF
  chmod +x .base/upgrade.sh
  git add -A >/dev/null
  git commit -q -m init >/dev/null
  cd - >/dev/null
}

teardown() {
  rm -rf "${REPO}"
}

@test "fires on ./.base/upgrade.sh when Makefile.ci has upgrade target" {
  run "$(hook remind_make_first_upgrade.sh)" \
    <<< "{\"tool_input\":{\"command\":\"./.base/upgrade.sh v0.18.2\"},\"cwd\":\"${REPO}\"}"
  assert_message_contains "make -f Makefile.ci upgrade"
  assert_message_contains "VERSION=v0.18.2"
}

@test "fires on bare .base/upgrade.sh (no leading ./)" {
  run "$(hook remind_make_first_upgrade.sh)" \
    <<< "{\"tool_input\":{\"command\":\".base/upgrade.sh\"},\"cwd\":\"${REPO}\"}"
  assert_message_contains "make -f Makefile.ci upgrade"
}

@test "fires on absolute path .base/upgrade.sh" {
  run "$(hook remind_make_first_upgrade.sh)" \
    <<< "{\"tool_input\":{\"command\":\"${REPO}/.base/upgrade.sh v0.18.3\"},\"cwd\":\"${REPO}\"}"
  assert_message_contains "make -f Makefile.ci upgrade"
  assert_message_contains "VERSION=v0.18.3"
}

@test "silent when Makefile.ci absent (no make wrapper available)" {
  local repo
  repo="$(mktemp -d)"
  cd "${repo}"
  git init -q -b main
  git config user.email t@t
  git config user.name t
  mkdir -p .base
  echo "#!/bin/sh" > .base/upgrade.sh
  chmod +x .base/upgrade.sh
  git add -A >/dev/null
  git commit -q -m init >/dev/null
  cd - >/dev/null
  run "$(hook remind_make_first_upgrade.sh)" \
    <<< "{\"tool_input\":{\"command\":\"./.base/upgrade.sh v0.18.2\"},\"cwd\":\"${repo}\"}"
  assert_silent
  rm -rf "${repo}"
}

@test "silent when Makefile.ci has no upgrade target" {
  cat > "${REPO}/Makefile.ci" <<'EOF'
.PHONY: test

test:
	echo test
EOF
  run "$(hook remind_make_first_upgrade.sh)" \
    <<< "{\"tool_input\":{\"command\":\"./.base/upgrade.sh v0.18.2\"},\"cwd\":\"${REPO}\"}"
  assert_silent
}

@test "silent on make -f Makefile.ci upgrade (already going through wrapper)" {
  run "$(hook remind_make_first_upgrade.sh)" \
    <<< "{\"tool_input\":{\"command\":\"make -f Makefile.ci upgrade VERSION=v0.18.2\"},\"cwd\":\"${REPO}\"}"
  assert_silent
}

@test "silent on unrelated commands" {
  run "$(hook remind_make_first_upgrade.sh)" \
    <<< "{\"tool_input\":{\"command\":\"git status\"},\"cwd\":\"${REPO}\"}"
  assert_silent
}

@test "silent on script with similar name (foo/upgrade.sh)" {
  mkdir -p "${REPO}/foo"
  echo "#!/bin/sh" > "${REPO}/foo/upgrade.sh"
  chmod +x "${REPO}/foo/upgrade.sh"
  run "$(hook remind_make_first_upgrade.sh)" \
    <<< "{\"tool_input\":{\"command\":\"./foo/upgrade.sh\"},\"cwd\":\"${REPO}\"}"
  assert_silent
}
