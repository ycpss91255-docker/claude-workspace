---
name: auto-invoke-pr-on-code-change
description: 使用者不會顯式打 /pr。當使用者描述「處理/修/加 xxx」型 code 變更時，Claude 必須主動透過 Skill 工具呼叫 /pr 走 PR 流程，不要 ad-hoc Edit + 直接 commit。
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 57c42783-dd59-4158-905a-b8d90ffa7347
---

使用者描述需求時不會打 `/pr` slash command — 而是用自然語言（「處理 issue #X」「修 ROS bridge build 失敗」「幫我加 --auto flag」「重構 setup.sh」「同步 README」等）。Claude 必須**主動辨認這是 code-change 請求**並透過 Skill 工具呼叫 `/pr`，走 branch → commit → push → PR open → auto-merge 完整流程。

**Why:** CLAUDE.md 的「Process discipline — slash command / skill 優先於 ad-hoc 執行」已經明文要求走 documented entry，但實務上容易因為「user 沒打 /pr」就漏掉。`/pr` 涵蓋的步驟（branch 命名、regression test、conventional commit、auto-merge）若 ad-hoc 執行很容易跳過其中一步（refs CLAUDE.md 範例：`/release` v0.18.x 漏 `.version` bump 那次）。

**How to apply:**

- 任何會修改 `.sh` / `Dockerfile` / `compose.yaml` / `.github/workflows/*` / `README*.md` / `CLAUDE.md` / `.claude/commands/*` / `.claude/skills/*` / `.claude/hooks/*` / `.claude/scripts/*` 的 user 請求 → 先檢查是否該套 `/pr`，預設答案是「該套」
- 例外（直接 Edit 不走 /pr）：
  - User 明確說「直接改」「不用開 PR」「先 dry-run 不 commit」
  - Trivial 一次性檢視（不會留 diff）
  - Doc-only 修改 + 在 main branch 上動已被 CLAUDE.md 明文豁免（「Only pure documentation updates ... can be pushed directly to main」）— 但仍建議先確認 user 偏好
- 其他 slash command 也適用同邏輯（`/release` `/batch-template-upgrade` `/new-repo` `/issue-fix` `/doc-sync`）— user 描述對應情境時直接 Skill 呼叫，不要憑 ad-hoc gh / git 操作湊一個流程

相關：[[no-claude-md-edit-in-sandbox]]、[[use-worktree]]、[[make-first-upgrade]]
