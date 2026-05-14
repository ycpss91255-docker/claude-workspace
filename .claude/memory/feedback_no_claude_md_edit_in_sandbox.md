---
name: Sandbox 內禁編輯 CLAUDE.md（除非明確同意）
description: 在 sandbox session 中不要用 Edit / Write / git 等工具修改 CLAUDE.md，必須先取得 user 明確同意才能動
type: feedback
originSessionId: 57c42783-dd59-4158-905a-b8d90ffa7347
---
在 sandbox session 中，**不要**對 `CLAUDE.md` 執行任何編輯（Edit / Write / `git mv` / `sed` / 任何工具）— 必須先取得 user 明確同意才能動。

**Why:** CLAUDE.md 是高敏感度的 single source of truth，會被自動載進每次 session 的 system prompt；錯誤改動會污染後續所有 session 的 behavior，且 user 觀察到「補強 CLAUDE.md 的敘述」太頻繁、容易膨脹。所以這條 rule 額外把 CLAUDE.md 提到「需事前同意」的層級，比一般檔案更嚴。

**How to apply:**
- 任何提案動到 CLAUDE.md（新增 row、修改 wording、調整目錄樹），先用文字提案完整 diff 讓 user 確認，得到「ok / 做」之類明確同意才動手
- 對其他檔案（TEST.md / CHANGELOG / settings / 程式碼）不受這條限制 — 該做就做
- 如果 user 在同一輪對話已經明確同意（例如「做 C」其中 C 包含 CLAUDE.md 編輯），那次同意視為授權；不要拿過去同意的範圍套用到新的 CLAUDE.md 改動上
- 例外：已經跑了 Edit 但被 revert / 誤動，user 又要求「幫我回復」算 explicit 還原同意
