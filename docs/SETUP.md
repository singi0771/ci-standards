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

```bash
git tag -f v1 && git push -f origin v1   # 小修：所有專案下次跑 CI 自動跟進
git tag v2 && git push origin v2         # 破壞性變更：開新 tag 並公告
```

判斷標準見 [README — 版本策略](../README.md#版本策略)。

### 改動公版的自我檢查

- [ ] 有沒有改到 input 名稱或 job 名稱？（會打壞既有 repo 的 ruleset → 該開 v2）
- [ ] 新增的 job 有沒有加進 `security-gate` 的 `needs`？（沒加＝這個掃描不會擋門，形同虛設）
- [ ] 新 action 有沒有釘版本？（不要用 `@master` / `@main`，供應鏈風險）
- [ ] 先在一個專案用 `@main` 試跑過，再移動 `v1`

---

## B. 啟用 Copilot 兩個 Agent

需要 **Copilot Business** 以上。兩者都是**選配** —— 不開，掃描與 Gate 照常運作，只是弱點要自己修。

### Copilot Code Review（自動審 PR）

1. Org → Settings → Copilot → Policies → 開啟 **Copilot code review**
2. 在 repo 或 ruleset 設定「自動要求 Copilot review」，讓每個 PR 自動被審
3. Copilot 審查時會讀專案的 `.github/copilot-instructions.md`

### Copilot Coding Agent（把 Issue 變 PR）

1. Org → Settings → Copilot → Policies → 確認 **Copilot coding agent** 已啟用
2. 開 Issue → 右側 Assignees **指派給 Copilot**
3. Copilot 先跑該 repo 的 `copilot-setup-steps.yml` 準備環境，再修碼、跑測試、開 PR

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
- caller 已設 `paths-ignore: ["**/*.md", "docs/**"]`，改文件不會觸發掃描
- caller 已設 `concurrency` + `cancel-in-progress`，連續 push 會自動取消舊 run

---

## E. 每月檢視清單

- [ ] 各 repo Actions run 是否有長期紅著沒人理的（尤其每週排程的 Security Scan —— 它會抓「程式碼沒動但新公布的 CVE」）
- [ ] Dependabot PR 有沒有積著沒 merge
- [ ] Org → Billing：AI Credits 與 Actions 分鐘用量
- [ ] 各專案 `.gitleaksignore` / `.semgrepignore` / `.trivyignore` 有沒有被濫用來蓋掉真弱點
- [ ] 公版的 action 版本是否該升（Dependabot 也會幫本 repo 開 PR）

---

## 延伸閱讀

- [README](../README.md) —— 導入流程、參數、日常使用、疑難排解
- [DEVSECOPS-NOTES.md](DEVSECOPS-NOTES.md) —— 工具取捨理由（為什麼不把 SonarQube Community 當 PR gate、ZAP 為何不進核心 gate）、建議導入順序
