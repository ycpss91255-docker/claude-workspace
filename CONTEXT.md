# CONTEXT.md

Domain knowledge and reference material for the `docker` workspace.
Companion to `CLAUDE.md` and `doc/adr/`.

## Routing rules

| Looking for... | Read | Why |
|---|---|---|
| A **standing rule** (must/never, style, workflow contract) | `CLAUDE.md` | Loaded into every session's system prompt; size-sensitive |
| **Domain knowledge** (how the system is structured, what each piece does, default values, gotchas) | This file (`CONTEXT.md`) | View on-demand; can grow without prompt-bloat cost |
| A **historical decision** (why we picked X over Y, postmortem of an incident, superseded approach) | `doc/adr/NNNNNNNN-*.md` | One file per decision; 5-section template (Date / Status / Context / Decision / Alternatives / Consequences); see ADR-00000001 for the meta-rationale |

The split is intentional: `CLAUDE.md` is the agent's working memory
contract, this file is the reference manual, and ADRs are the
incident log. New rationale should never land in `CLAUDE.md` — it
goes in an ADR. New domain knowledge should never land in `CLAUDE.md`
— it goes here.

## 1. Naming & file conventions

- 繁體中文 README：**`README.zh-TW.md`**（連字號，非底線）
- 英文 README：`README.md`
- 環境範本：`.env.example`（只含 `IMAGE_NAME=<name>`）
- Docker Compose：`compose.yaml`（非 `docker-compose.yaml`）

## 2. Container architecture

### Directory tree

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
└── .github/workflows/        # docker_harness 自身 CI（test.yaml）
```

`.claude/` 內部結構詳見 CLAUDE.md「目錄結構」section（CLAUDE.md
是 single source of truth；CI lint `check-claude-md-tree.sh` 會
比對 filesystem，drift 就 fail）。

### Standard container layout

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

### `.base` subtree structure

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

### User & permission management

Dockerfile 接受 `USER_NAME`、`USER_UID`、`USER_GID` 參數，在容器內建立
與主機 UID/GID 相符的用戶。sys stage 處理 UID/GID 衝突。

### Multi-stage build conventions

- `bats-src` / `bats-extensions` / `lint-tools` stage：測試工具來源（不出貨，可用 `test-tools:local` 替代）
- `sys` stage：用戶/群組建立、sudo 設定、時區語系、APT mirror 設定
- `base` stage：開發工具與語言套件
- `devel` stage：應用專屬工具 + entrypoint + PlotJuggler（env repos）
- `test` stage：ShellCheck → Hadolint → Bats smoke test（短暫性，build 完即丟）
- `runtime` stage：（僅應用程式類型）最小化 runtime
- Shell 設定：`SHELL ["/bin/bash", "-x", "-euo", "pipefail", "-c"]`

## 3. Setup pipeline (`setup.conf` → `.env` + `compose.yaml`)

`setup.sh` 讀取 `setup.conf`（INI 格式設定）+ 系統偵測 → 產生 `.env` 與
`compose.yaml` 兩份 derived artifacts。來源是 `setup.conf`，不要直接手改
`.env` / `compose.yaml`（下次 build/run 會被覆蓋）。

**每次 `build.sh` / `run.sh` 預設都會重新產生 `.env` + `compose.yaml`**，
使用 `--no-env` 跳過。`setup.sh` 會保留既有 `.env` 中有效的 `WS_PATH`、
`APT_MIRROR_*`。

### `setup.conf` location & override strategy

- `.base/config/docker/setup.conf` — 模板預設值（4 個 section；路徑自 #262 / v0.25.0 起）
- `<repo>/config/docker/setup.conf` — 選用 repo override。**Section-replace**：
  repo 檔有的 section 完整取代模板該 section；repo 沒列的 section
  繼續用模板預設

### `setup.conf` section schema

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

### System-detected items (do not read `setup.conf`)

- 使用者資訊：UID/GID/USER/GROUP（`id`）
- 硬體架構：`uname -m`
- Docker Hub 用戶
- WS_PATH 工作區三策略偵測：同層掃描 → 向上遍歷 → 退回上層目錄
- APT_MIRROR_UBUNTU / APT_MIRROR_DEBIAN：預設台灣鏡像，保留既有值

### Drift detection

`setup.sh` 在 `.env` 中寫入 `SETUP_*` metadata（包含 `SETUP_CONF_HASH`，
SHA256 over 模板 + repo setup.conf）。build/run 會比對 hash，若 setup.conf
已變動會自動重跑；使用者手改 .env 不會觸發重跑，但會在下次不帶 `--no-env`
時被蓋掉。

### `compose.yaml` conditional blocks

`generate_compose_yaml` 依 `[gpu]`/`[gui]` resolve 結果條件組裝：
- GPU 啟用 → 輸出 `deploy.resources.reservations.devices`（`nvidia` + count + capabilities）
- GUI 啟用 → 輸出 DISPLAY / WAYLAND / XDG_RUNTIME_DIR / XAUTHORITY 的 env + volume
- 基線 volumes 永遠輸出（`${WS_PATH}:/home/${USER_NAME}/work`），`[volumes] mount_*` 加在其後

## 4. Subtree mechanics (`.base/` upgrade flow)

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

## 5. CI/CD

### Reusable workflows

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

### Smoke Tests link convention

所有 repo 的 README Smoke Tests section 簡化為連結到 TEST.md：
```markdown
## Smoke Tests

See [TEST.md](doc/test/TEST.md) for details.
```

### CI 監控 (PR open 後)

開完 PR 後不要用 `sleep` 輪詢、也不要反覆手動跑 `gh pr checks`。改用
**`wait-pr-ci` skill**（`.claude/skills/wait-pr-ci/SKILL.md`）— 內部以
Monitor 工具 + `until` poll loop 30s 間隔，每個 check 從 pending 變化時
噴一行通知，全部 settle 後噴 `ALL_DONE`，agent 不會被 sleep 卡住、
context 也不會被 polling output 噴爆。

適用情境：
- 剛開完 PR 等 merge
- 同 batch 多個 PR 平行等
- `@dependabot rebase` 後 CI 重跑

不適用 tag-triggered workflow（release-test-tools / release-worker）—
那是 tag-scoped 不是 PR-scoped，套同樣 Monitor pattern 但改查
`gh run list --branch <tag>`。

skill 內含 status check filter 對應表（template / docker_harness /
單 distro 容器 / multi-distro env / multi-distro app / .github），
詳見 SKILL.md。

## 6. Versioning & release

### SemVer X/Y/Z semantics (2026-05-15 update, refs #106)

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
`.version` integrity。配對的 `[[semver-bump]]` skill 詳列 X/Y/Z 程序
（CLAUDE.md 的 release section 是 standing rule pointer，這裡只列語意
細節，不複製 step-by-step 流程）。

### Release flow

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

## 7. i18n (script message localisation)

腳本訊息支援 4 種語言：`en`（預設）、`zh`（繁中）、`zh-CN`（簡中）、`ja`（日文）。

| 元件 | i18n 方式 | 切換方法 |
|------|----------|---------|
| `setup.sh`（template） | `_msg()` 函式 | `--lang` flag 或 `SETUP_LANG` 環境變數 |
| `build.sh` / `run.sh` | usage() case 分支 + 轉發 `--lang` 給 setup.sh | `--lang` flag 或 `SETUP_LANG` 環境變數 |
| `exec.sh` / `stop.sh` | usage() case 分支 | `SETUP_LANG` 環境變數 |
| README | 各語言獨立檔案放在 `doc/` | 頂部語言切換連結 |

### Shell script conventions

- 所有 `.sh` 使用 `set -euo pipefail`
- Help 統一使用 `usage()` 函式 + `cat >&2`
- 所有互動腳本（build.sh / run.sh / exec.sh / stop.sh）支援 `-h` / `--help`
- build.sh / run.sh 支援 `--lang` 旗標
- ShellCheck compliant（CI 強制）

## 8. Defaults (locale / timezone / APT / GPU / GUI)

### Locale (important — order matters on Debian bookworm)

Debian bookworm 必須先 uncomment `/etc/locale.gen` 再 `locale-gen`，
`LC_ALL`/`LANG` ENV 必須在 `locale-gen` **之後**設定：

```dockerfile
RUN sed -i 's/^# *en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && \
    locale-gen && \
    update-locale LANG="en_US.UTF-8"

ENV LC_ALL="en_US.UTF-8"
ENV LANG="en_US.UTF-8"
```

### Timezone & locale

所有容器預設使用 `Asia/Taipei` 時區與 `en_US.UTF-8` 語系。

### APT mirror

`setup.sh` 產生的 `.env` 包含 APT mirror 設定：
- `APT_MIRROR_UBUNTU=tw.archive.ubuntu.com`
- `APT_MIRROR_DEBIAN=mirror.twds.com.tw`

Dockerfile 透過 `ARG` + `sed` 使用，`|| true` 防止檔案不存在時失敗。

### GPU support

AI Agent 容器透過 `devel-gpu` service 支援 NVIDIA GPU（CPU 為預設）。
`post_setup.sh` 偵測 GPU 後設定
`BASE_IMAGE=nvidia/cuda:13.1.1-cudnn-devel-ubuntu24.04`。ROS 環境容器
透過 compose.yaml 的 `deploy.resources.reservations.devices` 設定。

## 9. AI Agent credential isolation

只掛載**憑證檔案**，不掛載整個設定目錄：
- Claude：`~/.claude/.credentials.json`
- Gemini：`~/.gemini/oauth_creds.json`
- Codex：無 OAuth 檔案，僅使用 `OPENAI_API_KEY`

## 10. Branch protection (per-repo `required_status_checks`)

所有 `ycpss91255-docker` 組織下的 repo，main branch 一律啟用 branch
protection，**包含 admin**，任何情境都不允許直接 push：

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

新建 repo 時必須同步設定 branch protection，`/new-repo` slash command
應自動處理。

## 11. TDD 4-category matrix

所有變更採嚴格 TDD：先寫失敗測試 → 寫最少程式碼讓測試通過 → 重構。
任何變更先思考「這次動到的東西，落在 1～4 哪幾類？」每個受影響的類別都
要有對應測試覆蓋。

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

### Rules

- **Lint 也算測試**：雖然不是「跑得起來」型，但同樣在 CI 強制；新檔 / 新規則要先讓 linter 失敗才修，不靠人工檢查
- **Unit 對 Dockerfile 通常 N/A**：純宣告式內容無邏輯可隔離；改 Dockerfile 改用 smoke + lint 覆蓋
- **TEST.md 是 single source of truth**：4 類測試的數量與位置都記在 `doc/test/TEST.md`，每次新增 / 刪除 / 改名測試必須同步（hook `check_test_md_drift.sh` 會自動比對）
- **驗證一律走 Docker**：4 類都透過 `./build.sh test` 或 `make -f Makefile.ci test` 在 Docker image 內執行，不接受本機 bats / shellcheck 通過作為驗證

## 12. Docker-only verification

**所有 lint 與 test 驗證只能透過 Docker 執行**，不要直接呼叫本機的
`bats`、`shellcheck`、`hadolint`、`kcov` 等工具。理由：
- 本機環境可能缺少 `bats-mock`、特定版本 bats-support / bats-assert，或
  shellcheck 版本與 CI 不同，會得到與 CI 不一致的結果
- CI 的 reusable workflow 也是透過同一組 Docker image 執行，走 Docker
  可以確保本地與 CI 行為一致

入口：
- `./build.sh test` — Dockerfile `test` stage（ShellCheck → Hadolint → Bats smoke）
- `make -f Makefile.ci test` / `lint` — base 自身的 unit/integration 測試

## 13. Known gotchas

| 問題 | 原因 | 教訓 |
|------|------|------|
| `setup.sh` 直接執行時 IMAGE_NAME 偵測錯誤 | `_base_path` 預設用 `BASH_SOURCE` 目錄，不是 repo root | 涉及路徑的預設值要考慮所有呼叫方式 |
| Hadolint CI 太嚴導致全 fail | DL3008 等規則不適用 dev 環境 | 新增 lint 工具時先本地測試 |
| Docker COPY 不 follow symlinks | symlink 指向 .base/，Docker COPY 複製 symlink 本身 | 不要在需要 Docker COPY 的目錄中放 symlinks |
| `sed` apt mirror 在 `-euo pipefail` 下失敗 | glob 匹配不到檔案時 sed 回傳非零 | apt mirror sed 加 `\|\| true` |
| `.env.example` 刪除後 IMAGE_NAME 偵測失敗 | `detect_image_name` 只認 `docker_*` 和 `*_ws` | `.env.example` 保留作為 fallback |
