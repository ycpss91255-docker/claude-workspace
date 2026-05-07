#!/usr/bin/env bats

load '../lib/test_helper'

setup() {
  REPO="$(mktemp -d)"
  for sh in build run exec stop; do
    echo '#!/bin/sh' > "${REPO}/${sh}.sh"
    chmod +x "${REPO}/${sh}.sh"
  done
  REPO_BARE="$(mktemp -d)"
}

teardown() {
  rm -rf "${REPO}" "${REPO_BARE}"
}

@test "deny docker build when build.sh exists" {
  run "$(hook check_prefer_dot_sh.sh)" \
    <<< "{\"tool_input\":{\"command\":\"docker build -t foo .\"},\"cwd\":\"${REPO}\"}"
  assert_permission_decision "deny"
  assert_message_contains "./build.sh"
}

@test "deny docker run when run.sh exists" {
  run "$(hook check_prefer_dot_sh.sh)" \
    <<< "{\"tool_input\":{\"command\":\"docker run --rm foo\"},\"cwd\":\"${REPO}\"}"
  assert_permission_decision "deny"
  assert_message_contains "./run.sh"
}

@test "deny docker exec when exec.sh exists" {
  run "$(hook check_prefer_dot_sh.sh)" \
    <<< "{\"tool_input\":{\"command\":\"docker exec -it foo bash\"},\"cwd\":\"${REPO}\"}"
  assert_permission_decision "deny"
  assert_message_contains "./exec.sh"
}

@test "deny docker stop when stop.sh exists" {
  run "$(hook check_prefer_dot_sh.sh)" \
    <<< "{\"tool_input\":{\"command\":\"docker stop foo\"},\"cwd\":\"${REPO}\"}"
  assert_permission_decision "deny"
  assert_message_contains "./stop.sh"
}

@test "deny docker compose up → run.sh" {
  run "$(hook check_prefer_dot_sh.sh)" \
    <<< "{\"tool_input\":{\"command\":\"docker compose up -d\"},\"cwd\":\"${REPO}\"}"
  assert_permission_decision "deny"
  assert_message_contains "./run.sh"
}

@test "deny docker compose down → stop.sh" {
  run "$(hook check_prefer_dot_sh.sh)" \
    <<< "{\"tool_input\":{\"command\":\"docker compose down\"},\"cwd\":\"${REPO}\"}"
  assert_permission_decision "deny"
  assert_message_contains "./stop.sh"
}

@test "deny docker compose build → build.sh" {
  run "$(hook check_prefer_dot_sh.sh)" \
    <<< "{\"tool_input\":{\"command\":\"docker compose build\"},\"cwd\":\"${REPO}\"}"
  assert_permission_decision "deny"
  assert_message_contains "./build.sh"
}

@test "deny docker compose exec → exec.sh" {
  run "$(hook check_prefer_dot_sh.sh)" \
    <<< "{\"tool_input\":{\"command\":\"docker compose exec foo bash\"},\"cwd\":\"${REPO}\"}"
  assert_permission_decision "deny"
  assert_message_contains "./exec.sh"
}

@test "deny docker compose run → run.sh" {
  run "$(hook check_prefer_dot_sh.sh)" \
    <<< "{\"tool_input\":{\"command\":\"docker compose run foo\"},\"cwd\":\"${REPO}\"}"
  assert_permission_decision "deny"
  assert_message_contains "./run.sh"
}

@test "ask when docker build but no build.sh wrapper" {
  run "$(hook check_prefer_dot_sh.sh)" \
    <<< "{\"tool_input\":{\"command\":\"docker build -t foo .\"},\"cwd\":\"${REPO_BARE}\"}"
  assert_permission_decision "ask"
}

@test "ask when docker compose up but no run.sh wrapper" {
  run "$(hook check_prefer_dot_sh.sh)" \
    <<< "{\"tool_input\":{\"command\":\"docker compose up\"},\"cwd\":\"${REPO_BARE}\"}"
  assert_permission_decision "ask"
}

@test "silent on read-only docker subcommand (ps)" {
  run "$(hook check_prefer_dot_sh.sh)" \
    <<< "{\"tool_input\":{\"command\":\"docker ps -a\"},\"cwd\":\"${REPO}\"}"
  assert_silent
}

@test "silent on read-only docker subcommand (images)" {
  run "$(hook check_prefer_dot_sh.sh)" \
    <<< "{\"tool_input\":{\"command\":\"docker images\"},\"cwd\":\"${REPO}\"}"
  assert_silent
}

@test "silent on docker pull (download is harmless)" {
  run "$(hook check_prefer_dot_sh.sh)" \
    <<< "{\"tool_input\":{\"command\":\"docker pull alpine\"},\"cwd\":\"${REPO}\"}"
  assert_silent
}

@test "silent on docker rm (already in permissions.ask)" {
  run "$(hook check_prefer_dot_sh.sh)" \
    <<< "{\"tool_input\":{\"command\":\"docker rm -f foo\"},\"cwd\":\"${REPO}\"}"
  assert_silent
}

@test "silent on non-docker command" {
  run "$(hook check_prefer_dot_sh.sh)" \
    <<< "{\"tool_input\":{\"command\":\"git status\"},\"cwd\":\"${REPO}\"}"
  assert_silent
}

@test "silent on make (subprocess docker is not visible to Claude)" {
  run "$(hook check_prefer_dot_sh.sh)" \
    <<< "{\"tool_input\":{\"command\":\"make -f Makefile.ci test\"},\"cwd\":\"${REPO}\"}"
  assert_silent
}

@test "strips single env-prefix and matches docker build" {
  run "$(hook check_prefer_dot_sh.sh)" \
    <<< "{\"tool_input\":{\"command\":\"BUILDKIT_PROGRESS=plain docker build -t foo .\"},\"cwd\":\"${REPO}\"}"
  assert_permission_decision "deny"
  assert_message_contains "./build.sh"
}

@test "strips multiple env-prefixes and matches docker build" {
  run "$(hook check_prefer_dot_sh.sh)" \
    <<< "{\"tool_input\":{\"command\":\"DOCKER_BUILDKIT=1 BUILDKIT_PROGRESS=plain docker build .\"},\"cwd\":\"${REPO}\"}"
  assert_permission_decision "deny"
}
