---
name: .base subtree 升級先用 make
description: 升級 .base subtree 一律 make 優先；raw ./.base/upgrade.sh 是 fallback 但 enforce_make_first_upgrade.sh hook 會 BLOCK 直到 checkpoint ACK
type: feedback
originSessionId: 33bd5c5e-e564-48bf-b038-bcaab5b8b2f6
---
升級 `.base` subtree 一律先用 make,只在 make 不可用 / target 出問題時才退回 `./.base/upgrade.sh` (raw .sh 在現代 repo 會被 `enforce_make_first_upgrade.sh` hook BLOCK,須走 checkpoint protocol ack 才能放行,refs ADR-00000002 / #120 / #139):

- 升到最新:`make -f Makefile.ci upgrade`
- 指定版本:`make -f Makefile.ci upgrade VERSION=vX.Y.Z`
- 檢查新版:`make -f Makefile.ci upgrade-check`
- Legacy fallback (被 hook 擋,需要 ACK):`./.base/upgrade.sh [vX.Y.Z]`,舊版 checkout 仍可能用 `./template/upgrade.sh`
- 批次跨 repo 升級:`/batch-base-upgrade` (重新命名自 `/batch-template-upgrade`,refs #146)

**Why:** 使用者要求把 make 設成主要入口,sh 留作 fallback。原本 Makefile.ci 的
`upgrade` target 只支援最新版(不能傳版本),所以順便擴充 recipe 為
`./upgrade.sh $(VERSION)`,讓 make 涵蓋指定版本的常見情境,sh fallback 才不會變成
日常必跑。後續 #120 / #139 把這條規則 promote 成 hook BLOCK,從 prose 升級成
enforcement。

**How to apply:** 跟使用者討論升級流程、寫文件範例、跑實際升級時都套這個順序。
範例指令、CLAUDE.md Workflows 列表、template README「Updating」章節都要以 make 為主。
相關: [[feedback_base_subtree_upgrade]] -- init.sh 自動 resync 的細節。
