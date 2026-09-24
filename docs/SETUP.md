# 平台設定指南（管理者用）

> **導入流程不在這裡。** 要把公版導入一個新專案，請看 [README](../README.md#5-分鐘導入一個新專案) —— 那是開發者每次導入都要照做的操作手冊。
>
> 這份文件講的是**一次性的帳號 / 組織 / 方案層級設定**：公版怎麼發佈、分支保護的方案前提、額度怎麼控。設定完通常就不用再回來。

| 我要做的事 | 看哪裡 |
|---|---|
| 把公版導入新專案 | [README — 5 分鐘導入](../README.md#5-分鐘導入一個新專案) |
| 查參數怎麼設 | [README — 可調參數](../README.md#可調參數inputs) |
| CI 紅了怎麼辦 | [README — 疑難排解](../README.md#疑難排解) |
| 發佈 / 更新公版 | [§A](#a-公版維護者發佈與更新) 本文 |
| 分支保護開不起來 | [§B](#b-分支保護的方案前提) 本文 |
| 控制花費 | [§C](#c-額度與帳務) 本文 |
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

每次發佈打**兩個** tag：不可變的版本號（還原點）+ 會移動的別名（大家指向的）。

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
- [ ] 新增的 job 有沒有加進 `security-gate` / `ci-gate` 的 `needs`？（沒加＝這個檢查不會擋 PR，形同虛設）
- [ ] 新 action 有沒有釘 commit SHA？（不要用 `@master` / `@main`，供應鏈風險）
- [ ] 新 **container image** 有沒有釘 tag + digest？（`:latest` 的話沒改程式的 repo 會隨上游新規則突然變紅，
      只釘 tag 的話上游重推同一個 tag 你不會知道）
- [ ] 新下載的**執行檔**有沒有釘版本 + sha256？（升版時校驗碼要跟著換，見 CONTRIBUTING.md §6）
- [ ] 有 `if` 條件的新 job **不要**設成 required check（被跳過時 GitHub 要嘛當通過、要嘛一直 pending），
      只把它加進 gate 的 `needs`，由 gate 判斷「開了就必須 success」
- [ ] 掃描工具「執行失敗」有沒有被當成「通過」？（下載用 `curl --fail` + `sha256sum -c` + 跑前先驗 `--version`）
- [ ] 跑不到 30 秒的新檢查有沒有併進既有 job？（每個 job 不滿一分鐘也算一分鐘）
- [ ] 先在一個專案用 `@main` 試跑過，再移動 `v1`

---

## B. 分支保護的方案前提

操作步驟在 [README — 分支保護](../README.md#分支保護讓流程非過不可)。這裡只講**開不起來時**的決策。

### private repo 需要 Pro 以上方案

免費個人帳號的 private repo，呼叫 ruleset API 會直接被擋：

```
403 Upgrade to GitHub Pro or make this repository public to enable this feature.
```

| 方案 | 適用 | 代價 |
|---|---|---|
| **轉移到 Team 方案的 org**（推薦） | 團隊專案 | 需 org owner 操作；好處是 billing、權限、ruleset 一起統一管 |
| 帳號升級 GitHub Pro | 個人專案、想最小改動 | 約 $4/月 |
| repo 轉 public | 本來就要開源的專案 | 內容全公開，多數內部工具不適用 |

### 另一個常見卡點：你不是該 repo 的 admin

`setup-branch-protection.sh` 需要 admin 權限。可先確認：

```bash
gh api repos/<owner>/<repo> --jq .permissions
```

`"admin": false` 就要請 repo owner 執行，或請他把你升為 admin。

---

## C. 額度與帳務

### 先關掉超額付費

Settings → Billing → **Spending limit** → Actions 設為 **$0**。
這樣用完免費額度就是停跑，不會產生帳單。

### 額度怎麼被吃掉

| 項目 | 免費額度 | 備註 |
|---|---|---|
| Actions 分鐘（private repo） | 每月 3,000 分鐘（Team） | **public repo 不計費**，所以 ci-standards 自己不吃額度 |

### 省額度的做法

計費規則只有一條要記：**每個 job 不滿一分鐘也算一分鐘**，macOS runner 算 10 倍、Windows 算 2 倍。

- `scan-docker-image: false` —— image 掃描每次多吃 2–3 分鐘；沒 Dockerfile 一定關
- schedule 從每週改每月（改呼叫端 `security.yml` 的 cron，例如 `"0 3 1 * *"`）
- 呼叫端的 **`push: main`** 有 `paths-ignore: ["**/*.md", "docs/**"]`，直接推文件到 main 不會觸發掃描
  （**`pull_request` 刻意不加** —— 加了會讓純文件 PR 的 required check 永遠 pending、PR 卡死）
- 呼叫端已設 `concurrency` + `cancel-in-progress`，連續 push 會自動取消舊 run
- 還在寫的 PR 開成**草稿**：1.3.0 的範本呼叫端遇到草稿整個跳過，按 Ready for review 才跑
- Dependabot 的 docker / github-actions 改每月（1.3.0 範本預設）；每個 Dependabot PR 都會跑整套
- 1.3.0 公版自己已經把 actionlint + shellcheck 合成一個 job、hadolint 併進 Docker build
  —— 這些不用你設定，移了 `v1` 就生效

完整清單見 [README — 省 Actions 分鐘](../README.md#省-actions-分鐘這套怎麼省你還能怎麼省)。

---

## D. 每月檢視清單

- [ ] **`v1` 有沒有落後 `main`**（`git log --oneline "$(git rev-list -n1 v1)"..origin/main` 應為空）
      —— 落後代表所有專案吃的都還是舊版，這是最容易發生也最容易漏掉的事故
- [ ] 各 repo Actions run 是否有長期紅著沒人理的（尤其每週排程的 Security Scan —— 它會抓「程式碼沒動但新公布的 CVE」）
- [ ] Dependabot PR 有沒有積著沒 merge
- [ ] Org → Billing：Actions 分鐘用量
- [ ] 各專案 `.gitleaksignore` / `.semgrepignore` / `.trivyignore` / `.github/zizmor.yml` 有沒有被濫用來蓋掉真弱點
- [ ] 公版的 action 版本是否該升（Dependabot 每月會幫本 repo 開 PR）
- [ ] 人工釘死的掃描器版本是否該升（OSV-Scanner、zizmor、actionlint、hadolint、Semgrep / gitleaks 的 image
      —— Dependabot 不會動這些，步驟見 CONTRIBUTING.md §6）

---

## 延伸閱讀

- [README](../README.md) —— 導入流程、參數、日常使用、疑難排解
- [KNOWN-LIMITATIONS.md](KNOWN-LIMITATIONS.md) —— 實測過但還不能用的功能，含查問題的步驟
- [MIGRATION-TO-ORG.md](MIGRATION-TO-ORG.md) —— 把公版搬到組織底下的 checklist
- [CONTRIBUTING.md](../CONTRIBUTING.md) —— 改公版的流程、送 PR 前的自我檢查
- [CHANGELOG.md](../CHANGELOG.md) —— 發佈過哪些版本
- [DEVSECOPS-NOTES.md](DEVSECOPS-NOTES.md) —— 工具取捨理由（為什麼不把 SonarQube Community 當 PR gate、ZAP 為何不進核心 gate）、建議導入順序
