# 交接：現況與待辦

> **最後更新**：2026-08-13　**已發佈版本 1.2.3**（發佈基準 `6fed71b`，`v1` 指向它）
> **2026-08-13 起是「兩台機器並存」** —— Windows 成為主要開發機（1.2.3 在那裡發佈），
> macOS 那台仍在服役（跑 llmstack／geearning／MLX server），同日搬出了 OneDrive。
> §4 整節改寫過。作廢的**只有 OneDrive 底下的舊 macOS 路徑**，不是 macOS 本身。
>
> 這裡刻意寫**發佈基準**而不是「`main` 現在是哪個 commit」——
> 後者連這份文件自己被合併都會讓它過期（已經發生過好幾次）。
> `main` 通常會領先發佈基準若干個純文件 commit，那是正常的。
>
> 這是一份**活的**文件。每次做完一段工作就更新「現況快照」與「待辦」，
> 讓下一個接手的人（或下一個 Claude session）不必重新推導。
> 歷史細節請看 `CHANGELOG.md`，這裡只寫**現在是什麼狀態、下一步做什麼**。
>
> ⚠️ **開始動手前先驗一次快照**（`git log --oneline -1`、
> `git ls-remote --tags origin | grep -E 'refs/tags/v1($|\.)'`）。
> 這份文件可能是幾天前寫的 —— 照著過期的快照做，最糟的情況是重複
> force-push `v1`。**實際狀態永遠以指令輸出為準，不是以這份文件為準。**

---

## 0. 給接手的 AI：先讀這些

你沒有前一個 session 的對話記憶，但這個 repo 本身就是記憶。按這個順序讀，
大約十分鐘就能有完整脈絡：

| 順序 | 檔案 | 讀它是為了知道 |
|---|---|---|
| 1 | 本檔（`docs/HANDOFF.md`） | 現在卡在哪、下一步做什麼 |
| 2 | `README.md` | 這個公版是什麼、有哪些 input、版本策略 |
| 3 | `CHANGELOG.md` 的 1.1.0 / 1.2.0 / 1.2.1 / 1.2.2 / 1.2.3 五段 | **每一版都在修「上一版以為修好、其實沒有」的東西**，這五段是全部的教訓來源 |
| 4 | `docs/KNOWN-LIMITATIONS.md` | 哪些問題已知無解，別再花時間 |
| 5 | `CONTRIBUTING.md` | 改公版的規矩（尤其「什麼情況要開 v2」） |
| 6 | `docs/ADOPT.md` | 導入腳本的三類檔案策略 |

再跑一次 `git log --oneline -20` 與 `gh pr list --state merged --limit 10`
（或用瀏覽器看 PR #8～#18），commit message 與 PR 內文寫得很細，是主要的決策紀錄。

**不要只讀本檔就開始改公版。** 這個 repo 踩過的坑幾乎都不直觀
（見 §5），沒讀過 CHANGELOG 很容易重蹈覆轍。

---

## 1. 這個 repo 是什麼

`singi0771/ci-standards` 是**中央公版**：一組 reusable workflow，各專案用一行
`uses: singi0771/ci-standards/.github/workflows/xxx.yml@v1` 呼叫。
改公版一次、**把 `v1` 移到新的 commit**，所有專案下次觸發就同步 ——
這是它存在的全部理由。

⚠️ **合併進 `main` 不等於發佈。** 消費端釘的是 `@v1`，`v1` 沒移動的話，
改再多它們完全不會有感覺。發佈永遠是兩步：合併 → 移 tag（見 §3 的發佈流程）。

三條主線：

1. **CI**（`ci-reusable.yml`）：Python lint/test、Docker build、actionlint、shellcheck
2. **Security**（`security-reusable.yml`）：Semgrep、Trivy、OSV-Scanner、gitleaks
3. **Copilot 自動迴圈**：CI/Security 失敗 → 請 Copilot 修；兩條都過 → 請 Copilot 審；
   審有意見 → 再請 Copilot 修

**CI 與 Security 各有一個 Gate job**（`ci / CI Gate`、`security / Security Gate`），
那兩個才是唯一該設為 required status check 的東西。
Copilot 那三支沒有 Gate，**也絕不能設成 required** —— 它們有 `if` 條件，
被 skip 的 check 永遠不會回報，PR 會直接卡死。

---

## 2. 現況快照

| 項目 | 狀態 |
|---|---|
| 發佈基準 | `6fed71b`（1.2.3）。`main` 會領先這個點若干個**純文件** commit，屬正常 —— 要確認請跑 `git log --oneline -1` |
| CHANGELOG | 已定版到 **1.2.3** |
| `v1` tag | ✅ 已移到 `6fed71b`（1.2.3 已發佈，各專案下次觸發就會吃到） |
| 最新版本 tag | ✅ `v1.2.3`（`v1.2.3^{}` → `6fed71b`，已驗證與 `v1` 同一 SHA） |
| 公版自己的 CI | ✅ 全綠（dogfooding，用 `uses: ./` 跑自己的 reusable） |
| 開發機 | **兩台並存**（2026-08-13 起）：Windows 為主（`D:\3_CodingProject`，1.2.3 在此發佈）；macOS 仍在服役且已搬出 OneDrive。詳見 §4 |
| AdminAutoTools | ✅ **已升到 1.2.1 契約**，且 `@main` → `@v1` 與缺 `issues: write` 都已修（**AdminAutoTools#65 已合併**，見 §3 ⑥）。`COPILOT_TRIGGER_PAT` 已於 2026-08-09 設定 |
| AdminAutoTools 的 CI | 🔴 **2026-08-13 中午起全面停擺**（所有 job `steps=0`，疑似 Actions 配額／spending limit）。**這是目前最該先解的一條**，詳見 §3 |
| adopt.sh | ✅ 43 項回歸測試在 **Linux／macOS／Windows(Git Bash) 三個平台都跑過** |
| adopt.ps1 | ✅ **1.2.3 起首次在真 Windows 上驗過**：PS 5.1 與 pwsh 7 都能跑，產出與 `adopt.sh` byte-identical。⚠️ 但**沒有任何自動測試在守它**（見 §3 ⑦） |

### 1.2.1 修了什麼（為什麼 AdminAutoTools 一定要重跑 adopt）

1.2.0 修好了 Copilot 自動修迴圈，改的是三支 `copilot-*` 薄殼的 **`if:` 條件**與
**`secrets:` 區塊**。但當時的 `adopt.sh` 升級模式是「就地合併」，而**就地合併只碰 `with:`**。

結果：舊 consumer 升級後拿到新的 `uses:`、卻留著舊的 `if:` 和缺席的 `secrets:` ——
**版本號變了，迴圈還是壞的**。1.2.1 就是修這個：三支薄殼改成整份換新。

所以對 AdminAutoTools 來說，**光移 `v1` tag 沒有用**，壞的是它本地那三支薄殼。
必須重跑一次 `adopt.sh`。

---

## 3. 待辦（依序）

> **1.2.3 已發佈完成**（`v1` 與 `v1.2.3^{}` 都在 `6fed71b`，已用 `git ls-remote` 驗過）。
> 發佈的操作步驟見本節最後的「發佈流程」，下次公版有實質變更時照那個走。
>
> **① ② ③ ⑥ 都已完成**（劃掉保留，是為了留住「為什麼」與驗收方式）。
> **現在的第一順位是「AdminAutoTools 的 Actions 停擺」**（本節中段，紅字那條）——
> 在它解決之前，那個 repo 的 CI 與 Copilot 迴圈都是死的，其他事做了也驗不到。
> 之後才是 ⑦（給 `adopt.ps1` 加自動守門）與 ④（GitHub 網頁設定）。

### ~~① 用 AdminAutoTools 測 adopt~~ ✅ 已完成（2026-08-13 查證）

AdminAutoTools 在 `D:\3_CodingProject\AdminAutoTools\AdminAutoTools\`
（**巢狀結構**，外層資料夾包著真正的 clone）。

三支薄殼已經是 1.2.1 契約，驗收條件全數滿足：

```bash
cd /d/3_CodingProject/AdminAutoTools/AdminAutoTools
for m in commented review-id review-state copilot-trigger-pat max-attempts; do
  grep -q -- "$m" .github/workflows/copilot-autofix-review.yml && echo "OK $m" || echo "MISSING $m"
done
```

### ~~② AdminAutoTools 設 repo secret~~ ✅ 已完成

`COPILOT_TRIGGER_PAT` 已於 2026-08-09 設定（`gh secret list --repo cecigehlpj/AdminAutoTools` 可驗）。

> 留著這段說明，因為**下一個 consumer 導入時還是會漏**：
> 沒設的話 CI 會全綠，但 Copilot 自動修迴圈不會動工，而且沒有明顯錯誤 ——
> `@copilot` mention 必須由真人帳號發出，`github-actions[bot]` 發的會被
> coding agent 忽略（GitHub 的防 bot 迴圈機制）。
> 權限：fine-grained PAT，Issues: write + Pull requests: write，範圍限該 repo。

### ~~③ 驗 adopt.ps1（Windows）~~ ✅ 已完成（1.2.3，2026-08-13）

移轉到 Windows 之後做的第一件事，**當場抓到一個致命 bug**：
`adopt.ps1` 在 Windows PowerShell 5.1 上**連 parse 都過不了**（19 個 parser
error），而那正是它 `#Requires -Version 5.1` 宣稱支援、主打「受管制公司環境
不必裝 pwsh」的目標環境。根因是檔案沒有 UTF-8 BOM，5.1 改用 ANSI codepage
（繁中 = cp950）解讀，中文全變亂碼。1.2.3 加上 BOM 修掉。

驗過的項目：

| 項目 | 結果 |
|---|---|
| `powershell.exe` 5.1 parse | 修正前 **19 errors** → 修正後 **0** |
| `pwsh` 7.6.3 parse | 0（修正前後皆是） |
| 實跑 install 模式（Python + Docker + shell 偵測） | 5.1 與 7 皆 exit 0 |
| **與 `adopt.sh` 的產出比對** | **byte-identical**（`diff -r` 無差異） |
| 產出 YAML 編碼 | UTF-8 無 BOM + LF ✅ |
| 1.2.1 的 `SetCurrentDirectory()` 修正 | ✅ 從別的工作目錄呼叫，`.github\` 正確落在 `-Target`，公版自身未被污染 |

重跑方式：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\adopt.ps1 -Target "某個測試專案" -Std . -DryRun
```

### ⑦ 給 adopt.ps1 加自動守門（1.2.3 留下的缺口）

**BOM 是看不見的，編輯器一次「另存新檔」就可能弄掉，而現在沒有任何東西在守。**
`adopt-tests.yml` 只測 `adopt.sh`，沒有一步會在 5.1 上 parse `adopt.ps1`。

最小成本的作法：在 `adopt-tests.yml` 的 `windows-latest` job 加一步

```yaml
- name: adopt.ps1 必須能被 PowerShell 5.1 parse
  shell: powershell        # 注意：powershell 是 5.1，pwsh 才是 7
  run: |
    $e = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
      "$env:GITHUB_WORKSPACE\scripts\adopt.ps1", [ref]$null, [ref]$e) | Out-Null
    if ($e.Count) { $e | ForEach-Object { Write-Host $_.Message }; exit 1 }
```

⚠️ 一定要用 `shell: powershell`（5.1），用 `pwsh`（7）會永遠是綠的 ——
7 預設就吃 UTF-8，根本不會重現這個問題。**用錯 shell 等於白加。**

### ④ 使用者端設定（GitHub 網頁，非程式）

- [ ] **關掉 GitHub 原生的「自動請 Copilot code review」**。它會在 CI 之前就審，
      違反「先讓免費掃描器擋掉明顯問題、確定值得看了才花 AI credits」的設計順序，
      而且會審 Dependabot 的純版本更新（公版的 gate 刻意跳過那類）。
      只留公版 `copilot-autoreview-gate` 驅動的那條。詳見 `docs/SETUP.md`。
- [ ] 確認 ruleset 的 `required_review_thread_resolution: true`
- [ ] **把 adopt 回歸測試加進本 repo 的 ruleset**（Settings → Rules → 編輯 ruleset →
      Require status checks to pass，加入這兩個 context）：

      adopt regression (ubuntu-latest)
      adopt regression (macos-latest)
      adopt regression (windows-latest)

      現在它們**只會讓 PR 顯示紅燈、不會擋下合併** —— `adopt-tests.yml` 是獨立
      workflow，job 不在 `ci / CI Gate` 底下，而 ruleset 只列了兩個 Gate。
      1.2.2 的整個教訓就是「macOS 這條路徑沒被守住」，補了測試卻沒補守門等於只做一半。

      這三個 job **沒有 `if` 條件、`pull_request` 也沒有 paths 過濾**，每個 PR 必跑，
      所以設成 required 不會造成「skipped 的 check 永不回報 → PR 卡死」。

      ⚠️ **不要加進 `scripts/setup-branch-protection.sh`** —— 那支是給 consumer 用的，
      而 consumer 沒有 `adopt-tests.yml`，列進去就會變成永遠不回報的 required check。
      這是本 repo 專屬的設定，手動加。

### ~~⑥ 把 AdminAutoTools 的三支 copilot 薄殼從 `@main` 改回 `@v1`~~ ✅ 已完成（2026-08-13）

**[`cecigehlpj/AdminAutoTools#65`](https://github.com/cecigehlpj/AdminAutoTools/pull/65) 已合併。**
在 macOS 上用 `adopt.sh --ref v1` 產生，未手動編輯。三件事一起處理掉：

- 三支薄殼的 `uses:` 從 `@main` 改為 `@v1`
- 它順帶打開了 `run-shellcheck`（偵測到專案有 `.sh`），因而第一次檢查到三支既有腳本的
  SC2181／SC3043，**已一併修掉**，否則這個 PR 會把 CI 弄紅
- 補上兩支 autofix 薄殼缺的 `issues: write`（見下）

> ⚠️ **合併時 CI 是紅的，但那不是這個 PR 的問題** —— 見下方「Actions 全面停擺」。
> 變更本身在本機驗過：shellcheck 乾淨、`bash -n`／`sh -n` 通過、六支 workflow YAML 可解析。

### 🔴 AdminAutoTools 的 GitHub Actions 從 2026-08-13 中午起全面停擺

**這是目前最該先解的一條。** 症狀：所有 workflow 的所有 job 都在 3–6 秒內 `failure`，
而 API 顯示 **`steps: []`（job 從未啟動）**——包括 gitleaks、Semgrep 這種不吃相依的。

```bash
gh api repos/cecigehlpj/AdminAutoTools/actions/runs/<id>/jobs \
  --jq '.jobs[] | "\(.conclusion) steps=\(.steps|length) \(.name)"'
```

時間線很乾淨：**06:27 全綠 → 15:22 之後全部 `steps=0`**。

`steps=0` 代表 runner 根本沒接下這個 job，幾乎都是**帳號層級的 Actions 配額或
消費上限**（AdminAutoTools 是 **private** repo，Actions 分鐘要計費；ci-standards 是
public 所以不受影響 —— 同一時間它的 CI 全綠）。

去 GitHub → Settings → Billing → **Actions 用量與 spending limit** 確認。
README 建議把 spending limit 設 $0 以防爆帳單，代價就是**額度用完當天 CI 直接死**，
而且錯誤訊息完全看不出原因。

> 在這條解決之前，AdminAutoTools 的 Copilot 自動迴圈也不會動 —— 它整條都是 Actions 驅動的。

**這次還順帶抓到一個沒人發現的靜默失效**：兩支 autofix 薄殼**缺 `issues: write`**。
達 `max-attempts` 上限時要貼 `needs-human-review` label，而 label API 屬 Issues 權限 ——
少了會 **403 且不報錯**，等於「升級人工」那一步從來沒成功過。1.1.0 就修過公版這個洞
（見 CHANGELOG），但 consumer 的薄殼沒跟上。

原始問題如下（保留，因為下一個 consumer 可能也這樣釘）：

2026-08-13 查到的：AdminAutoTools 的 `ci.yml`／`security.yml` 釘 `@v1`（正確），
但**三支 `copilot-*` 薄殼釘的是 `@main`**：

```
copilot-autofix-reusable.yml@main
copilot-autofix-review-reusable.yml@main
copilot-autoreview-reusable.yml@main
```

這等於**繞過整個發佈閘門** —— `@v1` 存在的理由就是「合併進 main 不等於發佈」，
釘 `@main` 的話任何併進 main 的改動下一次觸發就直接生效，沒有回滾點。

現在剛好沒事（`main` 與 `v1` 只差文件），但**下次動 copilot reusable 就會無預警上線**。
當初大概是為了讓 1.2.0 的迴圈修正快點生效才這樣釘的，那個理由已經消失了。

改法：`adopt.sh` 升級模式會統一把 `uses:` 換成 `--ref` 指定的值，重跑一次即可。

### ⑤ 長期觀察中

- **`action_required`**：Copilot 觸發的 run 會停在待核准，這是 GitHub 對 coding agent
  的安全設計，**沒有開關可調**（別再去調 fork PR 的核准設定，那條路已證實無效，
  兩個佐證寫在 `docs/KNOWN-LIMITATIONS.md`）。
  已決定**觀察兩週**（自 2026-08-11 起），記錄：
  (a) 每週要按幾次 Approve and run　(b) Copilot 開新 PR vs 推既有 PR 的比例。
  數據夠了再決定要不要做自動空 commit 的解法。
- **搬到 GitHub organization**：步驟見 `docs/MIGRATION-TO-ORG.md`。
  搬完各專案要用 `adopt.sh --uses-repo ORG/ci-standards` 換掉 `uses:` 的 owner。

### 發佈流程（公版每次有實質變更就要做一次）

**合併進 `main` 不是發佈。** 消費端釘 `@v1`，`v1` 沒移動 = 沒有任何專案會有感覺。

```bash
cd "$CODE_WORK/ci-standards"
git fetch origin --prune
git checkout main && git pull
git log --oneline -1        # 記下這個 SHA，下面用它

git tag -a vX.Y.Z -m "一句話說明這版改了什麼" <上面那個完整 SHA>
git push origin vX.Y.Z

git tag -f v1 <同一個完整 SHA>
git push -f origin v1

git ls-remote --tags origin | grep -E 'refs/tags/v1($|\.)'
```

**驗收**：最後一行的輸出裡 `refs/tags/v1` 與 `refs/tags/vX.Y.Z^{}` 指向同一個 SHA。
（annotated tag 自己的物件 SHA 不同是正常的，要看 `^{}` 那一行。）

幾個容易出錯的地方：

- **tag 釘死完整 SHA，不要用 HEAD** —— 本機 `main` 若落後，用 HEAD 會打到錯的 commit。
- **`v1` 是會移動的別名**，各專案的 `uses: ...@v1` 在**觸發當下**才解析，沒有 lockfile。
  `vX.Y.Z` 則是不可變的回滾點，出事時各專案可以臨時改釘那個。
- **破壞性變更不能移 `v1`** —— 改 input 名、改 job 名（consumer 的 ruleset 綁著
  `ci / CI Gate`、`security / Security Gate`）都算，那要開 `v2`。判準見 `CONTRIBUTING.md`。
- **純文件變更可以不發版**，等下次有實質變更再一起發。
- **雲端 session 推不了 tag**（policy gateway 對 tag ref 回 403），這一步一律在本機做。

---

## 4. 環境與路徑

> **2026-08-13：現在是「兩台機器並存」，不是單純從 macOS 換到 Windows。**
> 同一天兩件事平行發生 ——
> Windows 那台成為**主要開發機**（1.2.3 就是在那裡發佈的）；
> 而 **macOS 那台同日把專案搬出了 OneDrive**，因為它還在跑服務（見下）。
>
> ⚠️ **只有「OneDrive 底下」的舊 macOS 路徑作廢**
> （`/Users/kimi/Library/CloudStorage/OneDrive-.../CodingProject`）。
> macOS 本身沒有作廢 —— 若看到那串 **OneDrive** 路徑或指向它的 `$CODE_WORK`，
> 那才是過期資訊。

**Windows（主要開發機）**

| 項目 | 值 |
|---|---|
| 開發機 | Windows 11 Enterprise，PowerShell 7 + Git Bash |
| 公司專案根目錄 | `D:\3_CodingProject`（Git Bash：`/d/3_CodingProject`） |
| ci-standards | `D:\3_CodingProject\ci-standards` |
| AdminAutoTools | `D:\3_CodingProject\AdminAutoTools\AdminAutoTools` ← **巢狀** |
| 移轉備份 | `D:\3_CodingProject\_migration_backup_20260813_1115`（含 robocopy log） |

**macOS（仍在服役 —— 它在跑服務，不只是開發機）**

| 項目 | 值 |
|---|---|
| 公司專案根目錄 | `/Users/kimi/CodingProject`　← **已搬出 OneDrive**，`$CODE_WORK` 與 `~/.zshrc` 已同步更新 |
| 個人專案根目錄 | `~/Library/CloudStorage/OneDrive-個人/Kimi/2_Code`（`$CODE_PERS`，仍在 OneDrive） |
| 跑在這台上的服務 | `llmstack`（LiteLLM + open-webui + postgres）、`geearning`（api/dashboard/db）、MLX server（launchd `com.kimi.llmstack.mlx-primary-namecard`，port 18080） |
| Cloudflare Tunnel | `cloudflared-shared`，在 `~/docker-services/cloudflared`，**不在專案樹裡**，搬遷完全不影響它 |

> 搬出 OneDrive 之後，這三個 compose 專案的 bind mount 已全部指向
> `/Users/kimi/CodingProject/...`，容器名稱與網路不變（compose 專案名來自資料夾名，
> 資料夾名沒變）→ Tunnel 的 ingress 指向不受影響。
> launchd plist 與 `~/.local/bin/llmstack-mlx-primary-namecard` 都寫死過舊路徑，
> **已一併改掉**（各留 `.bak-migrate`）。

Git Bash 這台機器上的版本（`adopt.sh` 實際跑在這裡）：

| 工具 | 版本 |
|---|---|
| bash | 5.2.37 (MSYS) —— **不是** macOS 那個 3.2.57 |
| awk | GNU Awk 5.0.0 —— **不是** BSD awk |
| python3 | 3.13，有 PyYAML；**locale 是 cp950，不是 UTF-8**（見 §5） |

⚠️ **這台機器測不到 1.2.2 修的那兩個 bug**（bash 3.2 + BSD awk 是 macOS 專屬），
那條路徑現在只剩 `adopt-tests.yml` 的 `macos-latest` 在守。本機全過**不代表** macOS 會過。

### 移轉當下踩到的（換機器時會再遇到）

- **`core.filemode` 要設成 `false`。** 從 macOS 帶過來的設定是 `true`，
  Windows 表達不了 exec bit，Git 會把三支 `.sh` 報成 `100755 → 100644` ——
  **在這台機器 commit 就會把執行權限從 repo 裡剝掉**，Linux/macOS 的人
  `./adopt.sh` 直接壞。（歷史上已經修過一次：`9746eda`。）

- **用 robocopy 搬「正在用的」git repo 會搬出拼裝品。** `.git` 與工作檔案
  在不同同步世代被複製，結果工作區混著四個不同 commit 的檔案、index 還比 HEAD 舊。
  處理方式：確認每個檔案的 blob 都在歷史裡（就沒有獨有工作），
  然後 `git reset --hard origin/main` 重建。搬完務必跑一次
  `git status` + `git diff origin/main` 確認，別假設 robocopy 的 verify log 夠。

- **`.gitattributes` 救了換行。** `* text=auto eol=lf` 讓 `.sh`/`.yml` 在 Windows
  簽出仍是 LF，沒踩到 `bad interpreter: ...^M`。**別動它。**

---

## 5. 踩過的坑（**別重蹈覆轍**）

### 關於這個 repo

- **Gate 一定要用白名單邏輯。**
  `needs.<job>.result` 在 job 被 runner 取消時**不是** `cancelled`，
  所以「列舉失敗狀態」的黑名單會靜靜放行。必須寫成
  「這個 job 啟用了 ⇒ 結果必須是 `success`」。
  1.1.0 之前 CI Gate 綠燈但檢查根本沒跑過，就是這個。

- **有 `if` 條件的 job 絕不能設成 required check。**
  被 skip 的 check 永遠不會回報，PR 直接卡死。只把 Gate 設成 required。

- **公版不能用 adopt 導入自己。**
  公版的呼叫端刻意用 `uses: ./` 做 dogfooding；被改成 `owner/repo@ref`
  之後，PR 上跑的就不再是「這個 PR 的版本」，綠燈會變成假的。
  `adopt.sh` 有安全閥擋這件事，別拿掉。

- **`scripts/test-adopt.sh` 是破壞性測試，一定要先 `cd` 到暫存目錄。**
  2026-08-08 出過事：舊版用命令替換取路徑，`cd` 只發生在子 shell，
  所有情境都跑在 ci-standards 自己身上，把 `.github/` 整組改掉還 commit 進 main，
  讓那個 PR 的綠燈變成假的。現在測試起點就在 `mktemp -d`，`new_repo` 還會斷言 `$PWD`。
  **`git status --porcelain` 乾淨不等於沒事** —— 被改的檔案如果被 commit 了，它一樣乾淨。

- **改 `templates/` 就等於改所有「之後新導入」的專案**；
  改 `.github/workflows/*-reusable.yml` 等於改**所有現有**專案。兩者影響面不同。

### 關於工具與環境

- **「43 項全過」只證明它在測試那台機器上會過。**
  1.2.1 的回歸測試是在雲端（Linux + bash 5.x + GNU awk）跑的，全綠；
  但 `adopt.sh` 在 macOS（bash **3.2.57** + BSD awk）**從第 120 行就直接中止**，
  也就是 `docs/ADOPT.md` 列在第一順位的平台，腳本根本跑不起來。
  1.2.2 才修掉，並加了 `adopt-tests.yml` 的 `[ubuntu-latest, macos-latest]` matrix。
  兩個具體地雷：

  - **bash 3.2 會把全形標點的首位元組吃進變數名。**
    `"公版：$STD（ref: ...）"` 在 UTF-8 locale 下的 bash 3.2 會解析成變數
    `STD\xef`，配上 `set -u` 就是 `STD?: unbound variable`。
    bash 5.x 不會，`LC_ALL=C` 也不會 —— Linux CI 測不到。
    **`$VAR` 後面接非 ASCII 字元時一律寫成 `${VAR}`。**
    這個 repo 的訊息全是中文，等於每一行 `info "…$VAR…"` 都是候選地雷。

  - **BSD awk 不接受 `-v` 的值裡有換行**（`awk: newline in string`），GNU awk 才容忍。
    多行字串要走 `ENVIRON[]` 傳給 awk。

- **同一個教訓的第三次：Windows 的 Python 預設不是 UTF-8。**
  2026-08-13 移轉到 Windows 後第一次跑回歸測試就是 42/43，掛在
  「所有 workflow YAML 仍可解析」。**產生的 YAML 完全沒問題** ——
  是測試自己的 `open(f)` 用了 locale 編碼（繁中 Windows 是 **cp950**）去讀
  含中文註解的 UTF-8 檔，`UnicodeDecodeError` 被誤報成「adopt 產生的 YAML 壞了」。

  - **讀檔一律明寫 `encoding='utf-8'`。** Linux/macOS 的 locale 就是 UTF-8，
    所以這條路徑在雲端永遠測不到。Python 3.15 才會改預設，在那之前不能省。
  - **注意這跟 macOS 那兩個是同一類**：「某個平台的預設值跟開發機不一樣」。
    已經連續三次了 —— bash 3.2、BSD awk、cp950。
  - **不要用 `2>/dev/null` 吃掉測試的錯誤訊息。** 原本這項失敗只印
    「YAML 解析失敗」五個字，不知道哪一檔、什麼原因，診斷花掉的時間遠超過
    印出訊息的成本。現在會印出檔名 + 原因。
  - ⚠️ **`adopt-tests.yml` 的 `windows-latest` 抓不到這個 bug** ——
    runner 的 locale 是 UTF-8。那條 matrix 守的是「Git Bash 這個 shell 環境」，
    真正防住編碼問題的是程式碼裡明寫的 `encoding='utf-8'`。

- **第四次：Windows PowerShell 5.1 沒有 BOM 就不當 UTF-8。**
  同一天稍晚，`adopt.ps1` 第一次在真 Windows 上執行 —— **連 parse 都過不了**，
  19 個 parser error。5.1 讀 `.ps1` 沒看到 BOM 就用 ANSI codepage（繁中 = cp950），
  中文註解全變亂碼，亂碼再湊出讓字串提前結束的位元組。

  - **`.ps1` 含非 ASCII 就必須存 UTF-8 有 BOM。** 1.2.3 已修，理由寫在檔頭與
    `.gitattributes`，**別為了「統一無 BOM」把它拿掉**。
  - **腳本產出的 YAML 仍是無 BOM** —— 兩件事不要混為一談。
  - **pwsh 7 完全正常，所以它藏了很久。** 驗這種東西一定要用
    `powershell.exe`（5.1），不能用 `pwsh`。
  - 目前**沒有自動守門**（見 §3 ⑦）。

  ### 這一類問題的通則

  bash 3.2、BSD awk、Python cp950、PowerShell 5.1 —— **四次都是同一句話**：

  > 某個平台的預設值跟開發機不一樣，而那條路徑從來沒有人在那個平台上跑過。

  所以：**「在我的機器上全過」永遠只證明「在我的機器上全過」。**
  新增任何依賴平台預設值的東西（編碼、shell 版本、內建工具實作），
  要嘛明確寫死（`encoding='utf-8'`、`${VAR}`、BOM），要嘛在該平台上實測。

- **`git push --dry-run` 會給假成功。** 這個 repo 的網路路徑上，
  `--dry-run` 只做協商、不做 ref 更新，所以「成功」不代表真的推得上去。
  推 tag 這種事一律真的推，然後用 `git ls-remote --tags origin` 驗。

- **雲端 session 推不了 tag。** Claude Code on the web 的 policy gateway
  只放行 `claude/*` 分支的 ref，tag ref 回 403。tag 一律在本機打。

- **`claude` 不要串在 `&&` 後面一起貼。** 會 `EINTR` ——
  TUI 啟動要接管 stdin（raw mode），殘留的貼上結束序列會打斷它的第一次讀取。
  `cd` 一行、`claude` 手打一行。

- **`less` 沒有 `-F` 會吃掉後續貼上的指令。** 已用
  `git config --global core.pager 'less -FRX'` 修掉。

- **`.gitattributes` 強制 `.sh`/`.yml`/`.ps1` 用 LF**，否則 Git Bash 會出
  `bad interpreter: ...^M`。移轉到 Windows 之後這條從「預防」變成「正在生效」——
  **別動它。**

- **Git Bash 會把看起來像路徑的參數改寫成 Windows 路徑（MSYS path conversion）。**
  `git show "origin/main:docs/HANDOFF.md"` 會變成 `origin\main;docs\HANDOFF.md`
  然後噴 `unknown revision`。前面加 `MSYS_NO_PATHCONV=1` 就好。
  這只影響互動操作，不影響腳本本身。

<details>
<summary>已作廢：macOS 時期的環境坑（2026-08-13 前）</summary>

- **多行貼上會卡在輸入緩衝區。** zsh 的 bracketed paste 把多行當一整段待送出內容，
  看起來像「沒反應」。給使用者的指令**寫成一行**，用 `&&` 串接。
  （Windows 換成 PowerShell／Git Bash 之後不再適用，但如果之後又回到
  zsh／macOS，這條還是會踩。）

- **macOS 的 `~/Library/CloudStorage` 受 TCC 保護。**
  `find ~ ... 2>/dev/null` 會因為 EPERM 什麼都找不到，看起來像「檔案不存在」。
  終端機需要「完整取硬碟取用權」。

- **🔴 不要把 git repo 放在 OneDrive 裡。** 2026-08-13 搬遷時的實測：
  OneDrive 的「隨選檔案」佔位檔（`ls -lO` 顯示 `dataless`）**會停止實體化** ——
  一個 40 KB 的檔案 60 秒讀不下來，`nettop` 抓不到任何 OneDrive 傳輸。
  症狀不是「慢」，是**整個卡死**：

  - `git status` 直接 `fatal: .git/index: unable to map index file: Operation canceled`
  - `rsync` 讀到 dataless 檔案就無限期停住（實測卡了 8 分 43 秒才被中止）
  - AdminAutoTools 的 `.git` 有 **557 個 dataless 檔案，含 loose object**

  **正確的搶救順序**（而不是等 OneDrive 修好）：
  1. **packfile 通常是好的**，dataless 集中在 loose object → `git log` 多半還讀得出來
  2. 逐一比對本機 ref 與 `git ls-remote`，找出**只存在本機**的分支
     （那次 14 個分支只有 1 個是本機獨有）
  3. 有 remote 的 repo **一律重新 `git clone`**，別搶救 OneDrive 的 `.git`
  4. 再把**已實體化的檔案疊上去**（排除 `.git`），未提交的修改與 `.env`
     這類未追蹤檔案就保住了
  5. 剩下讀不到的**逐檔重試** —— 實體化是間歇性的，那次兩輪救回 18 個

- **複製檔案清單時，`find -type f` 會漏掉兩種東西。** 兩個都在上面那次搬遷實際踩到：
  - **符號連結**（`-type l`）。漏掉 120 個，其中包含 `.venv/bin/python`，
    害 MLX server 起不來。要用 `\( -type f -o -type l \)` 並給 rsync `--links`。
  - **空目錄**（`--files-from` 只建有檔案的路徑）。postgres 因為缺 `pg_notify`
    而 `FATAL: could not open directory "pg_notify"`，整個 stack 起不來。
    補法：`rsync -a --include='*/' --exclude='*'` 單獨補一次目錄結構。

  > 附帶一提：Python venv **搬家後不必重建**。`bin/python` 是指向系統 Python 的
  > 絕對符號連結，`sys.prefix` 由執行檔位置推導，所以路徑換了照樣能跑 ——
  > 前提是那個 symlink 真的有被複製過去。

</details>

### 關於 Copilot

- **Copilot code review 永遠送 `COMMENTED`，不送 `changes_requested`。**
  薄殼只認 `changes_requested` 的話，它的意見永遠進不了自動修迴圈。
- **Copilot 審完沒問題也是送 `COMMENTED`**（0 則 inline 意見），
  所以公版會先確認該 review 真的有 inline 意見才動作，不會誤觸發也不吃 attempt 次數。
- **Copilot 有時會進降級模式**（自陳 unable to run its full agentic suite），
  這種狀態下的建議可能結論錯誤。PR #15 就是實例：照它的建議拿掉 `always()`，
  結果變成「只有什麼都沒掃到才上傳 SARIF」。**它的意見要驗過再採納，不對就回覆說明並 resolve。**

---

## 6. 雲端 session 做得到 / 做不到

留著這張表，是為了知道什麼時候該切到本機。

> **2026-08-13 起「本機」有兩台**：Windows（主要）與 macOS（仍在服役，見 §4）。
> 兩台能做的事不一樣，所以分成兩欄。

| 事情 | 雲端 | 本機 Windows | 本機 macOS |
|---|---|---|---|
| 改公版程式碼、開 PR、盯 CI | ✅ | ✅ | ✅ |
| push 到 `claude/*` 分支 | ✅ | ✅ | ✅ |
| **push tag** | ❌ 403 | ✅ | ✅ |
| **讀寫使用者機器上的專案**（AdminAutoTools 等） | ❌ 看不到 | ✅ | ✅ |
| 跑 `adopt.sh` 對真實專案 | ❌ | ✅（Git Bash） | ✅ |
| **跑 `adopt.ps1`** | ❌ | ✅ **唯一做得到的** | ❌ |
| 跑 `scripts/test-adopt.sh` | ⚠️ 只有 Linux | ⚠️ 只有 Git Bash（bash 5.2 + GNU awk） | ✅ bash 3.2 + BSD awk |
| **測到 macOS 那條路徑**（bash 3.2 + BSD awk） | ❌ | ❌ | ✅ |

重點是**兩台各自補上對方的盲區**：

- `adopt.ps1` 只有 Windows 跑得了（PS 5.1 那個 BOM bug 就是在那裡抓到的）
- **bash 3.2 + BSD awk 只有 macOS 測得到** —— Windows 的 Git Bash 是
  bash 5.2 + GNU awk，跟 Linux 一樣，測不到 1.2.2 修的那兩個 bug

所以：**在任何一台上「43 項全過」都只證明那一台會過。** 動 `adopt.sh` 時，
真正的覆蓋來自 `adopt-tests.yml` 的三平台 matrix，不是本機那一次。

⚠️ 而且那些 check 目前**只會讓 PR 顯示紅燈，不會擋下合併** —— `adopt-tests.yml`
是獨立 workflow，它的 job 不在 `ci / CI Gate` 底下，而 ruleset 只把兩個 Gate
設成 required（見 §3 待辦 ④）。在那三個 check 進 ruleset 之前，**綠燈不是保證，是提示**。
而且**改 shell 腳本時本來就該記得 `${VAR}` 與 `encoding='utf-8'` 那兩條規則** ——
CI 是最後一道防線，不是第一道。
