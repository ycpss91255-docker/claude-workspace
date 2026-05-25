---
name: 改 git repo 一律用 git worktree
description: 對任一 repo 開新 branch / 做修改時，必須 git worktree add 到 <workspace>/worktree/<repo>-<N>/，不准在主 checkout 跑 checkout -B；資料夾不存在時要先問 user
type: feedback
originSessionId: 57c42783-dd59-4158-905a-b8d90ffa7347
---
對 18 個下游 repo + template 中任一個做修改（開 branch / WIP / chore PR），**必須**用 `git worktree add`，**不可**直接在主 checkout 跑 `git checkout -B <branch>` 弄髒 working tree。

**Why:**
- 主 checkout 留作「latest origin/main 的乾淨參考」— 多個 Claude session 可同時讀同一份不打架
- 平行 branch / PR 不需要 stash 或 switch，各自一個 worktree 各自跑
- 不會 reflexively commit 到錯 branch（過去踩過）
- 跟 per-repo Claude session 工作流相符 — `cd <workspace>/worktree/<repo>-<N> && claude` 自動拿到對的 cwd slug、symlinked `.claude/` + `CLAUDE.md`、隔離的 memory

**How to apply:**
- 標準位置：`<workspace>/worktree/<repo>-<N>/`（**已 gitignored**，line 20 of `<workspace>/.gitignore`）
- 命名：N 通常用 PR / issue 編號（範例：`template-177`、`claude-workspace-22`），尚無編號時可用 branch slug
- 起新 branch：`git worktree add <workspace>/worktree/<repo>-<N> -b <branch> main`
- merge 後：`git worktree remove <path>` 收尾，或定期 `git worktree prune` 清 stale entry
- **批次 script 例外**：`batch-base-upgrade.sh` / `batch-gitignore-fix.sh` / `batch-pr-merge.sh` 內部已有 `fetch + checkout -B main FETCH_HEAD + checkout -B <branch>` 流程，且只跑於受控批次 — 不需改寫成 worktree 流程
- **fresh machine 沒 `<workspace>/worktree/`**：**必須先問 user**「要建在 `<workspace>/worktree/` 還是別處？」或「直接 mkdir？」— 不准自行猜
- **rm worktree 資料夾不用問**：刪除 `<workspace>/worktree/<repo>-<N>/` 任一個 worktree dir（例如 `git worktree remove <path>` 之後手動清殘骸 / cleanup stale）**直接刪不問** — 既有 `auto_allow_rm_in_workspace.sh` hook 已 cover workspace 路徑下所有 rm，這條只是文字化 explicit 確認
