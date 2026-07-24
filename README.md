# ci-standards — 團隊統一 CI / 安全掃描中央公版

這個 repo 是**中央公版**。安全掃描與 CI 的邏輯只寫在這裡一次，所有專案用**一行 `uses:`** 呼叫它。
公版更新 → 移動 tag → 各專案下次跑 CI 就自動同步，不必逐一改每個 repo。

> 適用環境：私有 repo、免費開源工具，**不需要 GitHub Advanced Security**。搭配 Copilot Business 可再啟用「自動修 + 自動審」閉環。

---

## 目錄

1. [運作原理（先看這個）](#運作原理先看這個)
2. [5 分鐘導入一個新專案](#5-分鐘導入一個新專案)
3. [導入後，日常怎麼用](#導入後日常怎麼用)
4. [可調參數（inputs）](#可調參數inputs)
5. [分支保護：讓流程「非過不可」](#分支保護讓流程非過不可)
6. [常見情境客製](#常見情境客製)
7. [疑難排解](#疑難排解)
8. [版本策略](#版本策略)
9. [檔案地圖](#檔案地圖)
10. [這套涵蓋什麼、不涵蓋什麼](#這套涵蓋什麼不涵蓋什麼)

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
   jobs.ci:                                ├─ Python lint + test
     uses: ...@v1                          └─ Docker build check
```

**呼叫端只有十幾行、沒有邏輯**。要改掃描規則、加工具、升版本 —— 全部改這個 repo，不動任何專案。

### 為什麼有 Security Gate

`Security Gate` 是一個 `needs` 全部掃描的彙總 job：任一掃描失敗它就失敗。
所以**分支保護只要求它這一個 check**，日後你在公版增減掃描工具，不必回頭改每個 repo 的 ruleset。

### 完整閉環（有 Copilot Business 時）

```
免費掃描器「找」弱點 → 開 Issue → 指派 Copilot Coding Agent「修」並開 PR
      → Copilot Code Review「審」→ Security Gate 擋門 → 你「決定」merge
```

免費掃描器負責找（不花 AI Credits），Copilot 負責修與審，你負責決定。

---

## 5 分鐘導入一個新專案

### 前置檢查

| 項目 | 要求 |
|---|---|
| 語言 | Python（`ci-reusable.yml` 跑 ruff + pytest）。非 Python 見[常見情境](#專案不是-python) |
| 本 repo 可見性 | 目前是 **public**，任何 repo 都能呼叫。若哪天改回 private，要到 Settings → Actions → General → Access 選 **Accessible from repositories in the organization** |
| 目標 repo 權限 | 你要有 admin（才能設分支保護）；沒有的話第 5 步得請 owner 做 |

### 步驟 1 — 複製呼叫端範本

在**目標專案根目錄**執行：

```bash
cp -R /path/to/ci-standards/templates/consumer-repo/.github .
```

複製過去的東西：

| 檔案 | 作用 | 要不要改 |
|---|---|---|
| `workflows/security.yml` | 呼叫安全公版 | ✅ 改 `uses:` 與 `with:` |
| `workflows/ci.yml` | 呼叫 CI 公版 | ✅ 改 `uses:` |
| `workflows/copilot-setup-steps.yml` | Copilot Coding Agent 動工前的環境準備 | 依專案相依調整 |
| `dependabot.yml` | pip / docker / actions 每週自動更新 | 有前端再加 npm 區塊 |
| `copilot-instructions.md` | Copilot 修碼與審查時的專案規範 | ⚠️ **一定要改**，範本目前寫死 AdminAutoTools |
| `pull_request_template.md` | PR 檢查清單（含安全項） | 通常不用改 |

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
      scan-docker-image: true    # 有 Dockerfile 才開
      upload-sarif: false        # private 且無 GHAS → 保持 false
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

這會建立 ruleset：必須開 PR + 至少 1 approve + 對話解決 + 通過 `Security Gate` 與 CI + 禁止 force push / 刪分支。
⚠️ 有方案限制，見[下一節](#分支保護讓流程非過不可)。

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

## 可調參數（inputs）

### `security-reusable.yml`

| 參數 | 型別 | 預設 | 說明 |
|---|---|---|---|
| `python-version` | string | `3.12` | 掃描環境的 Python 版本 |
| `severity` | string | `CRITICAL,HIGH` | Trivy 要擋下的嚴重度。可加 `MEDIUM` 收更嚴 |
| `fail-on-findings` | boolean | `true` | `true`=掃到就擋 merge；`false`=只回報不擋（**導入初期過渡用**） |
| `scan-docker-image` | boolean | `false` | build 出 image 再掃 CVE。**有 Dockerfile 才開**，會多吃 2–3 分鐘 |
| `upload-sarif` | boolean | `false` | 上傳到 Security 分頁。僅 public repo 或有 GHAS 可用；開啟時呼叫端 job 要自行加 `permissions: security-events: write` |

### `ci-reusable.yml`

| 參數 | 型別 | 預設 | 說明 |
|---|---|---|---|
| `python-version` | string | `3.12` | CI 的 Python 版本 |
| `run-docker-build` | boolean | `true` | 驗證 image 能 build（不推送）。沒 Dockerfile 就設 `false` |

---

## 分支保護：讓流程「非過不可」

### ⚠️ 方案限制（一定先確認）

**private repo 的 ruleset / branch protection 需要 GitHub Pro 以上方案。**
免費個人帳號的 private repo 呼叫 API 會直接被擋：

```
403 Upgrade to GitHub Pro or make this repository public to enable this feature.
```

三個解法：把 repo 轉到有 Team 方案的 org（推薦，順便統一管 Copilot policy）／帳號升 Pro／repo 轉 public（多數情況不適合）。

### 一鍵設定

```bash
gh auth login                                        # 需有目標 repo 的 admin
./scripts/setup-branch-protection.sh <owner>/<repo>
```

### 手動設定

目標 repo → Settings → Rules → Rulesets → 針對 `main`：

- ✅ **Require a pull request before merging**（至少 1 approve、要求對話解決）
- ✅ **Require status checks to pass**，加入：
  - `security / Security Gate` ← **必要，只要這一個**
  - `ci / Python lint + test` ← 建議
- ✅ **Block force pushes** / 禁止刪除分支

> check 名稱格式是 `<呼叫端 job id> / <公版 job 名>`。若你改過 job id，這裡要跟著改。
> 名稱必須跟 Checks 分頁上實際出現的字串**完全一致**，所以務必等第一次 run 跑完再設。

### 另外要做的兩件事

- **Copilot 政策**：Org → Settings → Copilot → Policies，開啟 **Copilot code review** 與 **Copilot coding agent**
- **防止爆帳單**：Settings → Billing → Spending limit，Actions 設 **$0**

這兩項是組織層級的一次性設定，細節見 [`docs/SETUP.md`](docs/SETUP.md)。

---

## 常見情境客製

### 專案不是 Python

`security-reusable.yml` 是語言無關的（Semgrep / Trivy / gitleaks / OSV 都自己認語言），**可以照用**。
`ci-reusable.yml` 寫死 ruff + pytest，非 Python 專案就**別複製 `ci.yml`**，自己寫一支；或提個需求到本 repo，加一支 `ci-node-reusable.yml`。

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

```bash
git tag -f v1 && git push -f origin v1   # 小修：移動 v1，所有專案自動跟進
git tag v2 && git push origin v2         # 破壞性變更：開新 tag，各專案自行升級
```

| 情況 | 做法 |
|---|---|
| 修 bug、加掃描規則、升 action 版本 | 移動 `v1` |
| 改 input 名稱 / 移除 input / 改 job 名稱 | 開 `v2`，公告後各專案自行改 `@v1` → `@v2` |
| 想吃最新未打 tag 的版本 | 呼叫端寫 `@main`（不建議用在正式專案） |

> ⚠️ **改完公版一定要移動 tag**，否則指向 `@v1` 的專案完全不會有感覺。

---

## 檔案地圖

```
ci-standards/
├── README.md                          ← 本文件
├── .github/workflows/
│   ├── security-reusable.yml          ← 安全公版（Semgrep+OSV+Trivy+gitleaks+Security Gate）
│   └── ci-reusable.yml                ← CI 公版（Python lint/test + Docker build）
├── scripts/
│   └── setup-branch-protection.sh     ← 一鍵建立分支保護 ruleset
├── docs/
│   ├── SETUP.md                       ← 管理者用：公版發佈、Copilot 啟用、方案/額度
│   └── DEVSECOPS-NOTES.md             ← 為什麼不用 SonarQube/ZAP、工具取捨與導入順序
└── templates/consumer-repo/.github/   ← 各專案要複製過去的「呼叫端」範本
    ├── dependabot.yml
    ├── copilot-instructions.md
    ├── pull_request_template.md
    └── workflows/{security,ci,copilot-setup-steps}.yml
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
