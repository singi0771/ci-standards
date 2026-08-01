# 已知限制

## Copilot Coding Agent 無法回應 bot 貼的 `@copilot` 留言

**發現時間**：2026-07-26 canary 測試

**症狀**：`copilot-autofix-*` workflow 用 `GITHUB_TOKEN`（作者為 `github-actions[bot]`）
在 PR 貼出 `@copilot ...` 留言後，Copilot Coding Agent 沒有任何反應（沒開始 commit、
也沒出現 agent session）。

**根本原因**：GitHub 有「bot 防迴圈」機制，阻止一個 bot 的行為觸發另一個 bot。

**現況**：尚未確認所有帳號/方案是否一致；可能與 Copilot Business 開啟方式有關。

**繞過方式**：  
改用 fine-grained PAT 或 GitHub App token（作者為真實使用者或 App）替換 `GITHUB_TOKEN`，
詳見 [docs/SETUP.md — B. 啟用 Copilot 兩個 Agent](SETUP.md#b-啟用-copilot-兩個-agent)。

---

## CI Gate / Security Gate 永遠 pending（PR 卡死）

**症狀**：PR 上的 required check 一直顯示 pending，從未變成 pass 或 fail。

**原因**：有 `if:` 條件的 job 被 skip 時，GitHub **不會** 回報 check 狀態 → required check
永遠等不到回應。

**規則**：有條件的 job 絕不設為 required check；一律加進 `ci-gate` / `security-gate` 的
`needs:`，由 gate job 統一判斷（只有 `failure` / `cancelled` 才擋）。

---

## 指派既有 PR 給 Copilot 無效

**症狀**：把 Copilot 指派到一個人類建立的既有 PR，沒有任何反應。

**原因**：官方入口只有兩個：**指派到 Issue**、或在 **Copilot 自己開的 PR** 上留言。
把 Copilot 指派到既有 PR 不是官方支援的觸發入口。

**正確觸發方式**：

1. 開一個 Issue，右側 Assignees 指派給 Copilot
2. 或：在 Copilot 自己建立的 PR 上留言 `@copilot ...`
