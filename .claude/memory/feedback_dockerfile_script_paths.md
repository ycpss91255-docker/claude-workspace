---
name: Consumer Dockerfile 不要硬寫 template 腳本路徑
description: Consumer Dockerfile 應該用 *.sh glob 從 repo root 拉腳本,不要寫 template/script/docker/*.sh 等具體路徑
type: feedback
originSessionId: 21206d57-34a2-4c93-91d9-123d82ae07b1
---
Consumer repo 的 Dockerfile 在 `/lint` stage 拉腳本時,**應該用 `COPY *.sh /lint/`** 從 repo 根目錄(symlink)拉,**不要寫**:
```dockerfile
COPY template/build.sh template/run.sh template/exec.sh template/stop.sh /lint/      # 舊 v0.5.0 路徑,壞
COPY template/script/docker/build.sh ... /lint/                                      # 寫死新路徑,下次搬還會壞
```

**Why:** 2026-04-09 批次升級到 v0.7.1 時,17 repos 中有 2 個(`app/ros1_bridge`、`app/urg_node_humble`)Dockerfile 把 v0.5.0 時代的 `template/build.sh` 路徑寫死了。template 在 v0.6 把腳本搬到 `template/script/docker/`,這 2 個 repo build 直接炸 `"/template/stop.sh": not found`。其他 15 個用 `COPY *.sh /lint/` 都沒事 — 因為 root 層 symlinks 在 init.sh 重整後永遠指向正確位置。

**How to apply:**
- 新 repo 一律用 `COPY *.sh /lint/`(或 `COPY [repo-root globs] /lint/`)
- 看到 consumer Dockerfile 寫 `COPY template/<path>/<script>.sh` 要主動提議改成 glob
- 還沒修的 repos:目前只有 `app/ros1_bridge` 和 `app/urg_node_humble` 已修(2026-04-09),其他 repos 沒有此問題
- 同樣原則也適用於 `COPY template/test/smoke/*.bats` 等 — 路徑越具體,template 重構越容易打到 consumer
