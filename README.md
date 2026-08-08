# ci-standards — 團隊統一 CI / 安全掃描中央公版

這個 repo 是**中央公版**。安全掃描與 CI 的邏輯只寫在這裡一次，所有專案用**一行 `uses:`** 呼叫它。
公版更新 → 移動 tag → 各專案下次跑 CI 就自動同步，不必逐一改每個 repo。

> 適用環境：私有 repo、免費開源工具，**不需要 GitHub Advanced Security**。搭配 Copilot Business 可再啟用「自動修 + 自動審」閉環。

---

## 目錄

0. **[已知限制（導入前先看）](docs/KNOWN-LIMITATIONS.md)** —— 哪些功能實測過但還不能用
1. [運作原理（先看這個）](#運作原理先看這個)
2. [5 分鐘導入一個新專案](#5-分鐘導入一個新專案)
3. [導入後，日常怎麼用](#導入後日常怎麼用)
4. [自動修復閉環（選配，需 Copilot Business）](#自動修復閉環選配需-copilot-business)
5. [可調參數（inputs）](#可調參數inputs)
6. [分支保護：讓流程「非過不可」](#分支保護讓流程非過不可)
7. [常見情境客製](#常見情境客製)
8. [疑難排解](#疑難排解)
9. [版本策略](#版本策略)
10. [檔案地圖](#檔案地圖)
11. [這套涵蓋什麼、不涵蓋什麼](#這套涵蓋什麼不涵蓋什麼)

---

## 運作原理（先看這個）

```
你的專案 repo                          ci-standards（本 repo）
─────────────────                      ────────────────────────
.github/workflows/security.yml  ──呼叫──▶ security-reusable.yml
   jobs.security:                          ├─ SAST (Semgrep)
     uses: ...@v1                          ├─ Dependency vuln (OSV-Scanner)
     with: { ... }                         ├─ FS / IaC / Docker (Trivy)
                                           ├─ Secret scan (gitleaks)
                                           ├─ Docker image (Trivy)  ←可選
                                           └─ 🛡️ Security Gate ←彙總，分支保護只認這個

.github/workflows/ci.yml        ──呼叫──▶ ci-reusable.yml
   jobs.ci:                                ├─ Python lint + test    ←可選
     uses: ...@v1                          ├─ Docker build check    ←可選
     with: { ... }                         ├─ Workflow lint (actionlint) ←可選
                                           ├─ Shell lint (shellcheck)    ←可選
                                           └─ 🧪 CI Gate ←彙總，分支保護只認這個
```

> CI 的四項子檢查**每一項都可以獨立開關**（見[可調參數](#ci-reusableyml)）。
> 全關掉也不會讓 Gate 變紅 —— Gate 只認 `failure` / `cancelled`，`skipped` 一律算過。

**呼叫端只有十幾行、沒有邏輯**。要改掃描規則、加工具、升版本 —— 全部改這個 repo，不動任何專案。

### 為什麼有 Security Gate / CI Gate

兩者都是 `needs` 全部子 job 的彙總 job：任一子 job 失敗它就失敗。
所以**分支保護只要求這兩個 check**，日後你在公版增減工具，不必回頭改每個 repo 的 ruleset。

更重要的是：**不要把有 `if` 條件的 job 直接設成 required check**。
`docker-build`（`run-docker-build: false` 時）和 `trivy-image`（`scan-docker-image: false` 時）會變成
`skipped`，而 skipped 的 required check **永遠不會回報結果**，PR 就會卡在 pending 卡到天荒地老。
Gate job 用 `if: always()` 執行、自己判斷「skipped 算過、failure 才擋」，就沒有這個問題。

### 完整閉環（有 Copilot Business 時）

```
免費掃描器「找」弱點 → 開 Issue → 指派 Copilot Coding Agent「修」並開 PR
      → Copilot Code Review「審」→ Security Gate 擋門 → 你「決定」merge
```

免費掃描器負責找（不花 AI Credits），Copilot 負責修與審，你負責決定。

> 🔴 **「修」這一格有兩道關卡還沒開通**（2026-08-01 實測）：
>
> 1. **Copilot 開的 PR，其 CI/Security run 卡在 `action_required`** → required check 永遠不回報
>    → **那個 PR 永遠 merge 不了**，除非有人手動按 Approve and run。這條要先解。
> 2. Actions 貼的 `@copilot` 留言喚不醒 Agent（GitHub 的 bot 防迴圈限制）→ 只能人工開 Issue 起頭。
>
> Agent 本身是好的（指派 Issue → 立刻開 PR ✅），Code Review 也正常 ✅。
> **導入時請把「修」當成手動一步**，排查步驟見 [已知限制](docs/KNOWN-LIMITATIONS.md)。

> **Copilot 不會 approve PR。** Copilot Code Review 送出的是 COMMENT 類型的 review，
> 它只留意見，不會（也不能）按 Approve。所以最後那個「決定 merge」一定是人，
> 而分支保護的 required approvals 若設成 1，Copilot 是**湊不出**那一票的（見[分支保護](#分支保護讓流程非過不可)）。

---

## 5 分鐘導入一個新專案

### 前置檢查

| 項目 | 要求 |
|---|---|
| 語言 | Python 開箱即用（ruff + pytest）。非 Python 設 `run-python: false` 即可，見[常見情境](#專案不是-python) |
| 本 repo 可見性 | 目前是 **public**，任何 repo 都能呼叫。若哪天改回 private，要到 Settings → Actions → General → Access 選 **Accessible from repositories in the organization** |
| 目標 repo 權限 | 你要有 admin（才能設分支保護）；沒有的話第 5 步得請 owner 做 |

### 步驟 1 — 複製呼叫端範本

**一鍵版（推薦）** —— 會自動偵測技術棧並把參數填好，跨 macOS / Windows：

```bash
cd /path/to/your-project

/path/to/ci-standards/scripts/adopt.sh              # macOS / Linux / Git Bash
```
```powershell
powershell -ExecutionPolicy Bypass -File C:\path\to\ci-standards\scripts\adopt.ps1   # Windows
```

先加 `--dry-run` / `-DryRun` 看它偵測到什麼，確認無誤再真的跑。
**只需要 `git`，不需要 `gh`**；內網、離線、Proxy 的做法見 [`docs/ADOPT.md`](docs/ADOPT.md)。

用了一鍵版的話，**步驟 2 的 ① ② 可以跳過**（腳本已經填好），只剩 ③ 要自己改。

<details>
<summary>手動版</summary>

```bash
cp -R /path/to/ci-standards/templates/consumer-repo/.github .
```

</details>

複製過去的東西：

| 檔案 | 作用 | 要不要改 |
|---|---|---|
| `workflows/security.yml` | 呼叫安全公版 | ✅ 改 `uses:` 與 `with:` |
| `workflows/ci.yml` | 呼叫 CI 公版 | ✅ 改 `uses:` |
| `workflows/copilot-setup-steps.yml` | Copilot Coding Agent 動工前的環境準備 | 依專案相依調整 |
| `workflows/copilot-autofix-ci-security.yml` | CI/Security 失敗 → 自動 @copilot 修，含重試上限與升級 | 不用改（需 Copilot Business） |
| `workflows/copilot-autofix-review.yml` | Copilot review 要求變更 → 自動 @copilot 依意見修 | 不用改（需 Copilot Business） |
| `workflows/copilot-autoreview-gate.yml` | CI+Security 全過 → 自動請 Copilot 審 + 觸發 coding agent | 不用改（需 Copilot Business） |
| `dependabot.yml` | pip / docker / actions 每週自動更新 | 有前端再加 npm 區塊 |
| `copilot-instructions.md` | Copilot 修碼與審查時的專案規範 | ⚠️ **一定要改**，前四段是待填的佔位符 |
| `pull_request_template.md` | PR 檢查清單（含安全項） | 通常不用改 |

> 三支 `copilot-auto*` workflow 是**選配的自動化閉環**，沒有 Copilot Business 也能複製過去（只是不會動）。細節見[下方說明](#自動修復閉環選配需-copilot-business)。

### 步驟 2 — 改三個地方

**① `security.yml` 的 `uses:` 與參數**

```yaml
jobs:
  security:                                   # ← job id 是 security，會影響 check 名稱
    uses: singi0771/ci-standards/.github/workflows/security-reusable.yml@v1
    with:
      python-version: "3.12"
      severity: "CRITICAL,HIGH"
      fail-on-findings: true
      scan-docker-image: false   # 有 Dockerfile 才改 true（會多吃 2–3 分鐘）
      upload-sarif: false        # 保持 false，見「已知限制」
```

**② `ci.yml` 的 `uses:`**

```yaml
jobs:
  ci:                                         # ← job id 是 ci
    uses: singi0771/ci-standards/.github/workflows/ci-reusable.yml@v1
    with:
      python-version: "3.12"
      run-docker-build: true     # 沒 Dockerfile 設 false
```

> ⚠️ **job id（`security` / `ci`）不要亂改**。分支保護的 check 名稱是 `<job id> / <公版 job 名>`，改了名稱 ruleset 就對不上。

**③ `copilot-instructions.md`**
把「專案概觀 / 技術棧 / 進入點 / 開發測試指令」四段換成這個專案的實況。Copilot 修碼會照著跑測試，寫錯它就修不動。

### 步驟 3 — 推上去

```bash
git add .github && git commit -m "Adopt org CI/security standard" && git push
```

### 步驟 4 — 看第一次跑的結果

```bash
gh run list -L 5
```

第一次一定會有東西紅 —— 那是掃描器真的找到問題（多半是相依 CVE 或誤判）。
先看是誤判還是真弱點，處理方式見[疑難排解](#疑難排解)。**不要為了讓它變綠就關掉檢查。**

### 步驟 5 — 開分支保護

等第一次 workflow 跑完（check 名稱要先存在於 GitHub），再執行：

```bash
./scripts/setup-branch-protection.sh <owner>/<repo>
```

這會建立 ruleset：必須開 PR + 對話解決 + 通過 `Security Gate` 與 `CI Gate` + 禁止 force push / 刪分支。
⚠️ 有方案限制、以及 required approvals 預設為何是 0，見[下一節](#分支保護讓流程非過不可)。

> 三支 `copilot-auto*` 的觸發器（`workflow_run` / `pull_request_review`）依 GitHub 規則
> **只認 default branch 上的檔案**。所以「導入這件事」本身的那個 PR 不會有自動修/自動審，
> 要等合併進 `main` 之後的下一個 PR 才會生效 —— 不是壞掉。

---

## 導入後，日常怎麼用

### 一般開發

```bash
git checkout -b feat/xxx        # 不要直接改 main
# ...寫碼...
git push -u origin feat/xxx
gh pr create
```

開 PR 後自動發生：CI（ruff + pytest + docker build）→ 四項安全掃描 → Security Gate 彙總 → Copilot Code Review（若已啟用）。
全綠才能 merge。Gate 紅的話點進 Actions 看是哪一項掛掉。

### 掃描結果去哪看

- **Actions → 該 run → Summary**：Security Gate 會印一張表，一眼看出哪項掛掉
- **Artifact `semgrep-sarif`**：Semgrep 完整結果（`upload-sarif: false` 時走這裡）
- `upload-sarif: true` 時才會進 Security 分頁（需 public repo 或 GHAS）

### 掃到弱點 → 交給 Copilot 修

> ✅ **這條路已實測可用**（2026-08-01）。目前不能用的是「CI 紅了自動 @copilot」那條，
> 見[已知限制](docs/KNOWN-LIMITATIONS.md)。所以「修」這一步要由人開 Issue 起頭。

1. 依掃描結果開 Issue，把弱點檔案、行號、掃描器訊息貼進去
2. Issue 右側 Assignees **指派給 Copilot**
3. Copilot 先跑 `copilot-setup-steps.yml` 準備環境 → 修碼 → 跑測試 → 開 PR
4. PR 一樣要過 Security Gate；你 review 後 merge

> 用量提醒：Coding Agent 與 Code Review 都會扣 AI Credits（1,900/人/月）+ Actions 分鐘。先從小型、明確的 Issue 開始。

### 每週會自動發生

- **週一 03:00 UTC**：完整重掃（`schedule` 觸發），抓「程式碼沒動但新公布的 CVE」
- **Dependabot 每週**：pip / docker / github-actions 更新 PR，小版本會併成一個 PR

### 公版更新了怎麼辦

什麼都不用做。`uses: ...@v1` 且 `v1` tag 已移動 → 你下次跑 CI 就吃到新版。

---

## 自動修復閉環（選配，需 Copilot Business）

範本裡三支 `copilot-auto*` workflow 讓「修 + 審」完全自動化。**不裝 Copilot Business 也能複製過去，只是不會動**；有的話會形成這個循環：

> **架構**：這三支 consumer 端只是**十幾行的薄殼**（觸發器 + 一行 `uses:`），所有邏輯放在公版的三支 `*-reusable.yml`。改邏輯只要動公版、移 `v1`，**各專案下次觸發就反應式同步**，跟 ci/security 一樣不必逐一改。詳見[為什麼薄殼](#為什麼是薄殼而非整包複製)。

```
             ┌──────────────────────────────────────────────────┐
             ▼                                                    │
  你開 PR ─▶ CI + Security ──失敗──▶ copilot-autofix-ci-security ──▶ @copilot 修 ─┐
             │                        （最多 3 次，超過就升級人工）              │
             │全過                                                              │
             ▼                                                                  │
     copilot-autoreview-gate ──▶ 請 Copilot 審 + 觸發 coding agent ─────────────┘
             │                    （每個 PR 最多 3 次；Copilot 修完 commit
             │                      → 新 SHA 全綠 → 再審，這條迴圈靠上限收斂）
             │
      真人 reviewer 按 Request changes ──▶ copilot-autofix-review ──▶ @copilot 依意見修
             │                              （最多 3 次）
             ▼
        你看完 Copilot 的意見，決定 Merge
```

> **注意這裡沒有「Copilot approve」這一格。** Copilot 只會留 COMMENT，不會 approve。
> `copilot-autofix-review` 那條路徑吃的是 `changes_requested`，實務上**只有真人 reviewer 會觸發**——
> 這是刻意的：autoreview 貼的留言已經要求 Copilot「發現問題直接修正後 commit」，
> 若再接上 Copilot 自己的 COMMENT review，兩支 workflow 會互相觸發成無窮迴圈。

| consumer 薄殼 | 顯示名 | 呼叫的公版 | 觸發時機 → 做什麼 |
|---|---|---|---|
| `copilot-autofix-ci-security.yml` | Copilot Autofix — CI/Security | `copilot-autofix-reusable.yml` | CI/Security 失敗 → 找 PR → `@copilot` 貼失敗 job 與 log，要求直接修碼 |
| `copilot-autofix-review.yml` | Copilot Autofix — Review | `copilot-autofix-review-reusable.yml` | **真人** review `changes_requested` → `@copilot` 依意見修碼 |
| `copilot-autoreview-gate.yml` | Copilot Auto Review | `copilot-autoreview-reusable.yml` | CI/Security 完成 → 確認**兩條**都對同一 SHA 通過 → 請 Copilot 審 + 觸發 coding agent |

**內建的安全閥（避免無限燒 Credits）：**

- **修正次數上限**：`max-attempts`（預設 3），用 PR 留言裡的隱藏 marker 計數；達上限改貼 `needs-human-review` label 升級人工，不再自動修。
- **審查次數上限**：`max-review-requests`（預設 3）。Copilot 依意見 commit → 新 SHA → CI/Security 又全綠 → 又請審，**這條迴圈本身沒有終點**，靠這個上限收斂。
- **升級後閉嘴**：升級人工的留言帶 `<!-- *-escalated -->` marker，之後同一 PR 不再自動留言。想重啟自動修正就把那則留言刪掉。
- **Cooldown**：`copilot-autofix-ci-security` 對同一 commit 15 分鐘內只觸發一次（CI 與 Security 常在數秒內相繼失敗，避免重複）。
- **同 SHA 去重 + 排隊**：`copilot-autoreview-gate` 用 `concurrency` 把同一 SHA 的兩次呼叫排隊（CI 與 Security 幾乎同時完成時，兩邊會同時判定「該請審了」），後到的那次看到 marker 就跳過。
- **跳過 Dependabot**：Dependabot PR 不進 autofix，**也不進 autoreview**（每週 5 個 PR 各燒一次 review + agent 是純浪費）。
- **雙綠才放行**：`copilot-autoreview-gate` 會確認 CI 與 Security **都**對同一 SHA 成功才動作，不會只過一半就請審。

### 為什麼是薄殼而非整包複製

這三支的**觸發器**（`workflow_run` / `pull_request_review`）依 GitHub 規則**必須存在於 consumer repo 的 default branch**，無法純靠 `uses:` 繼承。但「觸發器要在本地」不代表「邏輯也要在本地」——

- consumer 端只留**薄殼**：本地觸發器 + 一行 `uses: ...copilot-*-reusable.yml@v1`，把事件參數（PR、SHA、run-id…）當 `with:` 傳進去。
- **所有 bash 邏輯集中在公版的 `*-reusable.yml`**。改邏輯（新升級規則、未來的測試覆蓋率門檻、資安擴充）只要動公版、移 `v1` → 各專案下次觸發自動吃到，**不必逐一改 repo**。
- 薄殼本身只有在 **input 契約改變**時才需要重新複製，頻率極低。

> 要調重試次數，在薄殼的 `with:` 加 `max-attempts: "5"` 即可，不必改公版。

---

## 可調參數（inputs）

### `security-reusable.yml`

| 參數 | 型別 | 預設 | 說明 |
|---|---|---|---|
| `python-version` | string | `3.12` | 掃描環境的 Python 版本 |
| `severity` | string | `CRITICAL,HIGH` | Trivy 要擋下的嚴重度。可加 `MEDIUM` 收更嚴 |
| `fail-on-findings` | boolean | `true` | `true`=掃到就擋 merge；`false`=只回報不擋（**導入初期過渡用**） |
| `scan-docker-image` | boolean | `false` | build 出 image 再掃 CVE。**有 Dockerfile 才開**，會多吃 2–3 分鐘 |
| `upload-sarif` | boolean | `false` | 上傳到 Security 分頁。僅 public repo 或有 GHAS 可用。⚠️ **這條路徑尚未實測成功，請先維持 `false`** —— 詳見[已知限制](docs/KNOWN-LIMITATIONS.md#upload-sarif-true-尚未驗證可用) |

### `ci-reusable.yml`

| 參數 | 型別 | 預設 | 說明 |
|---|---|---|---|
| `python-version` | string | `3.12` | CI 的 Python 版本 |
| `run-python` | boolean | `true` | 是否跑 ruff + pytest。**非 Python 專案設 `false`**，不必自己另寫一支 CI |
| `run-docker-build` | boolean | `true` | 驗證 image 能 build（不推送）。沒 Dockerfile 就設 `false` |
| `run-actionlint` | boolean | `false` | 檢查 GitHub Actions workflow 語法。actionlint 的 image 內建 shellcheck，會連 `run:` 區塊的 bash 一起檢查 |
| `actionlint-paths` | string | `""` | 額外要檢查的 workflow 檔 glob。空字串＝只檢查 `.github/workflows`。⚠️ actionlint 一旦收到檔案參數就「只」檢查那些檔案，所以公版是**分兩次**跑（預設路徑一次、額外路徑一次） |
| `run-shellcheck` | boolean | `false` | 用 shellcheck 檢查 shell script（runner 內建，不必安裝） |
| `shellcheck-paths` | string | `""` | 要檢查的 `.sh` glob。空字串＝自動找全 repo（找不到就略過） |
| `ruff-version` | string | `0.16.0` | **釘死**的 ruff 版本。不釘的話新版 ruff 會憑空多出規則、讓沒改碼的 repo 突然變紅；要升級 lint 規則在此改一版、統一生效 |

> **`run-*` 全部關掉也不會卡住**：四個子 job 都可能因 input 而 `skipped`，CI Gate 只在 `failure` / `cancelled` 才擋。
>
> **lint 穩定性**：consumer 的 ruff 規則由**自己的 `pyproject.toml`**（`[tool.ruff.lint] select/ignore`）決定，公版只負責釘死 ruff 執行檔版本。兩者搭配才能讓 `ruff check` 結果可重現、不隨上游漂移。

**「這個 repo 沒有 Python，主要內容是 workflow 與 script」的設定範例**（本 repo 自己就是這樣跑的，見 `.github/workflows/ci.yml`）：

```yaml
jobs:
  ci:
    uses: singi0771/ci-standards/.github/workflows/ci-reusable.yml@v1
    with:
      run-python: false
      run-docker-build: false
      run-actionlint: true
      run-shellcheck: true
```

---

## 分支保護：讓流程「非過不可」

### ⚠️ 方案限制（一定先確認）

**private repo 的 ruleset / branch protection 需要 GitHub Pro 以上方案。**
免費個人帳號的 private repo 呼叫 API 會直接被擋：

```
403 Upgrade to GitHub Pro or make this repository public to enable this feature.
```

三個解法：把 repo 轉到有 Team 方案的 org（推薦，順便統一管 Copilot policy）／帳號升 Pro／repo 轉 public（多數情況不適合）。

### ⚠️ required approvals 為什麼預設是 0

腳本預設 `required_approving_review_count: 0`，這是刻意的。設 1 而團隊只有你一個人時，**PR 會永遠 merge 不了**，三件事疊在一起：

1. GitHub 不允許 PR 作者 approve 自己的 PR
2. Copilot Code Review 送的是 COMMENT 類型 review，**它不會 approve**
3. ruleset 預設沒有 `bypass_actors`，連 org admin 都繞不過（跟舊版 classic branch protection 不同）

設 0 **不代表沒有守門**——「必須開 PR」和「必須通過 Security Gate / CI Gate」照樣強制，只是不強制人工按 Approve。等有第二位固定 reviewer 再改：

```bash
REQUIRED_APPROVALS=1 ./scripts/setup-branch-protection.sh <owner>/<repo>
```

### 一鍵設定

```bash
gh auth login                                        # 需有目標 repo 的 admin
./scripts/setup-branch-protection.sh <owner>/<repo>
```

腳本可重複執行：偵測到同名 ruleset 會改用 `PUT` 更新，不會建出第二份。

### 手動設定

目標 repo → Settings → Rules → Rulesets → New branch ruleset → 針對 `main`：

- ✅ **Enforcement status** 設為 **Active**（預設是 Disabled，很容易漏）
- ✅ **Require a pull request before merging**（approvals 先填 0、勾要求對話解決）
- ✅ **Require status checks to pass**，加入：
  - `security / Security Gate`
  - `ci / CI Gate`
- ✅ **Block force pushes** / **Restrict deletions**

> check 名稱格式是 `<呼叫端 job id> / <公版 job 名>`。若你改過 job id，這裡要跟著改。
> 名稱必須跟 Checks 分頁上實際出現的字串**完全一致**，所以務必等第一次 run 跑完再設。

> **只設這兩個 Gate，不要把個別 job 加進去。** `docker-build` 和 `trivy-image` 有 `if` 條件，
> 關掉時會變 `skipped`，而 skipped 的 required check 永遠不回報 → PR 永久 pending。

### ⚠️ 開之前先確認呼叫端沒有 paths-ignore

`ci.yml` / `security.yml` 的 **`pull_request` 區塊不可以有 `paths-ignore`**。
被 path filter 擋掉的 PR 根本不會啟動 workflow，required check 就永遠是 pending —— 一個只改 README 的 PR
會直接卡死，而且沒有 bypass 可以繞。範本已經拿掉了，但如果你手上是舊版複製過去的，導入前務必檢查。

（`push: main` 那邊保留 `paths-ignore` 沒問題，那不影響 required check。）

### 另外要做的兩件事

- **Copilot 政策**：Org → Settings → Copilot → Policies，開啟 **Copilot code review** 與 **Copilot coding agent**
- **防止爆帳單**：Settings → Billing → Spending limit，Actions 設 **$0**

這兩項是組織層級的一次性設定，細節見 [`docs/SETUP.md`](docs/SETUP.md)。

> 本 repo 目前在個人帳號底下。**private repo 的 ruleset 需要 Pro 以上方案**，
> 而組織可以用「一條 org ruleset 管所有 repo」，不必逐個跑腳本。
> 建議在導入第 3 個專案之前搬到組織，見 [`docs/MIGRATION-TO-ORG.md`](docs/MIGRATION-TO-ORG.md)。

---

## 常見情境客製

### 專案不是 Python

`security-reusable.yml` 是語言無關的（Semgrep / Trivy / gitleaks / OSV 都自己認語言），**照用即可**。

`ci-reusable.yml` 也**照用**，只要把 Python 那段關掉：

```yaml
with:
  run-python: false        # 不跑 ruff / pytest
  run-docker-build: true   # 有 Dockerfile 就留著
  run-actionlint: true     # workflow 語法 + run: 區塊的 bash
  run-shellcheck: true     # shell script
```

這樣仍然會產出 `ci / CI Gate` 這個 check，分支保護的 ruleset 不必為了語言不同而各寫一套。

**還需要語言原生的 lint / test（Node 的 eslint + jest、Go 的 go vet + go test…）時**，目前公版還沒有對應的 reusable。兩條路：

1. 在該專案自己加一支 `ci-lang.yml`，**用不同的 job id**（例如 `node`），再把 `node / <job 名>` 一起加進 ruleset 的 required checks。
2. 到本 repo 開 Issue 提需求，補一支 `ci-node-reusable.yml`（見 [CONTRIBUTING](CONTRIBUTING.md)）。

> 走第 1 條時**不要**把 `ci.yml` 的 job id 也改掉 —— `ci / CI Gate` 是所有專案共用的 check 名稱，改了 ruleset 就要逐一客製，公版的意義就沒了。

### 沒有 Dockerfile

`security.yml` 設 `scan-docker-image: false`、`ci.yml` 設 `run-docker-build: false`。
（公版有 `if [ -f Dockerfile ]` 保護，不設也不會爆，但會浪費 runner 時間。）

### 導入初期紅到不想活

先設 `fail-on-findings: false` 讓它只回報不擋 → 分批清乾淨 → 再改回 `true` 並開分支保護。
**不要**直接刪掉 workflow。

### 抑制誤判

在專案根目錄放對應的 ignore 檔（公版會自動吃到）：

| 掃描器 | 檔案 | 寫法 |
|---|---|---|
| Semgrep | `.semgrepignore` | 一行一個路徑 glob |
| gitleaks | `.gitleaksignore` | 一行一個 `commit:path:rule:line` fingerprint（失敗訊息裡會印） |
| Trivy | `.trivyignore` | 一行一個 CVE / GHSA ID |

> 每一條 ignore 都應該在 PR 說明「為什麼這是誤判」。要抑制的是誤判，不是真弱點。

---

## 疑難排解

| 症狀 | 原因 | 解法 |
|---|---|---|
| `workflow was not found` / `not allowed` | 本 repo 是 private 且沒開組織存取 | Settings → Actions → General → Access → Accessible from repositories in the organization |
| PR 上找不到 `security / Security Gate` 這個 check | 還沒跑過第一次，或 job id 被改過 | 先讓 workflow 跑完一次，再回 ruleset 設定 |
| `pytest` 失敗但專案根本沒測試 | pytest 沒收到測試會回 exit code 5 | 加一支最小 smoke test，或在 `pyproject.toml` 設定 pytest 選項 |
| OSV-Scanner 紅、其他都綠 | 相依套件有已知 CVE | 看 log 的套件名 → 升版（Dependabot PR 通常已經開好了） |
| gitleaks 抓到已經撤銷的舊 token | 密鑰留在 git 歷史裡 | **先去平台撤銷金鑰**，再把 fingerprint 加進 `.gitleaksignore` |
| Trivy 一堆 MEDIUM 擋門 | `severity` 設太寬 | 收斂成 `CRITICAL,HIGH` |
| `upload-sarif: true` 報權限錯誤 | 公版預設不要求 `security-events: write` | 呼叫端 job 自行加 `permissions:`，且 repo 要有 GHAS 或為 public |
| Actions 分鐘燒很快 | image 掃描 + Semgrep 多規則很吃時間 | 關掉 `scan-docker-image`、或把 schedule 從每週改每月 |

---

## 版本策略

每次發佈都要打**兩個** tag：一個不可變的版本號、一個會移動的別名。

```bash
git tag -a v1.2.0 -m "..." && git push origin v1.2.0   # 不可變：出事時的回滾點
git tag -f v1 && git push -f origin v1                 # 會移動的別名：所有專案自動跟進
```

| 情況 | 做法 |
|---|---|
| 修 bug、加掃描規則、升 action 版本、**新增有預設值的 input** | 打 `v1.x.y` + 移動 `v1` |
| 改 input 名稱 / 移除 input / 改 job 名稱 | 打 `v2.0.0` + 開 `v2`，公告後各專案自行改 `@v1` → `@v2` |
| 想吃最新未打 tag 的版本 | 呼叫端寫 `@main`（不建議用在正式專案） |

> ⚠️ **改完公版一定要移動 `v1`**，否則指向 `@v1` 的專案完全不會有感覺 —— main 領先 `v1` 好幾個 commit 卻沒人發現，是這套機制最容易出的事故。
>
> ⚠️ **只有會移動的 `v1` 是不夠的**。`v1` 移壞了就沒有「昨天的 v1」可退，所以每次都要留一個不可變的 `v1.x.y`。回滾＝把 `v1` 指回上一個版本號。

發佈過哪些版本、每版改了什麼，記在 [CHANGELOG.md](CHANGELOG.md)。

---

## 檔案地圖

```
ci-standards/
├── README.md                          ← 本文件
├── CHANGELOG.md                       ← 發佈過哪些版本、每版改了什麼
├── CONTRIBUTING.md                    ← 要改公版 / 要提需求的人看這裡
├── SECURITY.md                        ← 弱點回報管道
├── LICENSE
│
├── .github/                           ← ⚠️ 這裡有兩種東西，別搞混
│   ├── workflows/
│   │   │  ── ① 公版本體（給別人 uses: 呼叫的）──
│   │   ├── security-reusable.yml          ← 安全公版（Semgrep+OSV+Trivy+gitleaks+Security Gate）
│   │   ├── ci-reusable.yml                ← CI 公版（Python + Docker + actionlint + shellcheck）
│   │   ├── copilot-autofix-reusable.yml        ← Copilot 自動修（CI/Security 失敗）邏輯
│   │   ├── copilot-autofix-review-reusable.yml ← Copilot 自動修（依 review 意見）邏輯
│   │   ├── copilot-autoreview-reusable.yml     ← Copilot 自動審（雙綠請審 + 觸發 agent）邏輯
│   │   │
│   │   │  ── ② 本 repo 自己的呼叫端（dogfooding，用 ./ 呼叫上面那些）──
│   │   ├── ci.yml                         ← 自己跑 actionlint + shellcheck
│   │   ├── security.yml                   ← 自己跑四項安全掃描
│   │   ├── copilot-autofix-ci-security.yml
│   │   ├── copilot-autofix-review.yml
│   │   └── copilot-autoreview-gate.yml
│   ├── copilot-instructions.md        ← 本 repo 自己的 Copilot 規範
│   ├── pull_request_template.md       ← 本 repo 自己的 PR 檢查清單
│   ├── CODEOWNERS
│   └── dependabot.yml                 ← 本 repo 只有 github-actions 相依
│
├── .gitattributes                     ← 強制 LF 簽出；沒有它 Windows 會踩到 CRLF 的坑
├── scripts/
│   ├── adopt.sh                       ← 一鍵導入（macOS / Linux / Git Bash）
│   ├── adopt.ps1                      ← 一鍵導入（Windows PowerShell 5.1，零安裝）
│   └── setup-branch-protection.sh     ← 一鍵建立分支保護 ruleset（需要 gh）
├── docs/
│   ├── ADOPT.md                       ← 一鍵導入的跨平台說明、內網/離線做法、要不要 gh
│   ├── SETUP.md                       ← 管理者用：公版發佈、Copilot 啟用、方案/額度
│   ├── KNOWN-LIMITATIONS.md           ← ⚠️ 實測過但「還不能用」的東西，導入前必看
│   ├── MIGRATION-TO-ORG.md            ← 把本 repo 搬到組織底下的 checklist
│   └── DEVSECOPS-NOTES.md             ← 為什麼不用 SonarQube/ZAP、工具取捨與導入順序
└── templates/consumer-repo/.github/   ← 各專案要複製過去的「呼叫端」範本
    ├── dependabot.yml
    ├── copilot-instructions.md
    ├── pull_request_template.md
    └── workflows/
        ├── security.yml               ← 呼叫安全公版
        ├── ci.yml                     ← 呼叫 CI 公版
        ├── copilot-setup-steps.yml        ← Copilot agent 環境準備
        ├── copilot-autofix-ci-security.yml ← 選配：CI/Security 失敗 → 自動 @copilot 修
        ├── copilot-autofix-review.yml     ← 選配：review 要求變更 → 自動 @copilot 修
        └── copilot-autoreview-gate.yml    ← 選配：全過 → 自動請 Copilot 審
```

---

## 這套涵蓋什麼、不涵蓋什麼

**涵蓋**（Shift-left / 開發階段）

| 面向 | 工具 |
|---|---|
| 程式碼弱點 SAST | Semgrep（OWASP Top 10 + security-audit + secrets） |
| 相依套件 CVE | OSV-Scanner + Dependabot |
| 檔案系統 / IaC / Dockerfile 設定 | Trivy（vuln + misconfig + secret） |
| 密鑰外洩 | gitleaks（含 git 歷史） |
| Container image CVE | Trivy image（可選） |
| 程式碼品質 | ruff + pytest |

**不涵蓋**：WAF、EDR、SIEM、CSPM、runtime 偵測、滲透測試、DAST（ZAP）、SBOM 簽章。
把它當「把明顯的炸彈擋在 main 之外」的第一道防線，很稱職；但它不是完整資安防護。

### 為什麼私有 repo 也能免費跑

- 不上傳到需付費的 Security 分頁（code scanning），改用「**job 成敗當守門員 + artifact**」
- gitleaks 用 **docker 執行檔**跑，避開 `gitleaks-action` 對組織帳號的 license 要求
- 用 **OSV-Scanner** 取代需要 GHAS 的 dependency-review-action
- 全部工具皆開源免費，只消耗 GitHub Actions 分鐘

更多取捨理由（含為什麼不建議把 SonarQube Community 當 PR gate）見 [`docs/DEVSECOPS-NOTES.md`](docs/DEVSECOPS-NOTES.md)。

---

## 延伸閱讀

| 文件 | 給誰看 |
|---|---|
| [`docs/ADOPT.md`](docs/ADOPT.md) | 一鍵導入 —— Windows / macOS、內網與離線做法、`gh` 是不是必要 |
| [`docs/KNOWN-LIMITATIONS.md`](docs/KNOWN-LIMITATIONS.md) | **導入前必看** —— 實測過但還不能用的功能，含排查步驟 |
| [`docs/SETUP.md`](docs/SETUP.md) | 管理者 —— 公版發佈、Copilot 啟用、方案與額度 |
| [`docs/MIGRATION-TO-ORG.md`](docs/MIGRATION-TO-ORG.md) | 管理者 —— 搬到組織底下的 checklist |
| [`docs/DEVSECOPS-NOTES.md`](docs/DEVSECOPS-NOTES.md) | 想知道工具怎麼選的人 |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | 要改公版、要提需求的人 |
| [`CHANGELOG.md`](CHANGELOG.md) | 想知道 `v1` 現在是什麼的人 |
| [`SECURITY.md`](SECURITY.md) | 要回報弱點的人 |
