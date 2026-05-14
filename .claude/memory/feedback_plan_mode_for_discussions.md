---
name: plan-mode-for-discussions
description: "For any multi-step proposal / discussion (issue body draft, PR body draft, design choice review, refactoring plan), use Plan mode (ExitPlanMode tool) rather than inline chat drafts. Single-line confirmations and quick yes/no questions still go through chat. The threshold is \"is there something to approve as a unit?\" -- if yes, Plan mode."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 57c42783-dd59-4158-905a-b8d90ffa7347
---

For multi-step proposals where the user needs to review and approve as a unit, **use Plan mode** (`ExitPlanMode` tool) rather than dumping the draft inline in chat.

**Why:** Inline chat drafts get buried in scroll history, mix with other tool output, and lack a clear approve/reject affordance. Plan mode has dedicated UI for review, can be edited, and produces a clean go/no-go boundary.

**How to apply (refined 2026-05-14 per user feedback):**

**Use Plan mode** only when BOTH conditions hold:

1. **Big task** -- estimated work > ~30 min, or > 3 files touched, or > 1 hook/skill/script added
2. **Ambiguous scope or approach** -- decisions not yet made, multiple viable options, scope could expand

If both hold → enter Plan mode, formal proposal + approval.

**Skip Plan mode (proceed directly) when:**

- Task is small (1-2 files, well-bounded)
- Decisions already made (e.g. via AskUserQuestion answers in this conversation)
- The "discussion" is just a sign-off on already-clear content (one-line yes/no)
- It's a chat-level confirmation / status update / brief clarification

**Concrete examples:**

- Move 14 files + write 1 helper + doc-sync with all decisions pre-made → small + clear → just do it (PR review covers final approval).
- Refactor the 4 batch scripts across 3 different concerns with unclear naming → big + ambiguous → Plan mode.
- "Should I rename X to Y?" → chat OK.
- 7-phase verification skill where the phase definitions need user input → ambiguous → Plan mode.

**Mechanism:** I cannot unilaterally enter Plan mode -- user has to Shift+Tab into it. So when I judge "this needs Plan mode", I tell the user "please Shift+Tab into Plan mode for this", then I draft the plan to the plan file path and call `ExitPlanMode` for approval UI.

**Mechanism:** I can invoke `ExitPlanMode` with the plan markdown content. The user gets the approve/reject UI. On approval, I execute. (If I'm not in formal plan mode, this still works as a structured-proposal mechanism.)

**Interaction with [[bilingual-issue-pr-draft]]:** The bilingual rule says draft in zh-TW first. The plan-mode rule says use Plan mode for the draft. They compose: the **zh-TW draft is the plan content**. User reviews in zh-TW via Plan mode, approves, then I translate + submit via gh.

**Anti-pattern observed (2026-05-14):** Drafted the memory-symlink issue body inline in chat with a "要不要改" prompt. Should have been a Plan mode proposal -- user explicitly called this out and asked for Plan mode going forward.
