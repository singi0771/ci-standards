# 交接：現況與待辦

> **最後更新**：2026-08-13（對應 `main` = `e11d205`，已發佈版本 1.2.2）
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
| 3 | `CHANGELOG.md` 的 1.1.0 / 1.2.0 / 1.2.1 / 1.2.2 四段 | **每一版都在修「上一版以為修好、其實沒有」的東西**，這四段是全部的教訓來源 |
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
| `main` | `e11d205`（= 1.2.2 + 本文件） |
| CHANGELOG | 已定版到 **1.2.2**；`e11d205` 只多一份文件，未發版 |
| `v1` tag | ✅ 在 `fc239d2`（1.2.2 已發佈） |
| 最新版本 tag | ✅ `v1.2.2`（`v1.2.2^{}` → `fc239d2`） |
| 公版自己的 CI | ✅ 全綠（dogfooding，用 `uses: ./` 跑自己的 reusable） |
| AdminAutoTools | ⚠️ **停在 1.2.0 之前，自動修迴圈是壞的**，需要重跑 adopt |
| adopt.sh | ✅ 43 項回歸測試在 **Linux 與 macOS 都跑過**（1.2.2 起 `adopt-tests.yml` 有雙平台 matrix） |
| adopt.ps1 | ⚠️ **從未在真的 Windows 上執行過**，只逐段對譯 + 語法檢視 |

### 1.2.1 修了什麼（為什麼 AdminAutoTools 一定要重跑 adopt）

1.2.0 修好了 Copilot 自動修迴圈，改的是三支 `copilot-*` 薄殼的 **`if:` 條件**與
**`secrets:` 區塊**。但當時的 `adopt.sh` 升級模式是「就地合併」，而**就地合併只碰 `with:`**。

結果：舊 consumer 升級後拿到新的 `uses:`、卻留著舊的 `if:` 和缺席的 `secrets:` ——
**版本號變了，迴圈還是壞的**。1.2.1 就是修這個：三支薄殼改成整份換新。

所以對 AdminAutoTools 來說，**光移 `v1` tag 沒有用**，壞的是它本地那三支薄殼。
必須重跑一次 `adopt.sh`。

---

## 3. 待辦（依序）

> **1.2.1 已發佈完成**（`v1` 與 `v1.2.1` 都在 `ff1f356`）。
> 發佈的操作步驟移到本節最後的「發佈流程」，下次公版有實質變更時照那個走。

### ① 用 AdminAutoTools 測 adopt（1.2.1 的重點驗證）← 現在卡在這

AdminAutoTools 就在 ci-standards 隔壁，**注意它是巢狀結構**：
`CodingProject/AdminAutoTools/AdminAutoTools/`（外層資料夾包著真正的 clone）。

```bash
cd "$CODE_WORK/AdminAutoTools/AdminAutoTools"
git checkout main && git pull
"$CODE_WORK/ci-standards/scripts/adopt.sh" --std "$CODE_WORK/ci-standards" --dry-run
```

**驗收（dry-run）**：計畫裡三支 `copilot-*` 必須顯示 **`⟳ 換新`** 而不是 `↻ 合併`。
顯示「合併」就代表 `--std` 指到的公版是舊的，停下來檢查。

確認無誤後拿掉 `--dry-run` 真的跑，然後：

```bash
git diff                                  # 逐檔看過
git diff .github/workflows/copilot-autofix-review.yml
```

**驗收（實跑）**：`copilot-autofix-review.yml` 必須同時出現
`'commented'`、`review-id:`、`review-state:`、`secrets:` 底下的 `copilot-trigger-pat`，
而且原本調過的 `max-attempts` 要還在。

確認完刪掉備份、開 PR：

```bash
rm -f .github/workflows/*.bak .github/*.new
git checkout -b chore/adopt-ci-standards-1.2.1
git add .github && git commit -m "chore: 升級 ci-standards 公版至 1.2.1"
git push -u origin chore/adopt-ci-standards-1.2.1
```

### ② AdminAutoTools 設 repo secret（**最容易漏，漏了就白做**）

GitHub → AdminAutoTools → Settings → Secrets and variables → Actions →
New repository secret：

- Name：`COPILOT_TRIGGER_PAT`
- Value：**有 Copilot 授權的使用者**的 fine-grained PAT
  （權限 Issues: write + Pull requests: write，範圍限該 repo）

**沒設的話 CI 會全綠，但 Copilot 自動修迴圈不會動工**，而且沒有明顯錯誤 ——
因為 `@copilot` mention 必須由真人帳號發出，`github-actions[bot]` 發的會被
coding agent 忽略（GitHub 的防 bot 迴圈機制）。

### ③ 驗 adopt.ps1（Windows，尚未做過）

使用者有一台 Windows（PowerShell 7.6.3）。`adopt.ps1` **從未在真 Windows 上跑過**。

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\adopt.ps1 -Target "某個測試專案" -Std . -DryRun
```

特別要看：`.github\` 有沒有落在**正確的目錄**。1.2.1 修了一個相關 bug ——
`Set-Location` 不改行程的工作目錄，而腳本用 `[System.IO.File]` 讀寫（為了控制
UTF-8 無 BOM + LF），相對路徑會解到 PowerShell 啟動的目錄。已補
`[System.IO.Directory]::SetCurrentDirectory()`，但**沒實測過**。

### ④ 使用者端設定（GitHub 網頁，非程式）

- [ ] **關掉 GitHub 原生的「自動請 Copilot code review」**。它會在 CI 之前就審，
      違反「先讓免費掃描器擋掉明顯問題、確定值得看了才花 AI credits」的設計順序，
      而且會審 Dependabot 的純版本更新（公版的 gate 刻意跳過那類）。
      只留公版 `copilot-autoreview-gate` 驅動的那條。詳見 `docs/SETUP.md`。
- [ ] 確認 ruleset 的 `required_review_thread_resolution: true`

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

| 項目 | 值 |
|---|---|
| 公司專案根目錄 | `/Users/kimi/Library/CloudStorage/OneDrive-CECIEngineeringConsultants,Inc.,Taiwan/CodingProject` |
| ci-standards | 上述路徑 + `/ci-standards` |
| AdminAutoTools | 上述路徑 + `/AdminAutoTools/AdminAutoTools` ← **巢狀** |
| 個人專案根目錄 | 個人 OneDrive 底下的 `kimi/2_Code`（完整路徑待補） |

建議把根目錄寫進 `~/.zshrc`：

```bash
export CODE_WORK="/Users/kimi/Library/CloudStorage/OneDrive-CECIEngineeringConsultants,Inc.,Taiwan/CodingProject"
alias cw="cd $CODE_WORK"
```

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

- **`git push --dry-run` 會給假成功。** 這個 repo 的網路路徑上，
  `--dry-run` 只做協商、不做 ref 更新，所以「成功」不代表真的推得上去。
  推 tag 這種事一律真的推，然後用 `git ls-remote --tags origin` 驗。

- **雲端 session 推不了 tag。** Claude Code on the web 的 policy gateway
  只放行 `claude/*` 分支的 ref，tag ref 回 403。tag 一律在本機打。

- **多行貼上會卡在輸入緩衝區。** zsh 的 bracketed paste 把多行當一整段待送出內容，
  看起來像「沒反應」。給使用者的指令**寫成一行**，用 `&&` 串接。

- **`claude` 不要串在 `&&` 後面一起貼。** 會 `EINTR` ——
  TUI 啟動要接管 stdin（raw mode），殘留的貼上結束序列會打斷它的第一次讀取。
  `cd` 一行、`claude` 手打一行。

- **`less` 沒有 `-F` 會吃掉後續貼上的指令。** 已用
  `git config --global core.pager 'less -FRX'` 修掉。

- **macOS 的 `~/Library/CloudStorage` 受 TCC 保護。**
  `find ~ ... 2>/dev/null` 會因為 EPERM 什麼都找不到，看起來像「檔案不存在」。
  終端機需要「完整取硬碟取用權」。

- **Windows 路徑相依**：`.gitattributes` 強制 `.sh`/`.yml`/`.ps1` 用 LF，
  否則 Git Bash 會出 `bad interpreter: ...^M`。別動它。

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

| 事情 | 雲端 | 本機 |
|---|---|---|
| 改公版程式碼、開 PR、盯 CI | ✅ | ✅ |
| push 到 `claude/*` 分支 | ✅ | ✅ |
| **push tag** | ❌ 403 | ✅ |
| **讀寫使用者機器上的專案**（AdminAutoTools 等） | ❌ 看不到 | ✅ |
| 跑 `adopt.sh` 對真實專案 | ❌ | ✅ |
| 跑 `adopt.ps1`（需要 Windows） | ❌ | ✅ |
| 跑 `scripts/test-adopt.sh` | ⚠️ 只有 Linux | ✅ 含 macOS |

最後一列是 1.2.2 學到的：雲端跑得過**不代表** macOS 跑得過（bash 3.2 + BSD awk）。
現在 `adopt-tests.yml` 有雙平台 matrix，PR 上就會擋掉，不必再靠人工在 Mac 上補跑；
但**改 shell 腳本時仍要記得那條 `${VAR}` 規則**，CI 是最後一道防線不是第一道。
