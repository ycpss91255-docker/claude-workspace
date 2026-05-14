---
name: Subagent sandbox 比主 session 嚴 — 不適合批次 git 操作
description: 派 subagent 跑 git checkout / 自製腳本會被 Bash sandbox 擋,批次檔案系統 mutation 用主 session 前景 loop
type: feedback
originSessionId: 21206d57-34a2-4c93-91d9-123d82ae07b1
---
派 `general-purpose` subagent 執行 `git checkout` / `git pull` / `./template/upgrade.sh` 之類的指令會被 Bash sandbox 擋下(主 session 我自己跑沒事)。**批次操作 consumer repos(subtree pull、symlink 刷新、commit、push、create PR)應該在主 session 用前景 bash loop 跑,不要 dispatch subagent**。

**Why:** 2026-04-09 批次升級 17 個 repos 到 v0.7.1,我同時派 3 個平行 agent(env / app / agent 各一)。3 個全部卡在第一個 `git checkout main` 或 `./template/upgrade.sh`,只能完成 `gh pr close`(read-ish)。每個 agent 都浪費了一輪 token + 數十秒等待,最後還是回到主 session 用一個 bash for-loop 跑完。

**How to apply:**
- Subagent 適合:read-only research(grep、find、讀檔)、long-running 並行思考任務
- Subagent 不適合:任何涉及 `git mutating commands`、自製 `.sh` 腳本執行、`gh pr merge`、`docker` 指令
- 批次操作 N 個 repos 時:寫一個 bash for-loop 在主 session 前景跑(用 `set +e` 讓單一失敗不中斷),完整 N=17 repos 大約 30-60 秒
- 如果 task 需要平行分散(例如測試 + lint + research 三條獨立軌道),把 mutation 留主 session,research 派 subagent
