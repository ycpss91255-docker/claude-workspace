---
name: TDD 開發流程（4 類測試 + 嚴格 red→green→refactor commit 順序）
description: 程式碼變更必須先寫 fail 測試（紅）→ 寫最少 impl 過測試（綠）→ 重構，每階段獨立 commit；同時涵蓋 4 類測試（smoke / unit / integration / lint）中受影響的類別
type: feedback
originSessionId: a985009b-eda1-48eb-8e72-b80fcd000ebb
---
TDD 規則有兩個維度，兩個都要嚴格遵守：

## 維度 1：commit 順序（red → green → refactor）

每次 fix / feat / refactor **必須**分成獨立 commit：

1. `test: <describe failing scenario>` — 先寫一個 fail 測試，commit 起來證明它真的 red
2. `fix:` / `feat:` `<describe minimal impl>` — 寫最少 impl 讓 test 過（green）
3. `refactor:` `<describe>` — 結構優化（optional）

**禁止**：impl + test 同一個 commit，或 impl 先寫好才補 test。

## 維度 2：4 類測試（smoke / unit / integration / lint）

每個變更先決定「動到的東西落在 1～4 哪幾類」，每個受影響類別都要對應補測試：

1. **Smoke test** — 最基本 path 驗證（`test/smoke/*.bats`、Dockerfile `test` stage）
2. **Unit test** — 隔離單一 shell 函式 / 模組邏輯（`template/test/unit/`，bats-mock）；純 Dockerfile 通常 N/A
3. **System / Integration test** — 多元件協同（`template/test/integration/`，如 `init.sh` 完整流程）
4. **Lint / static analysis** — ShellCheck、Hadolint；CI 強制，新檔 / 新規則要先讓 linter 失敗才修

**Why:**
- 維度 1：使用者 2026-04-28 明確指出最近 3 個 PR（#165 / #164 / #168）都違反 — impl + test 寫同一 commit、或 impl 先寫好才補 test。CI 之所以還能 catch 問題，是因為**既存** integration tests（如 upgrade_spec.bats 用到的 `git subtree`）剛好覆蓋到 — 這跟「為這次 fix 主動寫 fail test」不一樣。
- 維度 2：過去使用者發現我直接改 compose.yaml / run.sh 沒先寫測試（違反 TDD）。後續又確認單講 "unit test" 不夠，因為 Dockerfile 沒有 unit 可寫，改用 4 類分類涵蓋所有變更面向。

**How to apply:**
- bug fix / 新功能 / 重構：先 commit 一個只含 fail 測試的 commit，跑 `make -f Makefile.ci test` 確認真的 red，再進 green commit
- 完整對應表見 `workspace/docker/CLAUDE.md` 的「測試分類（TDD 必須涵蓋的 4 個面向）」section（含「變更類型 → 應該寫哪幾類測試」表格）
- Lint 雖非「跑得起來」型測試，但仍視為必跑類別；不靠人工檢查
- 驗證一律透過 `./build.sh test` / `make -f Makefile.ci test` 在 Docker 內跑，不接受本機通過
