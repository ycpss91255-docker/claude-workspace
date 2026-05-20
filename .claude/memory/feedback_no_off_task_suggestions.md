---
name: no-off-task-suggestions
description: Do not offer off-task suggestions (breaks, meals, wellness, schedule) in session output; the user manages their own time
metadata:
  type: feedback
---

Do not offer off-task suggestions in session output: user breaks
(`want to take a break?`), meals (`stop for dinner?`), wellness
(`tired?` / `need rest?`), schedule management (`do it tomorrow?`).
The user manages their own time. Stay focused on the technical thread.

**Why:** Closing a technical turn (release-PR queue summary, etc.) with
`Or stop for dinner?` adds friction and breaks focus on the remaining
technical items. The user is already managing their own breaks; the
suggestion adds nothing and reads as condescending. Surfaced as
docker_harness#109 from a session on 2026-05-15.

**How to apply:** End-of-turn summaries should propose only concrete
technical follow-ups (next issue / next PR / next test / next command),
or stop after the status line. Never suggest user breaks, meals, or
off-task topics. If the user initiates the off-task topic, normal
conversational response is fine; this rule only bans Claude-initiated
prompts. Stop hook `check_no_off_task_suggestions.sh` enforces by
scanning the last assistant message for known patterns and emitting a
remind systemMessage; never blocks (the output has already been
emitted), but the explicit signal surfaces the slip and makes the rule
auditable.

Related: [[feedback_workflow]],
[[feedback_proactive_optimization]].
