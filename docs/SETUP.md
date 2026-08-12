# 平台設定指南（管理者用）

> **導入流程不在這裡。** 要把公版導入一個新專案，請看 [README](../README.md#5-分鐘導入一個新專案) —— 那是開發者每次導入都要照做的操作手冊。
>
> 這份文件講的是**一次性的帳號 / 組織 / 方案層級設定**：公版怎麼發佈、Copilot 兩個 Agent 怎麼開、分支保護的方案前提、額度怎麼控。設定完通常就不用再回來。

| 我要做的事 | 看哪裡 |
|---|---|
| 把公版導入新專案 | [README — 5 分鐘導入](../README.md#5-分鐘導入一個新專案) |
| 查參數怎麼設 | [README — 可調參數](../README.md#可調參數inputs) |
| CI 紅了怎麼辦 | [README — 疑難排解](../README.md#疑難排解) |
| 發佈 / 更新公版 | [§A](#a-公版維護者發佈與更新) 本文 |
| 開 Copilot 自動修 / 自動審 | [§B](#b-啟用-copilot-兩個-agent) 本文 |
| 分支保護開不起來 | [§C](#c-分支保護的方案前提) 本文 |
| 控制花費 | [§D](#d-額度與帳務) 本文 |
| 某個功能實測不會動 | [KNOWN-LIMITATIONS.md](KNOWN-LIMITATIONS.md) |
| 把公版搬到組織底下 | [MIGRATION-TO-ORG.md](MIGRATION-TO-ORG.md) |
| 改公版的流程與自我檢查 | [CONTRIBUTING.md](../CONTRIBUTING.md) |

---

## A. 公版維護者：發佈與更新

> 只有**維護 ci-standards 這個 repo 的人**要做。使用者不用。

### 首次發佈

```bash
git push origin main
git tag v1 && git push origin v1
```

### 可見性與存取權

本 repo 目前是 **public** —— 任何 repo 都能 `uses:` 呼叫它，不需額外設定，且 public repo 自己跑 Actions 不計費。

若日後改為 **private**，必須另外開放組織內呼叫，否則其他 repo 會收到 `workflow was not found`：

> Settings → Actions → General → **Access** → `Accessible from repositories in the organization`

### 改完公版之後

⚠️ **一定要移動 tag，否則所有專案完全不會有感覺**（大家都指向 `@v1`）。

每次發佈打**兩個** tag：不可變的版本號（回滾點）+ 會移動的別名（大家指向的）。

```bash
git tag -a v1.2.0 -m "說明" && git push origin v1.2.0   # 不可變
git tag -f v1 && git push -f origin v1                  # 移動別名
git tag -a v2.0.0 -m "..." && git tag v2 && git push origin v2.0.0 v2   # 破壞性變更
```

並在 [CHANGELOG.md](../CHANGELOG.md) 補上這一版。判斷標準見 [README — 版本策略](../README.md#版本策略)。

> 🔴 **這是這套機制最容易出的事故**：改動合進 `main`，但忘了移 `v1`，
> 於是 `main` 領先 `v1` 好幾個 commit 而沒有人發現 —— 新導入的專案拿到的其實是舊版，
> 包含你以為早就修掉的 bug。**定期檢查**：
>
> ```bash
> git log --oneline "$(git rev-list -n1 v1)"..origin/main   # 應該是空的
> ```

### 改動公版的自我檢查

- [ ] 有沒有改到 input 名稱或 job 名稱？（會打壞既有 repo 的 ruleset → 該開 v2）
- [ ] 新增的 job 有沒有加進 `security-gate` / `ci-gate` 的 `needs`？（沒加＝這個檢查不會擋門，形同虛設）
- [ ] 新 action 有沒有釘版本？（不要用 `@master` / `@main`，供應鏈風險）
- [ ] 新 **container image** 有沒有釘版本？（`semgrep/semgrep`、`ghcr.io/gitleaks/gitleaks` 都用 `:latest`
      的話，沒改碼的 repo 會隨上游新規則突然變紅，也是供應鏈風險）
- [ ] 有 `if` 條件的新 job **不要**設成 required check（skipped 的 check 永遠不回報 → PR 卡死），
      只把它加進 gate 的 `needs`，由 gate 判斷 skipped 算過
- [ ] 掃描工具「執行失敗」有沒有被當成「通過」？（下載用 `curl --fail` + 跑前先驗 `--version`）
- [ ] 先在一個專案用 `@main` 試跑過，再移動 `v1`

---

## B. 啟用 Copilot 兩個 Agent

需要 **Copilot Business** 以上。兩者都是**選配** —— 不開，掃描與 Gate 照常運作，只是弱點要自己修。

### Copilot Code Review（自動審 PR）

1. Org → Settings → Copilot → Policies → 開啟 **Copilot code review**
2. Copilot 審查時會讀專案的 `.github/copilot-instructions.md`
3. ⚠️ **不要**再另外開「每個 PR 自動要求 Copilot review」—— 理由見下一節

### ⚠️ 只留一個 review 觸發源

Copilot 會來審 PR 有**兩個**可能的來源，同時開著會互相打架：

| 來源 | 何時觸發 | 設定位置 |
|---|---|---|
| **GitHub 原生自動 review** | **PR 一開就審**（CI 還沒跑） | repo/org 設定或 ruleset 的「Require Copilot code review」 |
| **本公版的 `copilot-autoreview-gate.yml`** | **雙 Gate 全綠之後**才請審，且跳過 Dependabot | 複製範本即有 |

**兩個都開的話會發生什麼**（2026-08-09 PR #15 的真實案例）：

```
12:14  Dependabot 開 PR（單純 SHA bump，1 檔 +2/-2）
12:14  原生自動 review 立刻觸發 —— CI 一秒都還沒跑
12:22  Copilot 送出 review，本文自陳「unable to run its full agentic suite」
       → 降級模式下只看到 diff 兩行，提出了一個結論錯誤的建議
12:27  依該建議修改 → 公版被改出一個回歸
15:04  CI 這時才跑完（而且是綠的）
```

原生那條**違反這套設計的核心順序**：先讓免費掃描器擋掉明顯問題，
確定值得看了才花 AI credits 請 Copilot 審。在 CI 之前就審，等於：

- 對「反正會被 CI 擋掉」的 PR 白花 credits
- 審的是**即將被改掉**的程式碼
- 連 Dependabot 的純版本更新也審（公版的 gate 刻意跳過這類）

**建議設定：關掉原生自動 review，只留 gate 驅動的那條。**

1. Repo → Settings → **Code review**（或 org → Copilot → Policies）→
   關閉「automatically request Copilot review on new pull requests」
2. 若是用 **ruleset** 開的：Settings → Rules → Rulesets → 編輯該 ruleset →
   取消 **Require Copilot code review**
3. 驗證：開一個測試 PR，確認 **CI 跑完之前不會出現 Copilot 的 review**，
   雙 Gate 綠了之後才由 `copilot-autoreview-gate` 貼出請審留言

> 想手動請 Copilot 審某個 PR 隨時可以（PR 頁面 Reviewers → Copilot）。
> 關掉的只是「每個 PR 都自動審」。

### Review thread 一律要求 resolve（保持開啟）

`setup-branch-protection.sh` 建立的 ruleset 含 `required_review_thread_resolution: true` ——
**建議維持開啟**，即使它代表每個有 review 的 PR 都要人按一次 Resolve。

理由就在上面那個案例：Copilot 那則意見**結論是錯的，但它指出的邊界情況是真的存在**。
如果為了省一次點擊而關掉、或寫自動化去 auto-resolve，你會同時失去
「發現真問題」和「發現假問題」的能力 —— 而假問題的成本是回一則留言，
真問題的成本是公版帶著一個洞被所有專案吃下去。

**該優化的是觸發頻率（上一節），不是把關卡拿掉。**
關掉原生自動 review 之後，需要 resolve 的 thread 自然大幅減少：
Dependabot 的版本更新不再產生 review，而通過雙 Gate 才被審的 PR，
本來就值得人看一眼。

### Copilot Coding Agent（把 Issue 變 PR）

1. Org → Settings → Copilot → Policies → 確認 **Copilot coding agent** 已啟用
2. 開 Issue → 右側 Assignees **指派給 Copilot**
3. Copilot 先跑該 repo 的 `copilot-setup-steps.yml` 準備環境，再修碼、跑測試、開 PR

### ✅ 1.2.0 起：`@copilot` 改由 `COPILOT_TRIGGER_PAT` 發出，Agent 會動了

自動觸發那條線已修復 —— mention 改用**有 Copilot 授權之使用者的 fine-grained PAT**
以真人身分發出，不再受 bot 防迴圈限制。**每個要啟用迴圈的 repo 都要設定一次**：

1. 有 Copilot 授權的帳號 → Settings → Developer settings →
   Fine-grained personal access tokens → Generate new token
2. Repository access **只勾該 repo**；權限 **Issues: Read and write** +
   **Pull requests: Read and write**，其餘不給；效期照公司政策（到期要換）
3. 該 repo → Settings → Secrets and variables → Actions → New repository secret，
   名稱 `COPILOT_TRIGGER_PAT`
4. 驗收：開一個測試 PR 讓 Copilot 審出意見，確認 `@copilot` 留言的**作者是那個真人帳號**
   且 Agent 有動工。若留言作者仍是 `github-actions[bot]`，代表 secret 沒傳到（檢查薄殼
   的 `secrets:` 區塊）；run log 會有 `::warning::` 提示。

> 仍存在的人工關卡：Copilot 推的 commit 觸發的 run 要人按一次「Approve and run workflows」
> （或人推空 commit 繞過），見
> [KNOWN-LIMITATIONS](KNOWN-LIMITATIONS.md#copilot-觸發的-workflow-run-會卡在-action_required)。

以下為 1.1.0 時代的歷史紀錄（定位過程），保留供排查參考：

### 🟡 歷史：Agent 可用，但 Actions 貼的 `@copilot` 喚不醒它（1.2.0 已修復）

三支 `copilot-auto*` 的核心動作，是用 `GITHUB_TOKEN` 在 PR 貼一則 `@copilot ...` 留言，
作者是 `github-actions[bot]`。**這個前提沒有成立**：

| 觀察項 | 結果 |
|---|---|
| Gate 擋門、cooldown 去重、autoreview 去重 | ✅ 全部正常（4 個觸發事件只產生 2 則留言） |
| Copilot **Code Review**（自動審） | ✅ 會動 |
| Copilot **Coding Agent** — 指派 Issue（官方入口） | ✅ 會動，立刻開出 PR |
| Copilot **Coding Agent** — Actions 貼的 `@copilot` 留言 | ❌ 等 12 分鐘無反應 |

也就是說：**引擎是好的，卡住的是自動觸發那條線**（GitHub 對「bot 觸發 bot」的防迴圈限制）。

**完整結果、排查三關、以及解法，見
[KNOWN-LIMITATIONS.md](KNOWN-LIMITATIONS.md#copilot-coding-agent-對-actions-貼的-copilot-沒有反應)。**

> **導入新專案時，第 1 關要重測一次。** 方案是帳號層級的，但 Copilot policy 與
> `copilot-setup-steps.yml` 是 repo 層級的 —— 這個 repo 過了不代表下一個 repo 也過。
> 測法：開一個小 Issue，Assignees 指派給 Copilot，看它會不會開 PR。

> **在自動觸發修好之前照常導入，只是「修」要手動起頭。**
> 完整可用的路徑是「掃描擋門 → Copilot 自動審 → 開 Issue 指派 Copilot 修 → 人 merge」。
> 三支 `copilot-auto*` 複製過去不會有害（沒反應而已，也不燒 credits），
> 但**不要拿它們當導入成功的驗收標準**。

### 讓 Copilot 真的修得動的關鍵

`copilot-instructions.md` 與 `copilot-setup-steps.yml` **必須反映該專案的實況**。
範本裡的開發指令若沒改成專案自己的，Copilot 會照著錯的指令跑、測不起來，產出的 PR 品質會很差。這是導入後最常見的失敗原因。

實際用法（怎麼把掃描結果變成 Issue 丟給 Copilot）見 [README — 掃到弱點交給 Copilot 修](../README.md#掃到弱點--交給-copilot-修)。

---

## C. 分支保護的方案前提

操作步驟在 [README — 分支保護](../README.md#分支保護讓流程非過不可)。這裡只講**開不起來時**的決策。

### private repo 需要 Pro 以上方案

免費個人帳號的 private repo，呼叫 ruleset API 會直接被擋：

```
403 Upgrade to GitHub Pro or make this repository public to enable this feature.
```

| 方案 | 適用 | 代價 |
|---|---|---|
| **轉移到 Team 方案的 org**（推薦） | 團隊專案 | 需 org owner 操作；好處是 Copilot policy、billing、權限一起統一管 |
| 帳號升級 GitHub Pro | 個人專案、想最小改動 | 約 $4/月 |
| repo 轉 public | 本來就要開源的專案 | 內容全公開，多數內部工具不適用 |

### 另一個常見卡點：你不是該 repo 的 admin

`setup-branch-protection.sh` 需要 admin 權限。可先確認：

```bash
gh api repos/<owner>/<repo> --jq .permissions
```

`"admin": false` 就要請 repo owner 執行，或請他把你升為 admin。

---

## D. 額度與帳務

### 先關掉超額付費

Settings → Billing → **Spending limit** → Actions 設為 **$0**。
這樣用完免費額度就是停跑，不會產生帳單。

### 額度怎麼被吃掉

| 項目 | 免費額度 | 備註 |
|---|---|---|
| Actions 分鐘（private repo） | 每月 3,000 分鐘（Team） | **public repo 不計費**，所以 ci-standards 自己不吃額度 |
| AI Credits | 1,900 / 人 / 月 | Coding Agent 與 Code Review 都會扣 |

### 省額度的旋鈕

- `scan-docker-image: false` —— image 掃描每次多吃 2–3 分鐘
- schedule 從每週改每月（改呼叫端 `security.yml` 的 cron）
- caller 的 **`push: main`** 有 `paths-ignore: ["**/*.md", "docs/**"]`，直接推文件到 main 不會觸發掃描
  （**`pull_request` 刻意不加** —— 加了會讓純文件 PR 的 required check 永遠 pending、PR 卡死）
- caller 已設 `concurrency` + `cancel-in-progress`，連續 push 會自動取消舊 run

---

## E. 每月檢視清單

- [ ] **`v1` 有沒有落後 `main`**（`git log --oneline "$(git rev-list -n1 v1)"..origin/main` 應為空）
      —— 落後代表所有專案吃的都還是舊版，這是最容易發生也最容易漏掉的事故
- [ ] 各 repo Actions run 是否有長期紅著沒人理的（尤其每週排程的 Security Scan —— 它會抓「程式碼沒動但新公布的 CVE」）
- [ ] Dependabot PR 有沒有積著沒 merge
- [ ] Org → Billing：AI Credits 與 Actions 分鐘用量
- [ ] 各專案 `.gitleaksignore` / `.semgrepignore` / `.trivyignore` 有沒有被濫用來蓋掉真弱點
- [ ] 公版的 action 版本是否該升（Dependabot 也會幫本 repo 開 PR）

---

## 延伸閱讀

- [README](../README.md) —— 導入流程、參數、日常使用、疑難排解
- [KNOWN-LIMITATIONS.md](KNOWN-LIMITATIONS.md) —— 實測過但還不能用的功能，含排查步驟
- [MIGRATION-TO-ORG.md](MIGRATION-TO-ORG.md) —— 把公版搬到組織底下的 checklist
- [CONTRIBUTING.md](../CONTRIBUTING.md) —— 改公版的流程、送 PR 前的自我檢查
- [CHANGELOG.md](../CHANGELOG.md) —— 發佈過哪些版本
- [DEVSECOPS-NOTES.md](DEVSECOPS-NOTES.md) —— 工具取捨理由（為什麼不把 SonarQube Community 當 PR gate、ZAP 為何不進核心 gate）、建議導入順序
