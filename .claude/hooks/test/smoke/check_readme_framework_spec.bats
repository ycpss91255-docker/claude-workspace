#!/usr/bin/env bats

load '../lib/test_helper'

# mktemp_downstream_repo <category> <repo_name> — make a fake docker
# monorepo layout under TMP/<category>/<repo_name>/ with empty
# README.md + 3 translation stubs. Echoes the repo root.
# <category> must be agent / app / env (matching the hook's category list).
mktemp_downstream_repo() {
  local category="$1"
  local repo="$2"
  local root
  root="$(mktemp -d)"
  mkdir -p "${root}/${category}/${repo}/doc"
  : > "${root}/${category}/${repo}/README.md"
  : > "${root}/${category}/${repo}/doc/README.zh-TW.md"
  : > "${root}/${category}/${repo}/doc/README.zh-CN.md"
  : > "${root}/${category}/${repo}/doc/README.ja.md"
  echo "${root}/${category}/${repo}"
}

# write_aligned <readme_path> — write a minimally framework-compliant
# README to <readme_path>. All 6 checks should pass.
write_aligned() {
  local p="$1"
  cat > "${p}" <<'EOF'
# Some Repo

[![CI](https://github.com/ycpss91255-docker/some_repo/actions/workflows/main.yaml/badge.svg)](https://github.com/ycpss91255-docker/some_repo/actions/workflows/main.yaml)

One-liner.

**[English](README.md)** | **[繁體中文](doc/README.zh-TW.md)** | **[简体中文](doc/README.zh-CN.md)** | **[日本語](doc/README.ja.md)**

## TL;DR

```bash
./build.sh && ./run.sh
```

## Smoke Tests

See [TEST.md](doc/test/TEST.md) for details.
EOF
}

@test "silent on a fully aligned English README" {
  local repo
  repo="$(mktemp_downstream_repo agent foo)"
  write_aligned "${repo}/README.md"
  write_aligned "${repo}/doc/README.zh-TW.md"
  write_aligned "${repo}/doc/README.zh-CN.md"
  write_aligned "${repo}/doc/README.ja.md"
  run "$(hook check_readme_framework.sh)" <<< "{\"tool_input\":{\"file_path\":\"${repo}/README.md\"}}"
  assert_silent
  rm -rf "${repo%/*/*}"
}

@test "[1] fires on missing CI badge" {
  local repo
  repo="$(mktemp_downstream_repo agent foo)"
  write_aligned "${repo}/README.md"
  # Strip the badge line.
  sed -i '/badge.svg/d' "${repo}/README.md"
  run "$(hook check_readme_framework.sh)" <<< "{\"tool_input\":{\"file_path\":\"${repo}/README.md\"}}"
  assert_message_contains "[1] missing CI badge"
  rm -rf "${repo%/*/*}"
}

@test "[2] fires on missing 4-language link" {
  local repo
  repo="$(mktemp_downstream_repo agent foo)"
  write_aligned "${repo}/README.md"
  sed -i '/\*\*\[English\]/d' "${repo}/README.md"
  run "$(hook check_readme_framework.sh)" <<< "{\"tool_input\":{\"file_path\":\"${repo}/README.md\"}}"
  assert_message_contains "[2] missing 4-language switch link"
  rm -rf "${repo%/*/*}"
}

@test "[3] fires when TL;DR is a blockquote" {
  local repo
  repo="$(mktemp_downstream_repo agent foo)"
  write_aligned "${repo}/README.md"
  printf '\n> **TL;DR** legacy blockquote\n' >> "${repo}/README.md"
  run "$(hook check_readme_framework.sh)" <<< "{\"tool_input\":{\"file_path\":\"${repo}/README.md\"}}"
  assert_message_contains "[3] TL;DR is a blockquote"
  rm -rf "${repo%/*/*}"
}

@test "[4] fires on stale template/build.sh symlink target" {
  local repo
  repo="$(mktemp_downstream_repo app bar)"
  write_aligned "${repo}/README.md"
  printf '\nbuild.sh -> template/build.sh    # Symlink\n' >> "${repo}/README.md"
  run "$(hook check_readme_framework.sh)" <<< "{\"tool_input\":{\"file_path\":\"${repo}/README.md\"}}"
  assert_message_contains "stale path 'template/build.sh'"
  rm -rf "${repo%/*/*}"
}

@test "[5] fires on .template_version reference" {
  local repo
  repo="$(mktemp_downstream_repo env baz)"
  write_aligned "${repo}/README.md"
  printf '\n.template_version            # Template subtree version\n' >> "${repo}/README.md"
  run "$(hook check_readme_framework.sh)" <<< "{\"tool_input\":{\"file_path\":\"${repo}/README.md\"}}"
  assert_message_contains "[5] obsolete '.template_version' reference"
  rm -rf "${repo%/*/*}"
}

@test "[6] fires on missing TEST.md link" {
  local repo
  repo="$(mktemp_downstream_repo agent foo)"
  write_aligned "${repo}/README.md"
  sed -i '/doc\/test\/TEST.md/d' "${repo}/README.md"
  run "$(hook check_readme_framework.sh)" <<< "{\"tool_input\":{\"file_path\":\"${repo}/README.md\"}}"
  assert_message_contains "[6] missing 'See [TEST.md]"
  rm -rf "${repo%/*/*}"
}

@test "[drift] fires when a translation has no CI badge while English does" {
  local repo
  repo="$(mktemp_downstream_repo app bar)"
  write_aligned "${repo}/README.md"
  # zh-TW intentionally left empty (no badge), zh-CN + ja aligned.
  : > "${repo}/doc/README.zh-TW.md"
  write_aligned "${repo}/doc/README.zh-CN.md"
  write_aligned "${repo}/doc/README.ja.md"
  run "$(hook check_readme_framework.sh)" <<< "{\"tool_input\":{\"file_path\":\"${repo}/README.md\"}}"
  assert_message_contains "[drift] doc/README.zh-TW.md has not adopted the framework yet"
  rm -rf "${repo%/*/*}"
}

@test "[drift] fires when a translation file is missing entirely" {
  local repo
  repo="$(mktemp_downstream_repo agent foo)"
  write_aligned "${repo}/README.md"
  rm "${repo}/doc/README.ja.md"
  write_aligned "${repo}/doc/README.zh-TW.md"
  write_aligned "${repo}/doc/README.zh-CN.md"
  run "$(hook check_readme_framework.sh)" <<< "{\"tool_input\":{\"file_path\":\"${repo}/README.md\"}}"
  assert_message_contains "missing translation: doc/README.ja.md"
  rm -rf "${repo%/*/*}"
}

@test "checks a translation file directly with [zh-TW] label" {
  local repo
  repo="$(mktemp_downstream_repo env baz)"
  write_aligned "${repo}/README.md"
  : > "${repo}/doc/README.zh-TW.md"
  run "$(hook check_readme_framework.sh)" <<< "{\"tool_input\":{\"file_path\":\"${repo}/doc/README.zh-TW.md\"}}"
  assert_message_contains "[zh-TW] [1] missing CI badge"
  rm -rf "${repo%/*/*}"
}

@test "silent when editing template/README.md (the framework reference itself)" {
  local root
  root="$(mktemp -d)"
  mkdir -p "${root}/template"
  cat > "${root}/template/README.md" <<'EOF'
# template
no badge no nothing
EOF
  run "$(hook check_readme_framework.sh)" <<< "{\"tool_input\":{\"file_path\":\"${root}/template/README.md\"}}"
  assert_silent
  rm -rf "${root}"
}

@test "silent when editing archive/<repo>/README.md (read-only archive)" {
  local root
  root="$(mktemp -d)"
  mkdir -p "${root}/archive/old_repo"
  : > "${root}/archive/old_repo/README.md"
  run "$(hook check_readme_framework.sh)" <<< "{\"tool_input\":{\"file_path\":\"${root}/archive/old_repo/README.md\"}}"
  assert_silent
  rm -rf "${root}"
}

@test "silent when editing a non-README file" {
  run "$(hook check_readme_framework.sh)" <<< '{"tool_input":{"file_path":"/tmp/not_a_readme.txt"}}'
  assert_silent
}

@test "silent on multi_run/README.md when fully aligned" {
  local root
  root="$(mktemp -d)"
  mkdir -p "${root}/multi_run/doc"
  write_aligned "${root}/multi_run/README.md"
  write_aligned "${root}/multi_run/doc/README.zh-TW.md"
  write_aligned "${root}/multi_run/doc/README.zh-CN.md"
  write_aligned "${root}/multi_run/doc/README.ja.md"
  run "$(hook check_readme_framework.sh)" <<< "{\"tool_input\":{\"file_path\":\"${root}/multi_run/README.md\"}}"
  assert_silent
  rm -rf "${root}"
}
