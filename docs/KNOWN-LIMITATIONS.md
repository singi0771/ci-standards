# 已知限制（導入前先看）

這份文件記的是**實測過、但目前還不能用**的東西。
每一條都寫清楚：怎麼測的、結果是什麼、影響哪一段流程、以及排查步驟。

> 為什麼要有這份文件：這些結論原本只存在於某個已關閉 PR 的留言裡，
> 後來導入的人看不到，只會重踩一次同樣的坑。

| 限制 | 影響 | 現在該怎麼辦 |
|---|---|---|
| [Copilot Coding Agent 不回應 Actions 貼的 `@copilot`](#copilot-coding-agent-對-actions-貼的-copilot-沒有反應) | 「自動修」的**自動觸發**那一步 | Agent 本身可用 —— 改成手動「開 Issue 指派 Copilot」即可 |
| [Copilot 觸發的 workflow 卡在 `action_required`](#copilot-觸發的-workflow-run-會卡在-action_required) | Copilot 開的 PR 可能不跑 CI | 改 repo 的 Actions 核准設定 |
| [`upload-sarif: true` 尚未驗證可用](#upload-sarif-true-尚未驗證可用) | Security 分頁整合 | 維持 `false`，用 artifact |
| [只有 Python 的 lint/test](#ci-reusable-只內建-python-的-linttest) | 非 Python 專案 | `run-python: false` + 自己補一支 |

---

## 實測基準：canary PR（2026-07-26）

排查前先知道「哪些是確定好的」，才不會亂改。

做法：開一個 PR 故意植入三個錯誤 —— shellcheck 的 `SC2086`（未引用的 `rm -rf $TARGET`）、
`SC2045`（用 `ls` 輸出當迴圈來源）、以及把 `actions/checkout` 從釘死的 SHA 改回可變 tag（Semgrep 會抓）。
CI 與 Security 會在數秒內相繼失敗，正好用來驗證去重機制。

**確認可用的（不用再花時間排查）：**

| 觀察項 | 結果 |
|---|---|
| `ci / CI Gate` 與 `security / Security Gate` 都變紅 | ✅ 三個植入的錯誤全被抓到 |
| CI 紅 + Security 紅 → autofix 只貼 **1** 則留言 | ✅ 第 2 次判定 `Cooldown: fix request posted in last 15 min — skipping duplicate` |
| 修好後 autoreview 只請 **1** 次審查 | ✅ CI 那次判定「Security 尚未通過」跳過，Security 那次才 `Review request 1/3` |
| Copilot **Code Review** 會動 | ✅ 跑了兩次（紅的時候一次、雙綠後一次） |
| Copilot **Coding Agent** 會動（指派 Issue，2026-08-01 補測） | ✅ 立刻開出 PR |
| 通知量 | ✅ **4 個觸發事件只產生 2 則留言** |

**失敗的：** 見下面兩節。

---

## Copilot Coding Agent 對 Actions 貼的 `@copilot` 沒有反應

**狀態：🟡 已定位到單一原因，有解法待實作**

`copilot-autofix-*` 三支的核心動作，是用 `GITHUB_TOKEN` 在 PR 貼一則 `@copilot ...` 留言。
留言作者是 `github-actions[bot]`。實測結果：

| 日期 | 測法 | 結果 |
|---|---|---|
| 2026-07-26 | Actions 貼 `@copilot` 留言到 PR | ❌ 等 12 分鐘無反應 |
| 2026-07-26 | GraphQL `replaceActorsForAssignable` 指派 Copilot 到人類開的 PR | ❌ 等 9 分鐘無反應（**但這是無效測試**，見下） |
| 2026-08-01 | **指派 Copilot 到 Issue**（官方入口） | ✅ **立刻開出 PR**（Issue #5 → PR #6） |

### 結論：Agent 是好的，卡住的是「bot 貼的留言」這個入口

2026-08-01 的測試證明 **Coding Agent 在這個帳號、這個 repo 上完全可用** ——
方案有到、policy 有開、`copilot-setup-steps.yml` 沒問題。

所以問題收斂成單一一點：**GitHub 對「bot 觸發 bot」的防迴圈限制**，
讓 `github-actions[bot]` 貼的 `@copilot` 不會喚醒 Agent。

### ⚠️ 7/26 的第二個測試是無效的，別拿它當證據

把 Copilot 指派到**人類開的既有 PR**，**本來就不是**官方支援的觸發方式。
Coding Agent 官方只認兩種入口：

1. 指派到一個 **Issue**
2. 在 **Copilot 自己開的 PR** 上留言要求修改

「直接指派也沒反應」證明不了「bot mention 被擋」，只證明了「那個入口不存在」。
當時因為這個無效測試，一度以為是方案或 policy 的問題 —— 其實不是。

### 排查步驟

**第 1 關 —— Coding Agent 到底有沒有開？** ✅ 本 repo 已於 2026-08-01 通過

開一個內容明確、範圍很小的 Issue，右側 Assignees 指派給 **Copilot**，等 10–15 分鐘。

- 它開了 PR → ✅ Agent 可用，跳到第 2 關
- Assignees 清單裡**根本找不到 Copilot** → 方案或 policy 沒開，跳到第 1.5 關
- 找得到、指派得下去、但沒動作 → 看 repo 的 Agents / Copilot 分頁有沒有失敗的 session，通常是 `copilot-setup-steps.yml` 掛了

> **導入新專案時這一關要重測。** 方案是帳號層級的，但 policy 與
> `copilot-setup-steps.yml` 是 repo 層級的 —— ci-standards 過了不代表 AdminAutoTools 也過。

**第 1.5 關 —— 方案與 policy**（第 1 關沒過才需要）

- Copilot Coding Agent 需要 **Copilot Pro+ / Business / Enterprise**。一般的 Copilot Pro **沒有**這個功能。
- Org → Settings → Copilot → Policies → **Copilot coding agent** 要是 Enabled。
- 個人帳號則在 Settings → Copilot 底下確認。

> 這一關沒過就**不要再往下調參數**，換 token 也不會有用 —— 引擎根本沒裝上去。

**第 2 關 —— Agent 可用，但不吃 bot 的留言** 🟡 本 repo 現在卡在這裡

第 1 關過了（指派 Issue 會動），但 Actions 貼的 `@copilot` 還是沒反應 —— 這就是 GitHub 的
bot 防迴圈限制。解法是換掉貼留言用的 token：

1. 建一個 fine-grained PAT 或 GitHub App token，權限只要 Pull requests / Issues 讀寫
2. 存成 secret（例如 `COPILOT_TRIGGER_TOKEN`）
3. 公版 reusable 加 `secrets:` 區塊接收它，把 `GH_TOKEN: ${{ github.token }}` 換成該 secret
   —— **不可以用 `secrets: inherit`**，那會造成 `startup_failure`（見 commit `c19ff64`）
4. Repo → Settings → Actions → General → 勾 **Allow GitHub Actions to create and approve pull requests**

**第 3 關 —— 換了 token 還是不動**

那就接受現實：Coding Agent 只從 Issue 進入。把 `copilot-autofix-*` 從
「貼 `@copilot` 留言」改成「**開一個 Issue 並指派 Copilot**」——
這條路已經證實可行（Issue #5 → PR #6）。

要注意的是換成開 Issue 之後，收斂機制要跟著改：目前的次數上限與去重是靠
PR 留言裡的隱藏 marker 計數，改開 Issue 就要改成用 label 或 Issue 標題 marker，
否則每次 CI 失敗都會開一個新 Issue。

### 在這件事解決之前，怎麼導入

**照常導入，只是「修」這一步改成手動觸發。** 完整可用的路徑是：

```
免費掃描器「找」→ Security Gate 擋門 → Copilot Code Review「審」（自動）
   → 開 Issue 指派 Copilot「修」（手動一步）→ 人 merge
```

三支 `copilot-auto*` 複製過去不會有害（沒反應而已，也不燒 credits），
但**不要拿它們當導入成功的驗收標準**。

---

## Copilot 觸發的 workflow run 會卡在 `action_required`

**狀態：🟡 有解，但要改 repo 設定**

canary 測試中，Copilot 送出 code review 之後觸發的 `Copilot Autofix — Review` run
停在 `action_required`（要人按 **Approve and run**），不會自己執行。

**影響範圍比看起來大**：這代表**任何由 Copilot 活動觸發的 workflow run 都可能需要人工核准**。
真正麻煩的不是這支 workflow（它吃 `changes_requested`，而 Copilot 只送 COMMENT，實務上不會走到），
而是**未來 Copilot Coding Agent 開的 PR** —— 那些 PR 的 CI / Security run 若也卡在 `action_required`，
Gate 就形同停擺，自動修好的 PR 永遠不會變綠。

**排查：**

1. Repo → Settings → Actions → General → **Fork pull request workflows from outside collaborators**
   —— 若是 `Require approval for first-time contributors` 或更嚴，Copilot 會被歸到需要核准那一類
2. 放寬到 `Require approval for first-time contributors who are new to GitHub`（或依你的風險胃納選）
3. 改完之後**重跑一次 canary**，確認 Copilot 觸發的 run 會自動執行

> 這是安全性與自動化的權衡，不是純技術問題。public repo 放太寬會讓任何人 fork 後跑你的 Actions，
> 決定前先確認 repo 的可見性與 spending limit（Actions 應設 $0，見 [SETUP §D](SETUP.md#d-額度與帳務)）。

---

## `upload-sarif: true` 尚未驗證可用

**狀態：🟡 疑似不可用，維持 `false`**

`security-reusable.yml` 的 workflow 層 `permissions` 是 `contents: read`。
被呼叫的 reusable workflow **只能縮減呼叫端授予的權限、不能擴張**，
所以呼叫端就算自己加了 `security-events: write`，進到公版的 job 仍可能被縮掉 → upload 回 403。

也就是說 README 上「呼叫端 job 自行加 `permissions:`」這個說法**還沒有被實測證實**。

**排查步驟：**

1. 在本 repo（public，不需要 GHAS）開一個測試 PR，把 `.github/workflows/security.yml` 的
   `upload-sarif` 改成 `true`，並在該 job 加上 `permissions: { contents: read, security-events: write }`
2. 看 `Upload SARIF to Security tab` 這一步的結果：
   - 成功 → 只要更新文件說明「呼叫端必須自行加 permissions」
   - 403 / Resource not accessible → 公版要改：在 `security-reusable.yml` 的 workflow 層
     直接宣告 `security-events: write`。**但這是破壞性變更** —— 沒有授予該權限的呼叫端可能整支起不來，
     要按[版本策略](../README.md#版本策略)開 `v2`，不能移 `v1`
3. 在這之前，掃描結果一律走 artifact（`semgrep-sarif`），功能上沒有損失

---

## `ci-reusable` 只內建 Python 的 lint/test

**狀態：🟢 已知設計取捨，不是 bug**

`ci-reusable.yml` 內建的是 ruff + pytest。其餘語言目前沒有對應的 job。

非 Python 專案**仍然照用公版**，把 Python 關掉即可（`run-python: false`），
`actionlint` / `shellcheck` / `docker build` 三項都是語言無關的。
要語言原生的 lint/test，見 [README — 專案不是 Python](../README.md#專案不是-python)。

> 推廣到更多專案之前，先盤點一次組織內的語言分布。
> 如果 Node 專案佔比高，補一支 `ci-node-reusable.yml` 的優先度會高於其他所有待辦。

---

## 這份文件怎麼維護

- 每解決一條，把它**從這裡刪掉**，並在 [CHANGELOG](../CHANGELOG.md) 記一筆
- 新發現的限制，一律附上「怎麼測的 + 結果 + 排查步驟」，不要只寫「XX 好像不能用」
- 排查步驟要能讓沒有前後文的人照著跑
