---
name: Template subtree 升級後一定要跑 init.sh
description: 升級 docker template subtree 後必須執行 ./template/init.sh,否則 root symlinks 仍指向舊腳本路徑
type: feedback
originSessionId: 21206d57-34a2-4c93-91d9-123d82ae07b1
---
升級 consumer repo 的 template subtree 後,**一定要執行 `./template/init.sh`** 重新建立 root 層的 symlinks(`build.sh` / `run.sh` / `exec.sh` / `stop.sh` / `Makefile`),即使你只是「改 .template_version」或只跑了 `git subtree pull`。

**Why:** 2026-04-09 批次升級 17 repos 到 v0.7.1 時,subagent 用 `git -C <repo> subtree pull` 替代 `cd && upgrade.sh`,跳過了 init.sh,結果 4 個 agent repos 的 symlinks 仍指向 `template/build.sh`(v0.5.0 layout),但檔案實際在 `template/script/docker/build.sh`。CI 在 Dockerfile 的 `COPY *.sh /lint/` 階段炸:`"/build.sh": not found`。

**How to apply:**
- 任何時候對 consumer repo 做 subtree pull,後續流程的最後一步都是 `./template/init.sh`(它有 idempotent 偵測,既存 repo 只重建 symlinks)
- 寫批次升級腳本時,init.sh 跟 subtree pull / 版本檔更新放在同一個區塊,不可省略
- 官方 `template/upgrade.sh` v0.6.6+ 已內建 init.sh 步驟;只要走它就安全。手動 subtree pull 才需要記得補
- 驗證:`ls -la build.sh` 應指向 `template/script/docker/build.sh`(v0.6+),不是 `template/build.sh`(v0.5.0 殘留)
