# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 專案概述

此倉庫是一個 Docker 容器管理與配置的集合，包含多種專用開發環境的模板，涵蓋 ROS 機器人開發、AI 工具整合，以及應用程式部署。所有 repo 屬於 `ycpss91255-docker` GitHub 組織。

## 檔案命名慣例

- 繁體中文 README：**`README.zh-TW.md`**（連字號，非底線）
- 英文 README：`README.md`
- 環境範本：`.env.example`（只含 `IMAGE_NAME=<name>`）
- Docker Compose：`compose.yaml`（非 `docker-compose.yaml`）

## 風格規範

- **不使用 emoji**：所有程式碼、文件、README、section headers 一律不使用 emoji
- **不加 AI 歸屬標記**：PR body、commit message、code comment 一律不要加
  `Generated with Claude Code`、`Co-Authored-By: Claude ...` 之類的歸屬行。
  這些訊息對 reviewer 無用、只是視覺噪音。
- **不使用覆蓋率忽略註解**：禁止使用 `# LCOV_EXCL_LINE`、`# LCOV_EXCL_START/STOP` 等註解隱藏未覆蓋程式碼。要呈現真實覆蓋率，未覆蓋的部分用測試補上,不要靠註解掩蓋
- **Google Style**：所有新程式碼一律遵循 Google Style Guide（Shell: Google Shell Style Guide；Python: Google Python Style Guide；其他語言依此類推）

## Sandbox baseline（settings.json）

`.claude/settings.json` 的 sandbox section 是這個 repo 簡化 allow
list 的關鍵組合，新進來的人請理解這 4 個 key 做什麼：

```json
"sandbox": {
  "enabled": true,
  "autoAllowBashIfSandboxed": true,
  "excludedCommands": [
    "docker *", "make *",
    "./build.sh *", "./run.sh *", "./exec.sh *", "./stop.sh *",
    ".claude/scripts/*"
  ],
  "filesystem": { "allowWrite": ["/tmp"] }
}
```

| Key | 行為 |
|---|---|
| `enabled: true` | 對 Claude 跑的 Bash 加 sandbox（read-only fs + 限制 write/network），失敗會在錯誤訊息出現 "Operation not permitted" |
| `autoAllowBashIfSandboxed: true` | 若 Bash 命令在 sandbox 內跑得起來（沒撞 read-only / network 限制），**直接 allow 不問 user**，等於把所有 read-only Bash（`grep`、`awk`、`cat`、`ls`、`find` 等）自動放行 |
| `excludedCommands: ["docker *", ...]` | 列在這的 command **完全跳過 sandbox**（OS-level 不套 seatbelt/bubblewrap）。Anthropic 官方 [sandboxing 文件](https://code.claude.com/docs/en/sandboxing) 明確建議 docker 一定要列進來,因為 sandbox 會擋 `connect(AF_UNIX, /var/run/docker.sock)` syscall(refs issue #39)。`make *` 與 4 支 wrapper 一起列,因為它們內部也會 spawn docker。`.claude/scripts/*` 列進來解決 bwrap 對 `app/<repo>/.claude` symlink 的 overlay 衝突(下游 repo 的 `.claude` 是 symlink 到 workspace root,bwrap setup 撞到 `Can't create file at .../.claude: Is a directory` — refs #77 sub-3),信任邊界 == repo-owned scripts 已經過 PR review。pattern 是 prefix wildcard 同 `permissions.allow` |
| `filesystem.allowWrite: ["/tmp"]` | sandbox 預設禁寫入；這條讓 `/tmp` 可寫，配合「把長 body 寫成 `/tmp/<name>.md` 再給 `gh --body-file`」的 cheatsheet pattern |

**實際影響**：
- `permissions.allow` 不需要寫 `Bash(grep:*)` / `Bash(awk:*)` / `Bash(cat:*)` 等 read-only command — sandbox autoAllow 已 cover
- 只需要寫 **state-changing** commands：`Bash(git:*)`、`Bash(gh:*)`、`Bash(docker:*)`、`Bash(make:*)` 等（這些 sandbox 不 autoAllow，因為會改 state / network）
- `permissions.ask` 用來把高風險的 state-change（`Bash(rm:*)`、`Bash(git reset --hard:*)`、`Bash(docker push:*)` 等）**從 allow 拉出來**強制問 user，即使父規則 allow 也會被 ask 蓋過
- `excludedCommands` 的 docker / make / wrapper 不再需要 `dangerouslyDisableSandbox: true` per call — 解掉「驗證一律走 Docker」與 sandbox 的衝突(refs #39)

**什麼時候 sandbox 不夠**：parser fallback 不是 sandbox 問題（見下節「Bash 命令寫法的 parser 限制」），即使 sandbox autoAllow 也救不了 — 因為 fallback 發生在 sandbox 評估**之前**。

新 repo / 新 fork 想 port 這套 setup 時，先把 sandbox 那 4 個 key 貼進去（特別是 `excludedCommands` 一定要含 `docker *`,否則撞 #39 的 docker socket 問題）,再從這個 repo 的 `permissions.allow` 揀必要的 state-changing entries 過去就好；不要把 read-only entries 整批複製。

## Bash 命令寫法的 parser 限制

Claude Code 的 bash AST parser 對某些 shell 構造會 fallback 到 prompt（即使
allowlist 涵蓋、`autoAllowBashIfSandboxed` 開啟也無效）。**主動避開以下
pattern**，改用替代寫法可以根除大量無謂的 user prompt：

| 觸發 prompt 的 pattern | parser 警告 | 替代寫法 |
|---|---|---|
| `cat <<EOF > /path` 寫檔 | `Unhandled node type: file_redirect` | **用 Write 工具**直接寫檔。非寫不可時用 `bash -c 'cat <<EOF > X ...'` 包起來 |
| `gh ... --body "$(cat path)"` / `--comment "$(cat path)"` / `--body-file - <<'EOF'`（heredoc 串 stdin） | `Unhandled node type: string` 或 `Contains zsh =cmd equals expansion` | **先 Write 落地成 `/tmp/<name>.md`，再 `gh ... --body-file /tmp/<name>.md`**（gh CLI 原生支援，所有 subcommand 都有；長 body 永遠寫成檔案，不要 inline、也不要串 stdin）。**`enforce_gh_body_file.sh` PreToolUse hook 會 BLOCK** 這兩個 pattern + 5 個額外 routing 違規(`gh issue/pr create` 必須 `--body-file`、`gh issue close --comment` 必須 two-step、`gh pr edit --body` inline、`gh issue|pr comment|pr review --body` inline > 80 字)。配對的 [[gh-artifact-format]] skill 講格式內容(title shape / body 5 sections / close 3 tiers / cross-ref keywords);refs #64 |
| `for x in $X; do ${x%:*}; done` 多 PR/repo for-loop | `Contains simple_expansion` | **抽永久 `.claude/scripts/<name>.sh`**，主程序只呼叫一行 |
| Monitor 內嵌 20+ 行 bash with `${var%:*}` 或 `<<<"$s"` | `Contains simple_expansion` / `Unhandled node type: string` | 同上，body 抽 script。PR CI 輪詢用 `.claude/scripts/wait-pr-ci.sh`；tag/branch CI 輪詢用 `.claude/scripts/wait-tag-ci.sh`（見 `.claude/skills/wait-pr-ci/SKILL.md`） |
| `cd path && git ...` | 內建 cd+git 安全警告（與上述 parser 無關） | **用 `git -C path <subcmd>`** 取代 |
| `(cd <repo>/worktree path && ./build.sh test)` 或 `bash -c "cd <dir> && ./build.sh ..."` | parser 只看 top-level token,subshell 是 `(`、`bash -c` 是 `bash`、都不命中 `excludedCommands: "./build.sh *"`,sandbox 套上去後 docker.sock 連不上 → `permission denied while trying to connect to the docker API at unix:///var/run/docker.sock` | **用 `./build.sh -C <dir> ...`**（同樣支援 `run.sh` / `exec.sh` / `stop.sh`,從 template v0.22.0 起,refs #53）。長形式 `--chdir`,行為對齊 `git -C` / `make -C`。Top-level token 留在 `./build.sh ...`,sandbox bypass 正常運作 |
| `gh pr merge N --repo X` 從非該 repo cwd | 內建 state-changing safety 提示（不可 bypass，與 parser、allowlist 都無關） | **接受 1-click 提示即可** — 這是合理的安全檢查，且 `docker` monorepo 裡沒有 `ycpss91255-docker/base` 的獨立 checkout（只是 git subtree），無法 cd 進去規避；`-R X` 短形式 / `(cd path && ...)` 子 shell 都不能繞 |
| `[[ a != b ]]` 在 Monitor 內 | Monitor eval wrapper escape `!` 成 `\!` | **用 `case` pattern**（見 `.claude/skills/wait-pr-ci/SKILL.md`） |
| `until ... $(cat <pidfile>) ...; do sleep N; done` 等 background task | `Contains command_substitution` | **用 `Bash` 的 `run_in_background`** — runtime 完成時自動通知，不用 poll。等 GitHub CI 用 `wait-pr-ci.sh` / `wait-tag-ci.sh`；等 local 長 process 用 `run_in_background` 起 task 然後做別的事 |
| `docker run ... bash -c '<長 inline 字串>'` 或 `docker compose ... bash -c '...'`（多行 shell logic 包在引號裡） | `Unhandled node type: string` | **抽成 script** — 用 Write 寫成 `/tmp/<name>.sh`，再 `docker run -v "$PWD":/source ... bash /source/<rel-path>/<name>.sh`；或抽 permanent `.claude/scripts/<name>.sh` 接 atomic flags（如 `run-bats-in-compose.sh --suite all --grep '^not ok'`），Claude parser 只看到 atomic args 不 hit string node。長 quoted body 永遠抽成檔案，不要 inline |

對應的 hook 補強：
- `.claude/hooks/remind_no_heredoc_redirect.sh` — heredoc-to-file 寫法(non-blocking remind)
- `.claude/hooks/enforce_gh_body_file.sh` — `gh` body-file 規律 BLOCKING (rules 1-8 in `.claude/skills/gh-artifact-format/SKILL.md`,refs #64)

其他 pattern（複雜 for-loop / Monitor body）沒有簡單 heuristic，靠這個
section 的規則 + 「## 主動優化建議 → 任務結束時主動列 skill 化候選」收斂。

## 跨 repo 批次 mutation 規範

對 ≥2 個 repo 做有狀態變更（commit、push、`git reset --hard`、
`git branch -D`、close issue / PR、merge 等），**必須走 documented
slash command 或 `.claude/scripts/` 下的 permanent script**，**不准
寫 ad-hoc for-loop 直接執行**。

| 反 pattern | 為什麼不行 | 改用 |
|---|---|---|
| `for repo in $REPOS; do cd ...; git reset --hard FETCH_HEAD; done` | for-loop 跑 15 次 → user prompt 跳 15 次 → yes-fatigue 一路按過去 → 等於繞過 ask rule | `/batch-template-upgrade` 或抽 script，**單一 prompt 涵蓋整個批次** |
| `cat <<EOF > /tmp/x.sh && chmod +x && /tmp/x.sh` 裡面跑 mass git mutation | 雙重問題：heredoc 觸發 parser warning + ad-hoc /tmp script 執行繞過所有 ask 規則（`/tmp/*.sh` 不在任何規則內） | 用 Write 寫 `.claude/scripts/<name>.sh`（permanent），加進 settings allow，再 PR 一次 review 整個 workflow |
| `for r in $REPOS; gh issue close N -R ...` | 同上 fatigue 問題；close issue 是 visible-to-others 操作 | 寫 batch script，或加進 `/batch-pr` 之類的 command |

read-only 跨 repo 操作（純 `gh pr view --json state` / `grep` 多檔）
不在這條規則內 — 沒有破壞性風險，可以用 for-loop（但仍受 parser
warning 影響，視頻率決定要不要 skill 化）。

## 變更完成 checklist（commit 前必做，無例外）

任何程式碼／腳本／Dockerfile／workflow 的變更完成後，**在 commit 之前**
必須依序跑完以下步驟。這不是 nice-to-have — 跳過任何一步都視為變更未完成：

1. **Doc 對齊**：同步更新 README / CHANGELOG / TEST.md（以及 4 語言 README
   若目錄結構有動）。對齊規則詳見下方「變更時必須同步更新的檢查清單」與
   「文件對齊原則」。重點：
   - 新增 / 刪除 / 改名 test → `doc/test/TEST.md` 總數 + 對應表格同步
   - 使用者可見的行為變更 → `doc/changelog/CHANGELOG.md` `[Unreleased]` 加條目
   - 目錄結構 / 檔名 / 符號連結改動 → 4 語言 README 目錄樹同步
   - **dependabot / 機器人 PR 也適用**：bot 不會自己改 CHANGELOG。merge
     前在 PR 留 review comment 補一行 `[Unreleased]`，或 merge 後立即開
     一個 `docs:` follow-up commit；批次 dep bumps 可以合併成同一條
     （例：「GitHub Actions runtime bumped to Node 24 (#A / #B / #C)」）。
     不要累積到下一次 release 才補
2. **Google Style code review**：對本次變更檔案做一次 self-review，列出
   不符合 Google Style Guide 之處並修正。Shell 檔尤其檢查：
   - `local` 宣告、變數命名（`lower_snake_case`；全域用 `UPPER_SNAKE_CASE`
     + `readonly`）
   - `[[ ]]` 而非 `[ ]`；`$(...)` 而非 backticks
   - 雙引號包住所有變數展開
   - 2 空格縮排、`function` 關鍵字不用（直接 `name() {`）
   - `main()` 包所有 top-level 執行邏輯
3. **Docker 驗證**：跑一次 `make -f Makefile.ci test`（base）或
   `./build.sh test`（下游 repo），確認 255+ tests 與 ShellCheck / Hadolint
   全綠。不接受「本機跑 bats 通過」作為驗證。

三項全數通過才能進入 commit / PR 流程。任一項失敗就回頭修，不要 defer。

**Canonical entry**：上面三步在 docker_harness 內可直接用 `/verify`
（`.claude/commands/verify.md` + `.claude/scripts/verify.sh`）一次跑完
— phases = shellcheck / hadolint / bats / tree-audit / TEST.md drift /
doc-scan / diff-stats。hard phase（shellcheck / hadolint / bats）失敗
即 exit 1 並 short-circuit 後面的 phase（`--continue-on-fail` 可關），
soft phase 失敗會在 summary 標 fail 但不中斷 — 最後印一張 markdown 表。
`/verify --dry-run` 看 phase 計畫；`/verify --phase <name>` 跑單一
phase；`/verify --base <ref>` 換 diff-stats / doc-scan 的對比基準（預設
`origin/main`）。其他 repo 沒這個 wrapper 仍走 `make` / `./build.sh test`。

## 測試分類（TDD 必須涵蓋的 4 個面向）

所有變更採嚴格 TDD：先寫失敗測試 → 寫最少程式碼讓測試通過 → 重構。任何變更先思考「這次動到的東西，落在 1～4 哪幾類？」每個受影響的類別都要有對應測試覆蓋。

| # | 類型 | 用途 | 本專案位置 / 工具 |
|---|------|------|------------------|
| 1 | Smoke test | 確認最基本 path 可運作（腳本能啟動、`-h` 可印出、容器能起來） | `test/smoke/*.bats`、`.base/test/smoke/`（共用：`script_help.bats` / `display_env.bats` / `test_helper.bash`），透過 Dockerfile `test` stage 在 build 時跑 |
| 2 | Unit test | 隔離單一 shell 函式 / 模組邏輯 | `.base/test/unit/`（如 `setup_spec.bats`），`bats-mock` 隔離外部呼叫；下游 container repo 通常無自己的 unit，重用 base 的 |
| 3 | System / Integration test | 驗證多元件協同行為（完整流程、跨腳本互動） | `.base/test/integration/`（如 `upgrade_spec.bats`、`init.sh` 流程驗證） |
| 4 | Lint / static analysis | 編譯期 / commit 期靜態檢查 | ShellCheck（所有 `.sh`）、Hadolint（Dockerfile）、`.hadolint.yaml` 規則；CI 強制，本地透過 `./build.sh test` 或 `make -f Makefile.ci lint` 觸發 |

### 變更類型 → 應該寫哪幾類測試

| 變更內容 | Smoke | Unit | Integration | Lint |
|----------|:-----:|:----:|:-----------:|:----:|
| 改 shell 函式邏輯（setup.sh、build.sh 等） | 視 path 影響 | **必須** | 視流程影響 | **必須** |
| 改 Dockerfile（新增 stage、調整 COPY） | **必須** | N/A | 視 build flow | **必須**（Hadolint） |
| 改 entrypoint.sh / 容器啟動行為 | **必須** | 視函式拆分 | 視 multi-container | **必須** |
| 改 multi-container compose 行為 | 視單容器影響 | N/A | **必須** | **必須**（compose lint 若有） |
| 改 CI workflow / reusable workflow | 視觸發點 | N/A | **必須**（PR 跑一次驗證） | **必須**（actionlint 若有） |
| 純 lint 規則調整（`.hadolint.yaml` 等） | N/A | N/A | N/A | **必須**（跑全套確認無新 violation） |
| 文件 / 翻譯 | N/A | N/A | N/A | N/A（只看 doc-sync） |

### 規則

- **Lint 也算測試**：雖然不是「跑得起來」型，但同樣在 CI 強制；新檔 / 新規則要先讓 linter 失敗才修，不靠人工檢查
- **Unit 對 Dockerfile 通常 N/A**：純宣告式內容無邏輯可隔離；改 Dockerfile 改用 smoke + lint 覆蓋
- **TEST.md 是 single source of truth**：4 類測試的數量與位置都記在 `doc/test/TEST.md`，每次新增 / 刪除 / 改名測試必須同步（hook `check_test_md_drift.sh` 會自動比對）
- **驗證一律走 Docker**：4 類都透過 `./build.sh test` 或 `make -f Makefile.ci test` 在 Docker image 內執行，不接受本機 bats / shellcheck 通過作為驗證

## 目錄結構

```
docker/
├── agent/                    # AI Agent 容器（4 個 archive 待辦,refs batch-open-archive-rename-issues.sh）
│   ├── ai_agent/             # All-in-one（Claude + Gemini + Codex）— archive 待辦
│   ├── claude_code/          # Claude Code 獨立版 — archive 待辦
│   ├── gemini_cli/           # Gemini CLI 獨立版 — archive 待辦
│   └── codex_cli/            # Codex CLI 獨立版 — archive 待辦
├── env/                      # ROS 開發環境容器（active 升級流程的全部 2 個 repo）
│   ├── ros_distro/           # ROS 1 multi-distro (noetic / kinetic × ros: / osrf/ros: × variants)
│   └── ros2_distro/          # ROS 2 multi-distro (humble / jazzy × ros: / osrf/ros: × variants)
├── app/                      # 應用程式容器（3 個 archive 待辦 + 4 個 rename + .base 遷移待辦）
│   ├── ros1_bridge/          # archive 待辦（被 env/ros_distro + env/ros2_distro 覆蓋）
│   ├── urg_node_humble/      # rename -> urg_node_ros2 + template/->.base/ 待辦
│   ├── urg_node_noetic/      # rename -> urg_node_ros  + template/->.base/ 待辦
│   ├── realsense_humble/     # rename -> realsense_ros2 + template/->.base/ 待辦
│   ├── realsense_noetic/     # rename -> realsense_ros  + template/->.base/ 待辦
│   ├── sick_humble/          # archive 待辦（被 env/ros2_distro 覆蓋）
│   └── sick_noetic/          # archive 待辦（被 env/ros_distro 覆蓋）
├── archive/                  # 已 archive（read-only）下游 repo 的本地 checkout，留作參考
│   ├── ros_noetic/           # superseded by env/ros_distro (noetic-ros-base entry)
│   ├── ros_kinetic/          # superseded by env/ros_distro (kinetic-ros-base entry)
│   ├── ros2_humble/          # superseded by env/ros2_distro (humble-ros-base entry)
│   ├── osrf_ros_noetic/      # superseded by env/ros_distro (noetic-desktop-full entry)
│   ├── osrf_ros_kinetic/     # superseded by env/ros_distro (kinetic-desktop-full entry)
│   └── osrf_ros2_humble/     # superseded by env/ros2_distro (humble-desktop-full entry)
├── template/                 # 本地 checkout of ycpss91255-docker/base（資料夾名沿用 GitHub rename 前的舊名 `template`；可選擇性重命名為 `base`）
├── multi_run/                # 多容器啟動工具（獨立 repo）
├── org-profile/              # 本地 checkout of ycpss91255-docker/.github (org 首頁)
├── .github/workflows/        # docker_harness 自身 CI（test.yaml）
└── .claude/                  # Claude Code 設定
    ├── commands/             # 自訂 slash commands
    │   ├── audit.md                   # /audit — 跨 repo 健康檢查
    │   ├── batch-pr.md                # /batch-pr — 批次跨 repo PR（通用）
    │   ├── batch-template-upgrade.md  # /batch-template-upgrade — 批次升級下游 template tag（active list 目前 = env/ros_distro + env/ros2_distro,其餘 11 個 repo 在 DEFAULT_REPOS 內 comment-out 待 follow-up）
    │   ├── doc-sync.md                # /doc-sync — 變更完成 checklist 對齊檢查
    │   ├── issue-check.md             # /issue-check — 掃 ycpss91255-docker org 未處理的 open issue
    │   ├── issue-fix.md               # /issue-fix <repo> [<issue_num>|all] [--dry-run] [--limit N] — auto-fix 一個或全部 open issue（合理才修，不合理留 comment）
    │   ├── new-repo.md                # /new-repo — 建立新 Docker repo
    │   ├── pr.md                      # /pr — Bug fix / 新功能 PR 流程
    │   ├── release.md                 # /release — Tag 與 release 流程
    │   ├── safe-delete.md             # /safe-delete — 用 trash 取代 rm
    │   ├── adr.md                     # /adr <slug> — 建立新 ADR (Architecture Decision Record),配 new-adr.sh + remind_adr_on_design_decision.sh Stop hook,refs #97
    │   └── verify.md                  # /verify — 變更完成 checklist 一次跑完 (shellcheck/hadolint/bats/tree/test-md/doc-scan/diff-stats)
    ├── scripts/             # 永久 helper script（被 commands / skills 呼叫）
    │   ├── batch-template-upgrade.sh        # /batch-template-upgrade 的實作
    │   ├── batch-rename-template-to-base.sh # 一次性 #263 Phase 6 fanout：13 下游 git rm template/ + git subtree add --prefix=.base ycpss91255-docker/base.git vX.Y.Z + Dockerfile/main.yaml/README sed
    │   ├── batch-sensor-app-v0.27.sh        # 一次性 #263 sensor-app 5 repo fanout（realsense_humble/noetic、sick_humble/noetic、urg_node_noetic）：rename + Dockerfile 對齊 v0.27 layered config + SETUP_DIR (#254/#261)
    │   ├── batch-template-pr-body.template.md  # 對應 PR body 模板（envsubst 格式）
    │   ├── batch-gitignore-fix.sh           # 一次性 .gitignore `.claude/` -> `.claude` 17 repo fanout（PR #21）
    │   ├── batch-gitignore-add-line.sh      # 通用 .gitignore 追加任意行的 17 repo fanout（PR #23）
    │   ├── batch-pr-merge.sh                # 批次 squash-merge 多個 <repo>:<pr>（接 short / full repo 名都可）
    │   ├── batch-pr-close.sh                # 批次 close 多個 <repo>:<pr>，--reason 必填（superseded-by 場景，例如 hotfix 後重 fanout 取代既有批次 PR）
    │   ├── check-template-versions.sh       # HTTPS curl 13 repo `.base/.version` 對齊檢查（release 後驗證）
    │   ├── fix-compose-copy-line.sh         # 一次性 compose.yaml COPY 路徑修正
    │   ├── fix-dockerfile-lint-lib.sh        # 通用：對 --branch 指定的 chore 分支批次 patch downstream Dockerfile 加 `COPY .base/script/docker/lib /lint/lib`（#284 sub-libs split 後 fanout 必須跑，idempotent）
    │   ├── fix-dockerfile-copy-script.sh     # 通用：對 --branch 指定的 chore 分支批次 patch downstream Dockerfile 把 `COPY *.sh /lint/` 改成 `COPY script/*.sh /lint/`（base#330 / v0.31.0 wrapper consolidation 後 root 沒有 *.sh,active 2 個下游 fanout 必須跑,idempotent）
    │   ├── check-claude-md-tree.sh          # CI lint：parse 此檔 .claude/ tree vs filesystem，drift 就 exit 1
    │   ├── rebase-pr.sh                      # one-shot rebase + force-push for a PR whose base moved (BEHIND/CONFLICTING);auto-resolve worktree by branch via $WORKSPACE_DIR scan,refs #87
    │   ├── wait-pr-ci.sh                    # wait-pr-ci skill 的 PR-scoped polling loop（避開 Monitor parser warning）
    │   ├── wait-pr-ci-batch.sh              # 多 repo 多 PR 同一個 Monitor 的 batch 版本（取代 N 個平行 Monitor stream）
    │   ├── wait-tag-ci.sh                   # 同 skill 的 tag/branch-scoped 版本（gh run list --branch <tag>）
    │   ├── wait-issue-close.sh              # wait-gh-state 的 issue-close 版本（gh issue view --json state）;refs #115
    │   ├── wait-release.sh                  # wait-gh-state 的 release-tag 版本（gh release list --json tagName + stable/rc 分類）;refs #115
    │   ├── migrate-local-to-setupconf.sh    # 一次性 setup.conf.local -> setup.conf 17 repo 遷移（template #201 / v0.16.0；下個版本後刪除）
    │   ├── batch-license-apache.sh           # 一次性 Apache 2.0 LICENSE + CI/License badge fresh add 13 repo fanout（org-wide license alignment）
    │   ├── run-bats-in-compose.sh           # docker compose 跑 bats 包裝，避開 docker compose ... bash -c '...' 的 parser fallback
    │   ├── ci-wall-time-compare.sh          # diff CI 兩個 run id 的 per-job wall time + overall,輸出 markdown 表(CI-perf PR 用,refs #77 sub-2)
    │   ├── batch-open-archive-rename-issues.sh # 開 11 張下游 follow-up issue：7 archive(4 agent + ros1_bridge / sick_humble / sick_noetic) + 4 rename + template->.base 遷移(urg_node_*, realsense_*),idempotent 跳過 title 相同既有 issue
    │   ├── setup-memory-link.sh             # 新 clone / 換機器:建 symlink ~/.claude/projects/<encoded>/memory -> <workspace>/.claude/memory,讓 per-project memory portable + git-tracked。idempotent
    │   ├── verify.sh                         # /verify 的實作:依序跑 shellcheck/hadolint/bats/tree-audit/TEST.md drift/doc-scan/diff-stats,hard-fail 阻擋,輸出 markdown summary
    │   ├── instinct-query.sh                 # 查詢 .claude/instincts.yaml — `instinct-query.sh <kind> [path]` 印出符合 trigger 的 instincts (5 kinds: file_edit / git_commit / gh_pr_create / gh_issue_create / bash_command)，hooks/skills 用來取代 grep CLAUDE.md prose;refs #95
    │   ├── release-tag.sh                    # canonical primitive for cutting version tags;decision tree (RC / Z / Y / X bump) + .version integrity + RC CI 查詢 + RELEASE_X_BUMP_ACK 檢查;搭配 enforce_semver_tag_via_script.sh 強制 routing,refs #106
    │   ├── new-adr.sh                         # /adr 的實作:auto-number 8 位數補零,從 doc/adr/[0-9]*.md 掃 max+1,渲染 5-section 模板 (Date/Status/Context/Decision/Alternatives/Consequences),refs #97
    │   ├── _instinct_parser.py               # instinct-query.sh 用的 stdlib-only YAML parser helper (避免 PyYAML dep 在 Alpine test image 缺失)
    │   └── lib/
    │       └── checkpoint.sh                  # /tmp checkpoint protocol helper — write_checkpoint + is_acked,Tier 2 E2 hook 共享 deny/ack 契約,refs ADR-00000002 / #117
    ├── memory/               # Claude Code per-project memory（auto-loaded via symlink）
    │   ├── MEMORY.md         # 入口索引(被 Claude Code 自動讀進 system prompt 開頭)
    │   ├── feedback_*.md     # 個別 feedback / workflow rule（每檔有 name + description + type frontmatter）
    │   └── project_*.md      # 專案性 context（如 ros1_bridge_jetson）
    ├── hooks/                # PostToolUse / PreToolUse hooks
    │   ├── check_no_emoji.sh           # Edit/Write 後掃 emoji
    │   ├── check_no_coverage_excl.sh   # Edit/Write 後掃 LCOV_EXCL_* 等覆蓋率忽略註解
    │   ├── check_no_ai_attribution.sh  # Edit/Write 後掃 Co-Authored-By/Generated with Claude
    │   ├── check_changelog_drift.sh    # git commit 前比對 staged code vs CHANGELOG.md
    │   ├── remind_readme_on_core_script.sh # git commit 前提醒 base 核心 .sh 改動是否同步 README
    │   ├── check_test_md_drift.sh      # *.bats / TEST.md 後比對測試數
    │   ├── remind_tdd_categories.sh    # 動到 .sh/Dockerfile/compose 等時提醒 4 類測試
    │   ├── remind_pr_wait_ci.sh        # gh pr create 前提醒用 /wait-pr-ci skill
    │   ├── remind_no_ai_attribution.sh # git commit / gh pr create 前掃 inline 歸屬字串
    │   ├── remind_subtree_init.sh      # git subtree pull .base 前提醒跑 init.sh
    │   ├── remind_docker_for_lint.sh   # bats/shellcheck/hadolint/kcov 前提醒走 Docker (wrapper list 可被 .claude/lint_wrappers.txt override)
    │   ├── remind_no_heredoc_redirect.sh # cat <<EOF > file 時提醒用 Write 工具
    │   ├── remind_no_chinese_in_git_artifacts.sh # git commit / gh PR / issue title|body|comment 前 BLOCK CJK 與全形字符
    │   ├── enforce_gh_body_file.sh     # gh issue/pr create/edit/comment/close/review 前 BLOCK 違反 body-file 規律的 8 種 pattern(配合 [[gh-artifact-format]] skill,refs #64)
    │   ├── remind_test_tools_smoke_sync.sh # Dockerfile.test-tools 改動但同層 release-test-tools.yaml 未同步時提醒
    │   ├── auto_allow_rm_in_workspace.sh # rm <workspace+/tmp 內 path> 自動 allow（避開 Bash(rm:*) ask yes-fatigue）
    │   ├── auto_allow_touch_ack.sh       # touch $TMPDIR/claude-checkpoint-*.ack 自動 allow（/tmp checkpoint 協定一鍵 ack,refs ADR-00000002 / #117）
    │   ├── check_tag_version_consistency.sh # git tag/push v* 前 BLOCK：repo root 有 .version 且不等於 tag 則 deny（refs #36；defensive 第二層,主要 gate 由 enforce_semver_tag_via_script.sh 接手）
    │   ├── enforce_semver_tag_via_script.sh # git tag/push v* 前 BLOCK：raw 命令一律拒絕,強制走 .claude/scripts/release-tag.sh canonical script(refs #106)
    │   ├── enforce_make_first_upgrade.sh # 三個 surface (./.base/upgrade.sh / ./template/upgrade.sh / git subtree pull --prefix=.base|template) 前 BLOCK,改走 make -f Makefile.ci upgrade(checkpoint ack 可解,refs #36 / ADR-00000002)
    │   ├── enforce_batch_via_script.sh   # 跨 repo for-loop + mutation (git push|reset|tag|branch -D / gh issue|pr close|merge|comment --body) 前 BLOCK,改走 .claude/scripts/<name>.sh(checkpoint ack 可解,refs #121 / ADR-00000002)
    │   ├── enforce_worktree_for_branch.sh # 主 checkout 內 git checkout -b|-B 前 BLOCK,要求改走 git worktree add <path> -b <branch> main(內部 worktree 自動放行,checkpoint ack 可解,refs #122 / PR #89 / ADR-00000006)
    │   ├── check_prefer_dot_sh.sh       # docker build/run/exec/stop/compose 前：cwd 有對應 .sh wrapper 則 deny,沒有則 ask
    │   ├── remind_topics_yaml_on_new_repo.sh # gh repo create ycpss91255-docker/* 前提醒去 .github topics.yaml 加 repos.* 條目
    │   ├── check_readme_framework.sh    # Edit/Write 後掃下游 repo README.md (+ 3 翻譯) 是否符合 .base/README.md 框架(badge / 4 語言 link / TL;DR H2 / Smoke Tests link / 無 stale 路徑) — non-blocking warning
    │   ├── check_no_stale_template_refs.sh # Edit/Write 後掃 .base/ 下 .sh/Makefile/Dockerfile 是否殘留 template/<path> 引用(rename 後遺漏,refs base#282)
    │   ├── remind_main_sync.sh         # gh pr merge 前提醒 merge 後跑 git pull --ff-only origin main 保持本地 main 持續 ff-tracking origin/main HEAD
    │   ├── check_main_fresh_before_worktree.sh # git worktree add ... main 前 BLOCK：若 local main 落後 origin/main 就 deny + 提示先 pull,避免從 stale base 起 branch(refs PR #89 precedent)
    │   ├── remind_strategic_compact.sh # Stop hook：讀 transcript 偵測 task-boundary 訊號(gh pr merge / tool count >= 50)後 propose /compact,configurable via STRATEGIC_COMPACT_{DISABLE,TOOL_THRESHOLD};refs #92
    │   ├── remind_adr_on_design_decision.sh # Stop hook：transcript 掃 rationale 關鍵字 (alternative/trade-off/rejected because/...) 達 threshold 且 session 無 doc/adr/ 寫入時提案 /adr,configurable via ADR_REMIND_{DISABLE,THRESHOLD};refs #97
    │   ├── check_no_off_task_suggestions.sh # Stop hook：transcript 掃 last assistant message 的 off-task 片語 (stop for dinner / take a break / need rest / do it tomorrow ...) 命中時 remind,never block,configurable via NO_OFF_TASK_REMIND_DISABLE;refs #109
    │   ├── remind_proactive_optimization.sh # Stop hook：task-boundary 訊號(gh pr merge / tool count >= 50)後若 session 未提任何 optimisation 候選 (workflow ergonomics / cross-repo inconsistency / doc drift / manual repetition) 則 remind 配 [[proactive-optimization]] skill,configurable via PROACTIVE_OPTIMIZATION_REMIND_{DISABLE,THRESHOLD};refs #124
    │   └── test/                       # bats specs (smoke + integration) — 跑法見 Makefile
    ├── skills/
    │   ├── rebase-pr/SKILL.md          # PR 因 BEHIND/CONFLICTING 需 rebase 時的 one-shot 流程,配 rebase-pr.sh + wait-pr-ci FAIL hint,refs #87
    │   ├── wait-pr-ci/SKILL.md         # PR CI 等待用 Monitor 而非 sleep 輪詢
    │   ├── gh-artifact-format/SKILL.md # gh issue/pr artifact 格式規範(issue title/body 5 sections/close 3 tiers/comment 3 categories/cross-ref keywords)配 enforce_gh_body_file.sh hook
    │   ├── semver-bump/SKILL.md        # 版本 tag 流程:X/Y/Z 分類 + RC 程序 + RELEASE_X_BUMP_ACK 使用,配 release-tag.sh + enforce_semver_tag_via_script.sh,refs #106
    │   ├── strategic-compact/SKILL.md  # 何時手動 /compact (task boundary) vs 何時別 compact (mid-implementation),配 remind_strategic_compact.sh hook
    │   ├── wait-gh-state/SKILL.md      # 非 CI 的 GitHub state 監看 (issue close / release stable),sibling to wait-pr-ci;refs #115
    │   └── proactive-optimization/SKILL.md # 任務 boundary 時主動提 optimisation 候選 (workflow ergonomics / cross-repo inconsistency / doc drift / manual repetition),配 remind_proactive_optimization.sh Stop hook;refs #124
    ├── test/                           # docker_harness 自己的 hook 測試 infra（與下游 repo 的 Dockerfile 無關）
    │   ├── Dockerfile                  # bats 1.11 + shellcheck on Alpine（COPY .claude/hooks/ + .claude/scripts/）
    │   └── Makefile                    # make -C .claude/test build / test / lint / hadolint / check
    ├── settings.json                   # hooks 註冊 + permissions + sandbox（**唯一一份,無 settings.local.json**）
    └── instincts.yaml                  # 結構化 repo conventions (#95 pilot) — hooks/skills/commands 用 `instinct-query.sh` 查詢,取代 CLAUDE.md prose grep
```

## 常用指令

### 所有容器通用

```bash
./build.sh                  # 建置（預設 target，自動更新 .env）
./build.sh --no-env test    # 建置但不更新 .env
./build.sh --no-cache       # 強制不使用 cache 重建
./build.sh test             # 建置並執行 smoke test
./run.sh                    # 互動式前台執行（自動更新 .env）
./run.sh --no-env -d        # 後台執行，跳過 .env 更新
./run.sh -d                 # 後台執行（detach mode）
./exec.sh                   # 進入執行中的容器（預設 devel）
./exec.sh <cmd>             # 在預設容器中執行指令
./exec.sh -t <service> <cmd> # 進入指定 service 執行指令
./stop.sh                   # 停止並移除所有容器
./build.sh --lang ja        # 指定訊息語言（en|zh-TW|zh-CN|ja）
SETUP_LANG=zh ./run.sh      # 透過環境變數設定語言
```

### AI Agent 容器額外指令

```bash
./run.sh devel-gpu                # GPU 版本
./run.sh --data-dir ../agent_foo  # 指定資料目錄
```

### base

```bash
make -f Makefile.ci test                      # 執行 Bats 測試 + ShellCheck + Kcov 覆蓋率
make -f Makefile.ci lint                      # 僅 ShellCheck
make -f Makefile.ci upgrade                   # 升級 .base/ subtree 到最新 tag
make -f Makefile.ci upgrade VERSION=vX.Y.Z    # 升級到指定版本
make -f Makefile.ci upgrade-check             # 檢查是否有新版
make -f Makefile.ci help                      # 顯示所有 CI 指令
```

> **升級一律 make 優先**。`./.base/upgrade.sh [vX.Y.Z]` 留作 fallback，
> 只在 make 不可用或 target 出問題時才用。


### 驗證一律走 Docker

**所有 lint 與 test 驗證只能透過 Docker 執行**，不要直接呼叫本機的
`bats`、`shellcheck`、`hadolint`、`kcov` 等工具。理由：
- 本機環境可能缺少 `bats-mock`、特定版本 bats-support / bats-assert，或
  shellcheck 版本與 CI 不同，會得到與 CI 不一致的結果
- CI 的 reusable workflow 也是透過同一組 Docker image 執行，走 Docker
  可以確保本地與 CI 行為一致

入口：
- `./build.sh test` — Dockerfile `test` stage（ShellCheck → Hadolint → Bats smoke）
- `make -f Makefile.ci test` / `lint` — base 自身的 unit/integration 測試

## 標準容器結構

每個容器目錄遵循相同的檔案配置模式：

```
<repo>/
├── Dockerfile                   # 多階段建置
├── compose.yaml                 # Docker Compose 服務定義
├── build.sh -> .base/script/docker/build.sh   # symlink
├── run.sh -> .base/script/docker/run.sh       # symlink
├── exec.sh -> .base/script/docker/exec.sh     # symlink
├── stop.sh -> .base/script/docker/stop.sh     # symlink
├── Makefile -> .base/script/docker/Makefile    # symlink
├── .hadolint.yaml -> .base/.hadolint.yaml      # symlink（或自訂版本）
├── script/
│   └── entrypoint.sh            # 容器進入點
├── doc/
│   ├── README.zh-TW.md          # 繁體中文
│   ├── README.zh-CN.md          # 簡體中文
│   ├── README.ja.md             # 日文
│   ├── test/TEST.md             # 測試文件
│   └── changelog/CHANGELOG.md   # 變更記錄
├── test/
│   └── smoke/
│       └── <name>_env.bats      # Bats 環境測試（repo-specific）
├── .base/                    # git subtree（共用腳本、測試、設定；版本追蹤檔 .base/.version）
├── config/docker/setup.conf     # （選用）repo override；section-replace .base/config/docker/setup.conf（路徑自 #262 / v0.25.0 起）
├── .env.example                 # IMAGE_NAME fallback
├── .gitignore
├── .github/workflows/
│   └── main.yaml                # CI/CD（呼叫 base 的 reusable workflows）
└── README.md                    # 英文（根目錄，GitHub 自動顯示）
```

> **注意**：共用的 smoke tests（script_help.bats、display_env.bats、test_helper.bash）
> 位於 `.base/test/smoke/`，不放在 `test/smoke/`。
> Dockerfile 用兩行 COPY 合併：
> ```dockerfile
> COPY .base/test/smoke/ /smoke_test/
> COPY test/smoke/ /smoke_test/
> ```
> `display_env.bats` 會自動偵測 compose.yaml 是否有 GUI 設定，headless repo 自動 skip。

### .base subtree 結構

```
.base/
├── init.sh                       # 初始化 repo（新建或既有）
├── upgrade.sh                    # 升級 .base/ subtree 版本
├── setup.conf                    # 預設設定（image_name/gpu/gui/network/volumes）
├── script/
│   ├── docker/                   # Docker 操作腳本（各 repo symlink）
│   │   ├── build.sh
│   │   ├── run.sh
│   │   ├── exec.sh
│   │   ├── stop.sh
│   │   ├── setup.sh              # .env + compose.yaml 產生器（讀 setup.conf）
│   │   ├── i18n.sh               # 語言偵測
│   │   └── Makefile
│   └── ci/
│       └── ci.sh                 # CI pipeline（本地 + 遠端）
├── dockerfile/
│   ├── Dockerfile.test-tools     # 預建置測試工具 image
│   └── Dockerfile.example        # 新 repo 的 Dockerfile 範本
├── config/                       # Shell 設定（bashrc、tmux、terminator、pip）
├── test/
│   ├── smoke/                    # 共用 smoke tests
│   ├── unit/                     # template 自身測試（見 doc/test/TEST.md）
│   └── integration/              # init.sh 整合測試（見 doc/test/TEST.md）
├── Makefile.ci                   # template CI 入口
├── compose.yaml                  # Docker CI 執行器
└── .hadolint.yaml                # 共用 Hadolint 規則
```

## 重要設計模式

### setup.conf → .env + compose.yaml 產生機制

`setup.sh` 讀取 `setup.conf`（INI 格式設定）+ 系統偵測 → 產生 `.env` 與
`compose.yaml` 兩份 derived artifacts。來源是 `setup.conf`，不要直接手改
`.env` / `compose.yaml`（下次 build/run 會被覆蓋）。

**每次 `build.sh` / `run.sh` 預設都會重新產生 `.env` + `compose.yaml`**，
使用 `--no-env` 跳過。`setup.sh` 會保留既有 `.env` 中有效的 `WS_PATH`、
`APT_MIRROR_*`。

#### setup.conf 位置與 override 策略

- `.base/config/docker/setup.conf` — 模板預設值（4 個 section；路徑自 #262 / v0.25.0 起）
- `<repo>/config/docker/setup.conf` — 選用 repo override。**Section-replace**：
  repo 檔有的 section 完整取代模板該 section；repo 沒列的 section
  繼續用模板預設

#### setup.conf section 清單

| Section | Key | 意義 |
|---------|-----|------|
| `[image_name]` | `rules` | IMAGE_NAME 偵測規則（有序，逗號分隔）：`@env_example`、`prefix:xxx`、`suffix:xxx`、`@basename`、`@default:xxx` |
| `[gpu]` | `mode` | `auto`（偵測 nvidia-container-toolkit） / `force` / `off` |
| `[gpu]` | `count` | `all` 或整數 |
| `[gpu]` | `capabilities` | 空格分隔：`gpu` / `compute` / `utility` / `graphics` |
| `[gui]` | `mode` | `auto`（偵測 `$DISPLAY`/`$WAYLAND_DISPLAY`） / `force` / `off` |
| `[network]` | `mode` | `host` / `bridge` / `none` |
| `[network]` | `ipc` | `host` / `shareable` / `private` |
| `[network]` | `privileged` | `true` / `false` |
| `[volumes]` | `mount_1..N` | 額外掛載，`<host>:<container>[:ro\|rw]`；含 `/dev/*` 裝置 pass-through。按數字後綴排序 |

#### 系統偵測項目（不吃 setup.conf）

- 使用者資訊：UID/GID/USER/GROUP（`id`）
- 硬體架構：`uname -m`
- Docker Hub 用戶
- WS_PATH 工作區三策略偵測：同層掃描 → 向上遍歷 → 退回上層目錄
- APT_MIRROR_UBUNTU / APT_MIRROR_DEBIAN：預設台灣鏡像，保留既有值

#### 漂移偵測

`setup.sh` 在 `.env` 中寫入 `SETUP_*` metadata（包含 `SETUP_CONF_HASH`，
SHA256 over 模板 + repo setup.conf）。build/run 會比對 hash，若 setup.conf
已變動會自動重跑；使用者手改 .env 不會觸發重跑，但會在下次不帶 `--no-env`
時被蓋掉。

#### compose.yaml 條件化 block

`generate_compose_yaml` 依 `[gpu]`/`[gui]` resolve 結果條件組裝：
- GPU 啟用 → 輸出 `deploy.resources.reservations.devices`（`nvidia` + count + capabilities）
- GUI 啟用 → 輸出 DISPLAY / WAYLAND / XDG_RUNTIME_DIR / XAUTHORITY 的 env + volume
- 基線 volumes 永遠輸出（`${WS_PATH}:/home/${USER_NAME}/work`），`[volumes] mount_*` 加在其後

### CI/CD Pipeline

所有 repo 使用 `template` 提供的 **reusable workflows**，各 repo 只保留 `main.yaml`：

```
main.yaml
├── call-docker-build → .base/.github/workflows/build-worker.yaml@<version>
│   inputs: image_name, build_args, build_runtime
└── call-release → .base/.github/workflows/release-worker.yaml@<version>
    inputs: archive_name_prefix, extra_files
```

- `build.sh` 會先 build `test-tools:local` image（ShellCheck + Hadolint + Bats）
- Dockerfile `test` stage 依序執行：ShellCheck (.sh) → Hadolint (Dockerfile) → Bats smoke test
- `call-release` 需要 build 通過才觸發，僅 `v*` tag 觸發
- `.hadolint.yaml` 忽略不適用於 dev 環境的規則（DL3007/DL3008 等）
- 本地 `./build.sh test` 與 CI 執行完全相同的檢查

### Smoke Tests

所有 repo 的 README Smoke Tests section 簡化為連結到 TEST.md：
```markdown
## Smoke Tests

See [TEST.md](doc/test/TEST.md) for details.
```

### 用戶與權限管理

Dockerfile 接受 `USER_NAME`、`USER_UID`、`USER_GID` 參數，在容器內建立與主機 UID/GID 相符的用戶。sys stage 處理 UID/GID 衝突。

### 多階段建置慣例

- `bats-src` / `bats-extensions` / `lint-tools` stage：測試工具來源（不出貨，可用 `test-tools:local` 替代）
- `sys` stage：用戶/群組建立、sudo 設定、時區語系、APT mirror 設定
- `base` stage：開發工具與語言套件
- `devel` stage：應用專屬工具 + entrypoint + PlotJuggler（env repos）
- `test` stage：ShellCheck → Hadolint → Bats smoke test（短暫性，build 完即丟）
- `runtime` stage：（僅應用程式類型）最小化 runtime
- Shell 設定：`SHELL ["/bin/bash", "-x", "-euo", "pipefail", "-c"]`

### Locale 設定（重要）

Debian bookworm 必須先 uncomment `/etc/locale.gen` 再 `locale-gen`，`LC_ALL`/`LANG` ENV 必須在 `locale-gen` **之後**設定：

```dockerfile
RUN sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && \
    locale-gen && \
    update-locale LANG="en_US.UTF-8"

ENV LC_ALL="en_US.UTF-8"
ENV LANG="en_US.UTF-8"
```

### AI Agent 憑證隔離

只掛載**憑證檔案**，不掛載整個設定目錄：
- Claude：`~/.claude/.credentials.json`
- Gemini：`~/.gemini/oauth_creds.json`
- Codex：無 OAuth 檔案，僅使用 `OPENAI_API_KEY`

### GPU 支援

AI Agent 容器透過 `devel-gpu` service 支援 NVIDIA GPU（CPU 為預設）。`post_setup.sh` 偵測 GPU 後設定 `BASE_IMAGE=nvidia/cuda:13.1.1-cudnn-devel-ubuntu24.04`。ROS 環境容器透過 compose.yaml 的 `deploy.resources.reservations.devices` 設定。

### 時區與語系

所有容器預設使用 `Asia/Taipei` 時區與 `en_US.UTF-8` 語系。

### APT Mirror

`setup.sh` 產生的 `.env` 包含 APT mirror 設定：
- `APT_MIRROR_UBUNTU=tw.archive.ubuntu.com`
- `APT_MIRROR_DEBIAN=mirror.twds.com.tw`

Dockerfile 透過 `ARG` + `sed` 使用，`|| true` 防止檔案不存在時失敗。

### i18n（國際化）

腳本訊息支援 4 種語言：`en`（預設）、`zh`（繁中）、`zh-CN`（簡中）、`ja`（日文）。

| 元件 | i18n 方式 | 切換方法 |
|------|----------|---------|
| `setup.sh`（template） | `_msg()` 函式 | `--lang` flag 或 `SETUP_LANG` 環境變數 |
| `build.sh` / `run.sh` | usage() case 分支 + 轉發 `--lang` 給 setup.sh | `--lang` flag 或 `SETUP_LANG` 環境變數 |
| `exec.sh` / `stop.sh` | usage() case 分支 | `SETUP_LANG` 環境變數 |
| README | 各語言獨立檔案放在 `doc/` | 頂部語言切換連結 |

### Shell 腳本慣例

- 所有 `.sh` 使用 `set -euo pipefail`
- Help 統一使用 `usage()` 函式 + `cat >&2`
- 所有互動腳本（build.sh / run.sh / exec.sh / stop.sh）支援 `-h` / `--help`
- build.sh / run.sh 支援 `--lang` 旗標
- ShellCheck compliant（CI 強制）

## 版本號慣例（refs #106）

語意（2026-05-15 update）：

| 位 | 用途 | RC 要求 | 額外 gate |
|---|---|---|---|
| **X (MAJOR)** | Ceremonial / 主要 release marker — 跟「破壞性變更」**解綁** | 必須 | **User 明確同意**（`RELEASE_X_BUMP_ACK=<tag>` env） |
| **Y (MINOR)** | 功能調整 + 破壞性變更（任何 user-visible 非 bug-fix 變動） | 必須 | 無 |
| **Z (PATCH)** | Bug 修復（純修補 / 文件修正） | 不用 | 無 |
| `MAJOR.MINOR.0-rcN` | Release Candidate（正式發布前驗證） | n/a | 隨時可 cut |

舊規則（X = 破壞性）已淘汰；現在 breaking 跟 non-breaking feature 一起
落 Y，X 純粹由 user 在 chat 明確說「OK cut」才動。

**強制走 `.claude/scripts/release-tag.sh`** — `enforce_semver_tag_via_script.sh`
PreToolUse hook BLOCKs raw `git tag v*` / `git push.*v[0-9]`，迫使 caller
透過 canonical script。Script 內含 decision tree + RC CI 查詢 + ACK 檢查 +
`.version` integrity。配對的 `[[semver-bump]]` skill 詳列 X/Y/Z 程序。

### Release 流程

```bash
# 1. 打 RC tag（GitHub Release 自動標為 prerelease）
.claude/scripts/release-tag.sh v1.3.0-rc1 -m "v1.3.0-rc1: ..."

# 2. 等 CI 全部通過（wait-tag-ci skill）
.claude/scripts/wait-tag-ci.sh --repo ycpss91255-docker/<repo> --branch v1.3.0-rc1

# 3. RC 通過 → 打正式 tag
.claude/scripts/release-tag.sh v1.3.0 -m "v1.3.0: ..."

# 4. RC 失敗 → 修復後打 rc2（never re-tag 同 rcN）
.claude/scripts/release-tag.sh v1.3.0-rc2 -m "v1.3.0-rc2: fix ..."

# 5. X bump (v1.0.0 / v2.0.0) 額外需要 user 在 chat 明確 OK
#    Claude 不能自己加 RELEASE_X_BUMP_ACK，必須等 user 說「ok cut v1.0.0」
RELEASE_X_BUMP_ACK=v1.0.0 .claude/scripts/release-tag.sh v1.0.0 -m "v1.0.0: ..."
```

> `release-worker.yaml` 已設定 `prerelease: ${{ contains(github.ref_name, '-') }}`，tag 含 `-` 會自動標為 prerelease。
>
> Z bump（bug fix）直接 `release-tag.sh v1.3.1 -m "v1.3.1: ..."` 無 RC。
> 詳見 `.claude/skills/semver-bump/SKILL.md`。

## Git 工作流程

### git worktree 用法（強制）

對任一 repo 開新 branch / 做修改時，**必須走 `git worktree add`**，不准
直接在主 checkout 跑 `git checkout -B <branch>` 弄髒 working tree。

| 規則 | 內容 |
|---|---|
| 工作位置 | **`<workspace>/worktree/<repo>-<N>/`**（已 gitignored 在 workspace `.gitignore`）。N 通常用 PR / issue 編號（如 `template-177` `docker_harness-22`），新工作沒編號可用 branch slug |
| 主 checkout 狀態 | 2 個 active 下游 repo（env/× 2）+ template + workspace 主 checkout **永遠停在 origin/main**，不長 branch、不放 WIP。「停在 origin/main」= **持續 ff-tracking origin/main HEAD**,不是凍結在某個 commit — **每次 PR merge 後立即 `git pull --ff-only origin main`**（hook `remind_main_sync.sh` 會在 `gh pr merge` 前提醒；`check_main_fresh_before_worktree.sh` 會在 `git worktree add ... main` 時 BLOCK 若 local 落後 origin/main,避免從 stale base 起 branch 後被迫 rebase — PR #89 踩過正是此 case）。其餘 11 個 repo（agent/× 4、app/× 7）有 open follow-up issue 待 archive 或 rename + `.base` 遷移，不在當前 active 升級流程內；批次 script 以註解保留 entry，待 prerequisite 完成後取消註解。`archive/` 底下 6 個 archived repo 屬只讀備份 |
| 起 branch | `git worktree add <workspace>/worktree/<repo>-<N> -b <branch> main` |
| 收尾 | merge 後 `git worktree remove <path>`，或 `git worktree prune` 清理 stale entry |
| 平行工作 | 同一 repo 可有多個 worktree，每個對應一個 branch / PR — 不會互相打架 |
| 跨 repo 批次 | `batch-template-upgrade.sh` 等批次 script 自帶 `git fetch + checkout -B main FETCH_HEAD + checkout -B <branch>` 流程，已在主 checkout 跑（不適用 worktree 規則的例外）。**逐 repo 單獨改動**才用 worktree |

**fresh machine 沒有 `worktree/` 資料夾的處理**：

如果 `<workspace>/worktree/` 不存在（剛換機器、或全新 clone），**Claude
必須先問 user**「要建在 `<workspace>/worktree/` 還是別的位置？」或
「直接幫你 mkdir 嗎？」，**不准自行猜測位置直接建**。

### 變更分類與流程

| 類型 | 流程 | 範例 |
|------|------|------|
| Bug fix | **PR** — 開 branch → 修復 + 加 regression test → PR merge | setup.sh `_base_path` 解析錯誤 |
| 新功能 | **PR** — 開 branch → 實作 → PR merge → tag release | 新增 `--no-env` flag |
| 重構 | **PR** — 搬檔案、改路徑、改 Dockerfile 結構等 | 搬腳本到 `script/docker/` |
| 文件更新 | **PR** — 開 branch → 修改 → PR merge | README 表格補充、翻譯更新 |
| template 變更 | **PR** → merge → tag → 各 repo `git subtree pull` | 任何共用腳本 / setup.sh / config / CI workflow 修改 |

> **嚴格執行**：**所有變更都必須走 PR**，不可直接 push main。使用 `/pr` slash command 執行 PR 流程。

### Branch Protection（GitHub 強制）

所有 `ycpss91255-docker` 組織下的 repo，main branch 一律啟用 branch protection，**包含 admin**，任何情境都不允許直接 push：

| 設定項 | 值 | 說明 |
|--------|------|------|
| `required_pull_request_reviews` | 啟用，0 approver | 必須透過 PR，但不要求 review approval |
| `required_status_checks` | strict=true | 必須通過 CI 才能 merge |
| `enforce_admins` | **true** | admin 也不能 bypass，一律走 PR |
| `allow_force_pushes` | false | 禁止 force push |
| `allow_deletions` | false | 禁止刪除 protected branch |

Status check 名稱依 repo 類型不同：

| Repo 類型 | Status Check Context |
|-----------|---------------------|
| `template` (base) | `ci-rollup`（self-test.yaml aggregator，post-#337） |
| `multi_run` | `test` |
| `docker_harness`（本 repo） | `bats + shellcheck + hadolint`（單 job test workflow） |
| 單 distro 容器 repo（多數 `agent/*`、`app/*`） | `call-docker-build / docker-build` |
| Multi-distro env repo（`env/ros_distro`、`env/ros2_distro`） | `ci-passed`（matrix aggregator） |
| Multi-distro app repo（`app/ros1_bridge` post-#54） | `ci-summary`（in-repo aggregator） |
| `.github`（組織首頁，post-topics-taxonomy） | `lint`（yaml 結構驗證 + shellcheck） |

新建 repo 時必須同步設定 branch protection，`/new-repo` slash command 應自動處理。

### CI 監控（PR open 後）

開完 PR 後不要用 `sleep` 輪詢、也不要反覆手動跑 `gh pr checks`。改用 **`wait-pr-ci` skill**（`.claude/skills/wait-pr-ci/SKILL.md`）— 內部以 Monitor 工具 + `until` poll loop 30s 間隔，每個 check 從 pending 變化時噴一行通知，全部 settle 後噴 `ALL_DONE`，agent 不會被 sleep 卡住、context 也不會被 polling output 噴爆。

適用情境：
- 剛開完 PR 等 merge
- 同 batch 多個 PR 平行等
- `@dependabot rebase` 後 CI 重跑

不適用 tag-triggered workflow（release-test-tools / release-worker）— 那是 tag-scoped 不是 PR-scoped，套同樣 Monitor pattern 但改查 `gh run list --branch <tag>`。

skill 內含 status check filter 對應表（template / docker_harness / 單 distro 容器 / multi-distro env / multi-distro app / .github），詳見 SKILL.md。`docker_harness` 跟 `.github` 不走 default filter — 前者 check 名稱是 `bats + shellcheck + hadolint`（單 job test workflow），後者是 `lint`（topics-taxonomy lint workflow）；兩個都不在 default 的 `test` / `Integration ...` 裡，跑 `wait-pr-ci.sh` 必須帶 `--check-filter '.name=="bats + shellcheck + hadolint"'` 或 `--check-filter '.name=="lint"'`，否則第一次 poll 噴 `no-checks` 後就一直空轉。Multi-distro repo（`env/ros_distro`、`env/ros2_distro`、`app/ros1_bridge`）的 PR rollup 沒有 `call-docker-build / docker-build`，必須改傳 `--check-filter '.name=="ci-passed"'`（env multi-distro）或 `--check-filter '.name=="ci-summary"'`（`ros1_bridge` post-#54）。`wait-pr-ci-batch.sh` 在混合 repo 類型 batch 時用 `--check-filter <repo>=<expr>` per-repo override（`ros_distro=...` / `ros2_distro=...` 為當前 active；`ros1_bridge=...` 等其餘 repo 在 archive / rename follow-up 期間暫不需要,但 expression 留作 reactivate 後參考）配 global default 即可一次涵蓋當前所有 active 下游。

### Bug fix 必須附帶 regression test

修 bug 時一律加測試防止回歸。

### .base subtree 更新流程

```bash
# 1. 在 base 本體修改 + commit + push + tag (use latest version)
# Note: 本地 checkout 仍叫 `template/` (尚未 rename),只是 GitHub 端 repo 改名為 base
cd template && git push && git tag -a vX.Y.Z -m "vX.Y.Z: ..."
git push origin vX.Y.Z

# 2. 各 repo 跑 make upgrade（內部呼叫 upgrade.sh，自動處理 subtree pull
#    + integrity check + init.sh symlink resync + main.yaml @tag sed）
cd <repo>
make -f Makefile.ci upgrade VERSION=vX.Y.Z   # 指定版本（推薦）
# 或 make -f Makefile.ci upgrade            # 升到最新 tag
# Fallback（make 不可用時）: ./.base/upgrade.sh vX.Y.Z

# 3. 走 PR merge（branch protection 禁止直接 push main）
git push origin <branch> && gh pr create
```

**升級一律 make 優先，`./.base/upgrade.sh` 留作 fallback**（沒有 make、
或 make target 出問題時才用）。**不要手動 `git subtree pull`** —
`upgrade.sh` 的 init.sh resync 與 `main.yaml` sed 很容易漏；版本追蹤用
subtree 內 `.base/.version`（不是已移除的 root `.template_version` /
`VERSION`）。下游 repo 若要自動升 PR 可加 `.github/dependabot.yml` 監
`github-actions` ecosystem（snippet 見 template README「Updating」章節）。

### 變更時必須同步更新的檢查清單

**所有程式碼修改完畢後，必須先確認文件（README、CHANGELOG、TEST.md）已對齊，才能做 commit。**

### 文件對齊原則

- **TEST.md 是測試的 single source of truth**
  - 每次新增/刪除/改名測試，TEST.md 必須同步更新（總數 + 對應 spec section 的表格）
  - 提交前驗證：`.claude/hooks/check_test_md_drift.sh` 會在每次 Edit/Write
    `*.bats` 或 `TEST.md` 時自動 fire；要手動觸發整套對齊（含 CHANGELOG /
    4 語言 README / emoji / AI 歸屬掃描）跑 `/doc-sync`。Hook 邏輯：parse
    `### test/<rel>.bats (N)` 的 `N`，跟該檔的 `grep -c '^@test'` 比對
    （注意：TEST.md 不全是 one-row-per-test —— `setup_spec.bats` 之類用
    category summary，所以舊的 `grep '^| \`' rows == @test count` 不能用）。
  - README 不重複列測試數量（避免不一致），只連結到 TEST.md

- **CHANGELOG.md 必須記錄使用者會看到的變更**
  - 新功能（feat）、Bug 修正（fix）、破壞性變更（BREAKING）都要寫
  - 內部重構若影響 other repo（如 Dockerfile 路徑、symlink 目標）也要寫
  - 每次 PR merge 前要在 `[Unreleased]` section 加條目

- **README 是使用者第一眼看到的文件**
  - 目錄結構（4 語言版本）必須跟實際檔案一致
  - 指令範例必須能直接複製執行
  - 不要重複可從其他文件查到的細節（測試數量、版本號等）

任何檔案異動（新增、刪除、搬移、改名）都必須檢查以下地方是否需要同步：

| 變更類型 | 需同步更新的地方 |
|----------|-----------------|
| 搬移/改名檔案 | README 目錄結構（4 語言版本）、Dockerfile COPY 路徑 |
| 新增/刪除腳本 | README 目錄結構、script_help.bats（如有 `-h` 支援） |
| 新增/刪除測試 | **TEST.md 必須同步**（總數 + 表格）、CHANGELOG.md（如為使用者可見變更） |
| 新功能/Bug 修正 | CHANGELOG.md `[Unreleased]` section |
| 修改 base 共用腳本 | 先改 base → PR → merge → tag → 各 repo `git subtree pull` |
| base 打 tag | 各 repo 跑 `make -f Makefile.ci upgrade VERSION=vX.Y.Z`（會自動 subtree pull、更新 `.base/.version`、sed `main.yaml` 的 `@tag`；fallback：`./.base/upgrade.sh vX.Y.Z`） |
| 修改 CI workflow | 修改 template 的 reusable workflow，各 repo 透過 `@tag` 自動同步 |

### 已知踩過的坑

| 問題 | 原因 | 教訓 |
|------|------|------|
| `setup.sh` 直接執行時 IMAGE_NAME 偵測錯誤 | `_base_path` 預設用 `BASH_SOURCE` 目錄，不是 repo root | 涉及路徑的預設值要考慮所有呼叫方式 |
| Hadolint CI 太嚴導致全 fail | DL3008 等規則不適用 dev 環境 | 新增 lint 工具時先本地測試 |
| Docker COPY 不 follow symlinks | symlink 指向 .base/，Docker COPY 複製 symlink 本身 | 不要在需要 Docker COPY 的目錄中放 symlinks |
| `sed` apt mirror 在 `-euo pipefail` 下失敗 | glob 匹配不到檔案時 sed 回傳非零 | apt mirror sed 加 `\|\| true` |
| `.env.example` 刪除後 IMAGE_NAME 偵測失敗 | `detect_image_name` 只認 `docker_*` 和 `*_ws` | `.env.example` 保留作為 fallback |

## Process discipline — slash command / skill 優先於 ad-hoc 執行

任何 `.claude/commands/`（`/release` `/pr` `/batch-template-upgrade`
`/issue-fix` `/new-repo` `/doc-sync` `/safe-delete` 等）或 `.claude/skills/`
（`wait-pr-ci` 等）已經涵蓋的 workflow，**優先呼叫 documented entry
point**，不要直接跑底下的 git / gh / make / template 腳本。理由：

1. **Slash command 是 contract**。command body 列的步驟容易在 ad-hoc
   執行時跳掉（例如 `/release` 的 chore-PR 步驟負責 bump `.version` +
   `[Unreleased]` -> `[vX.Y.Z]` promotion；template v0.18.0 / v0.18.1
   就是漏這步，造成下游 `make upgrade-check` 永遠誤報 upgrade available
   — refs issue #36）。Hook layer 補不齊每個漏洞,slash command 才是
   single source of truth。
2. **Skills 已經把 polling / monitoring / batching 包好**。例如 PR CI
   等待用 `wait-pr-ci` skill（內部 `wait-pr-ci.sh` + Monitor + filter
   expression）；改寫成 ad-hoc `gh pr checks` sleep loop 會繞過 filter、
   爆炸 context、踩 parser warning。
3. **Slash command 的 next-step hint 推著 workflow 往前走**。例如
   `batch-template-upgrade.sh` 跑完會自印 `wait-pr-ci-batch.sh` +
   `batch-pr-merge.sh` 的可貼指令；ad-hoc 跳過這層後續步驟容易漏。

**例外**：trivial 一次性檢視（`gh pr view` / `git log -1` /
`gh issue view` / 純讀 file）不適用，繼續 ad-hoc 即可。**多步 mutating
flow（tag、push、merge、release、批次操作）一律走 documented entry**。

若使用者明確要求 ad-hoc 執行某步,照做但要在訊息裡點名「跳過了哪個
documented command / 為什麼」,讓 conversation log 留痕。

### 機器可讀 conventions store — `.claude/instincts.yaml`

CLAUDE.md (這個檔案) 是 narrative source of truth。對於需要程式化查詢
的 convention（shell style / commit title / PR body 規律 / TDD 4 類測試
等），另外有一份 `.claude/instincts.yaml` 用 YAML schema 存結構化版本,
hook / skill / slash command 可以用 `.claude/scripts/instinct-query.sh
<kind> [path]` 查 trigger 命中的 instincts,而不是 grep prose。

支援 5 種 trigger kind:`file_edit`(可選 `glob` / `not_glob` 過濾路徑)、
`git_commit`、`gh_pr_create`、`gh_issue_create`、`bash_command`。
`instinct-query.sh --list` 印出所有 instincts 的 name + kind。

instincts.yaml 與 CLAUDE.md 之間目前**沒有自動同步**;兩邊都需要手改
保持一致。pilot 用 `remind_tdd_categories.sh` 當示範 consumer — 該 hook
在 fire reminder 時會 append 一段 instincts 輸出。Refs #95。

對應的 hook 補強：

- `check_tag_version_consistency.sh` — `git tag v*` / `git push v*` 前
  比對 repo root `.version`，不一致就 deny（取代「記得走 /release」的
  人工約束）
- `enforce_make_first_upgrade.sh` — 三個 surface 都會被 **BLOCK**:
  (1) `./.base/upgrade.sh ...`、(2) `./template/upgrade.sh ...` (legacy
  folder name)、(3) `git subtree pull --prefix=.base|template ...`(raw
  subtree pull)。要求改走 `make -f Makefile.ci upgrade`(make wrapper 內
  部呼叫同一支 .sh,但會幫忙跑 init.sh resync + main.yaml @tag sed)。要
  lift gate 跑 `/tmp` checkpoint protocol(ADR-00000002):touch deny 訊
  息列的 `<ack>` 檔再重發同一條指令即可
- `enforce_batch_via_script.sh` — 跨 repo `for ... do ... done` 配合
  mutating git/gh 操作(`git push|reset|tag|branch -D`、
  `gh (issue|pr) close|merge`、`gh (issue|pr) comment --body`) 時
  **BLOCK** 並要求改寫成 permanent `.claude/scripts/<name>.sh`。read-only
  loop(`gh pr view`、`git log`、`grep`、`cat`)不擋。同樣靠 checkpoint
  protocol lift:touch deny 訊息列的 `<ack>` 檔再重發同一條 loop
- `enforce_worktree_for_branch.sh` — `git checkout -b|-B <branch>` 在主
  checkout 內**BLOCK**,要求改走 `git worktree add <path> -b <branch> main`
  (refs PR #89 / ADR-00000006)。Worktree 內部偵測靠 `git rev-parse
  --git-dir` vs `--git-common-dir` -- 兩者不同代表在 worktree 內,自動放行。
  `git switch -c` 暫不擋(可能 follow-up)。`git checkout -- <file>` /
  `git checkout <existing-branch>` 不擋。同樣靠 checkpoint protocol lift
- `check_prefer_dot_sh.sh` — `docker build/run/exec/stop` 與
  `docker compose <up|down|build|run|exec>` 前：cwd 有對應 `.sh` wrapper
  就 deny + 提示改用 wrapper(會帶 setup.sh 自動更新 .env / compose.yaml
  + 語言環境 + GPU/GUI 偵測);沒對應 wrapper 則強制 ask 跳 prompt,
  user 沒明確同意不放行(取代「直接跑 docker 繞過 wrapper 邏輯」的
  人工約束)。read-only 子命令(ps/images/inspect/...)、make 內部觸發的
  docker compose、已在 ask 列表的破壞性 docker subs 都不受影響。

## Per-project memory（repo-portable via symlink）

Claude Code 的 per-project memory 預設存在
`~/.claude/projects/<encoded-workspace-path>/memory/`,其中
`<encoded-workspace-path>` 是把 workspace 絕對路徑的 `/` 換成 `-`
（例如 `/home/yunchien/workspace/docker` →
`-home-yunchien-workspace-docker`）。這個路徑被 workspace 絕對位置
鎖死,**換機器或改 workspace 路徑就會失聯**。

為了讓 memory 跟 repo 走 + 進 git history,實際 memory 檔案存在
`<workspace>/.claude/memory/`(git-tracked),Claude Code 預期的位置
則用 symlink 連回來：

```
<workspace>/.claude/memory/                       (git-tracked source of truth)
├── MEMORY.md                                     (index, ≤150 chars/line)
├── feedback_*.md                                 (workflow / convention rules)
└── project_*.md                                  (project context)

~/.claude/projects/-home-yunchien-workspace-docker/memory  →  symlink → <workspace>/.claude/memory
```

### 新 clone / 換機器 setup

跑一次：

```bash
bash .claude/scripts/setup-memory-link.sh
```

idempotent — 偵測現有 symlink target,已正確就 skip；偵測舊
non-symlink 資料夾且內容跟 repo 一致就 rm + symlink；偵測新內容
（這台機器才有的 entry）就 refuse 並要求先 merge 進 repo,除非
`--force`(會先備份成 `.backup-<timestamp>`)。

`--dry-run` 看預期動作。`--workspace <path>` / `--home <path>` 給
測試用 override。

### Memory 檔案規則（不變）

仍依 Claude Code 標準格式：

- frontmatter `name` (kebab-case slug) + `description` + `metadata.type`
  (`user` / `feedback` / `project` / `reference`)
- 主檔名跟 `name` 對齊（如 `feedback_no_emoji.md`）
- `MEMORY.md` 是 index — 一行一個 entry,`- [Title](file.md) — hook`
- 用 `[[name]]` 連 related memories

詳細寫法見 auto-memory section（system prompt 開頭）。

## 主動優化建議

工作過程中如果發現以下情況，**必須主動提出**，與使用者討論後再執行：

- 工作流程過於繁瑣、可以自動化的重複步驟
- 跨 repo 不一致或容易遺漏的手動同步
- 程式碼品質或架構上的改善機會
- 過時的文件、設定或慣例
- 可以用腳本取代的手動操作

> 不要默默執行優化，先提出來討論。

執行細節（候選分類、提案的措辭、何時不該提）見
`.claude/skills/proactive-optimization/SKILL.md`。配對的
`remind_proactive_optimization.sh` Stop hook 會在 task boundary
（gh pr merge 或 tool count >= 50）且 session 未提任何 optimisation
候選時，emit 一條 systemMessage 提醒。Disable via
`PROACTIVE_OPTIMIZATION_REMIND_DISABLE=1`。

### 任務結束時主動列 skill 化候選

任務收尾（PR merged / 工作結案）時，若這次工作中產生或演化了「下次還會
再做一次」的工具/腳本/工作流，**主動列出來提案是否要 skill 化**：

- `/tmp/` 下落地的 ad-hoc script（會跨 session 遺失）
- 重複 3 次以上的複雜 bash pipeline / for-loop（容易 hit Claude Code parser 限制 → user 要 yes）
- 既有 slash command 沒覆蓋的 workflow gap
- 既有 skill 在實作中發現的小 bug 或可改進點

提案格式：列「候選名 / 結構（command + script / 純 skill 描述）/ 優先度」，
讓使用者決定要不要動。**不要在工作中插話打斷流程**；也**不要每個任務都列**
— 只在真的有 ≥1 個高價值候選時才列。

### 工作量大時使用平行 Agent

當需要對多個 repo 或多個語言做相同操作時，**使用多個 Agent 平行處理**而非逐一執行：

- 例如：修改 17 個 repo 的 README → 啟動 3 個 Agent 各處理一批
- 例如：批次 PR → 分批平行建立
- 最大 3 個 Agent 同時運行

## 新建容器流程

使用 `/new-repo` slash command。所有新 repo 必須使用與 base repo 相同的架構：

- 加入 `.base/` subtree：`git subtree add --prefix=.base git@github.com:ycpss91255-docker/base.git <version> --squash`
- 執行 `./.base/init.sh`（自動偵測：有 Dockerfile → 既有 repo 初始化；無 Dockerfile → 產生完整結構）
- 共用腳本用 symlink：`build.sh`、`run.sh`、`exec.sh`、`stop.sh`、`Makefile` → `.base/script/docker/`
- Dockerfile 遵循 base 分層慣例（bats-src / lint-tools / sys / base / devel / test）
- CI 使用 base 的 reusable workflows（`build-worker.yaml`、`release-worker.yaml`）
- 版本追蹤用 subtree 內 `.base/.version`（`git subtree pull` / `upgrade.sh` 會自動更新；不再需要 root 層 `.template_version`）
- Smoke test 放 `test/smoke/`，共用測試從 base 的 `test/smoke/` COPY

## Git 設定

```bash
git config user.name "<your-name>"
git config user.email "<your-email>"
```

GitHub 組織：`ycpss91255-docker`
