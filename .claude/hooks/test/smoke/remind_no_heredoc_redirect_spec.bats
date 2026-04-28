#!/usr/bin/env bats

load '../lib/test_helper'

@test "fires on cat <<'EOF' > /path" {
  run "$(hook remind_no_heredoc_redirect.sh)" <<< '{"tool_input":{"command":"cat <<'\''EOF'\'' > /tmp/x.sh\necho hi\nEOF"}}'
  assert_message_contains "Heredoc-to-file redirect"
}

@test "fires on cat << EOF > /path (no quotes)" {
  run "$(hook remind_no_heredoc_redirect.sh)" <<< '{"tool_input":{"command":"cat << EOF > /tmp/x.md\nhello\nEOF"}}'
  assert_message_contains "Heredoc-to-file redirect"
}

@test "fires on cat <<-EOF > /path (dash form)" {
  run "$(hook remind_no_heredoc_redirect.sh)" <<< '{"tool_input":{"command":"cat <<-EOF > /tmp/y\n\thello\nEOF"}}'
  assert_message_contains "Heredoc-to-file redirect"
}

@test "fires on cat <<EOF >> /path (append redirect)" {
  run "$(hook remind_no_heredoc_redirect.sh)" <<< '{"tool_input":{"command":"cat <<EOF >> /tmp/log\nentry\nEOF"}}'
  assert_message_contains "Heredoc-to-file redirect"
}

@test "silent on plain echo > file (no heredoc)" {
  run "$(hook remind_no_heredoc_redirect.sh)" <<< '{"tool_input":{"command":"echo hello > /tmp/x"}}'
  assert_silent
}

@test "silent on cat /file > /other (no heredoc)" {
  run "$(hook remind_no_heredoc_redirect.sh)" <<< '{"tool_input":{"command":"cat /tmp/a > /tmp/b"}}'
  assert_silent
}

@test "silent on heredoc piped to command (no file redirect)" {
  run "$(hook remind_no_heredoc_redirect.sh)" <<< '{"tool_input":{"command":"cat <<EOF | sh\necho hi\nEOF"}}'
  assert_silent
}
