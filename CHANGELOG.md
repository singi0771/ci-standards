# Changelog

本 repo 是**中央公版**：所有專案用 `uses: .../@v1` 呼叫它。
一次改動會同時影響所有專案，所以每次發佈都必須記在這裡。

版本規則見 [README — 版本策略](README.md#版本策略)。每次發佈打兩個 tag：
不可變的 `vX.Y.Z`（回滾點）+ 會移動的 `vX`（大家指向的別名）。

格式參考 [Keep a Changelog](https://keepachangelog.com/zh-TW/1.1.0/)。

---

## [未發佈]

### 新增
- `docs/HANDOFF.md` —— 交接文件：現況快照、待辦（依序，含驗收標準）、
  踩過的坑、以及「雲端 session 做得到／做不到」對照表。
  換人或換機器接手時先讀這份，不必從 CHANGELOG 重新推導。
  這是一份**活的**文件，做完一段工作就更新。

### 變更
- `docs/HANDOFF.md` 同步 1.2.2：更新現況快照（`main`、`v1`、adopt.sh 的驗證狀態），
  並把「43 項全過只證明它在測試那台機器上會過」寫進「踩過的坑」——
  含 bash 3.2 會把**全形標點的首位元組併進變數名**（`$STD（` → 變數 `STD\xef`）、
  BSD awk 不接受 `-v` 帶換行這兩個具體地雷。
  §6 的對照表也更正：雲端只跑得到 Linux 那條。

- `docs/HANDOFF.md` §3 新增待辦：把 `adopt regression (ubuntu-latest / macos-latest)`
  兩個 check 加進本 repo 的 ruleset。`adopt-tests.yml` 是獨立 workflow，
  它的 job **不在 `ci / CI Gate` 底下**，所以現在測試失敗只會在 PR 顯示紅燈、
  不會擋下合併 —— 而 1.2.2 的整個教訓就是「這條路徑沒被守住」。
  這是本 repo 專屬的設定，不進 `scripts/setup-branch-protection.sh`
  （consumer 沒有這支 workflow，列進去會變成永遠不回報的 required check → PR 卡死）。

### 修正
- `scripts/test-adopt.sh`：讀 workflow 檔時明寫 `encoding='utf-8'`。
  原本的 `open(f)` 用的是 **locale 編碼**，在繁中 Windows（cp950）上讀這些
  含中文註解的 UTF-8 檔會噴 `UnicodeDecodeError` —— 於是「這台機器的 locale
  不是 UTF-8」被誤報成「adopt 產生的 YAML 壞了」。實際產出完全正常。

  這是繼 bash 3.2、BSD awk 之後**同一類問題的第三次**：某個平台的預設值
  跟開發機不一樣，而那條路徑沒有人測過。Python 3.15 才會把預設改成 UTF-8。

- `scripts/test-adopt.sh`：YAML 檢查失敗時印出**檔名與原因**，不再 `2>/dev/null`
  吃掉錯誤。原本只印「YAML 解析失敗」五個字，診斷成本遠高於印訊息的成本。

### 變更（CI）
- `adopt-tests.yml` 的 matrix 加入 `windows-latest`，並用 `defaults.run.shell: bash`
  讓三個平台走同一條路（Windows 上是 Git Bash —— 使用者實際跑 `adopt.sh` 的環境）。

  ⚠️ 範圍要說清楚：runner 的 locale 是 UTF-8，**這條 matrix 抓不到上面那個
  cp950 bug**。真正防住它的是程式碼裡明寫的 `encoding='utf-8'`；matrix 守的是
  「Git Bash 這個 shell 環境」本身。

- `adopt-tests.yml` 新增一步：斷言 `python3` + PyYAML 真的可用。
  `test-adopt.sh` 內部找不到 `python3` 時會**安靜地 skip** YAML 檢查，
  而那正是抓到這次 bug 的那一項 —— 讓「跳過」當場紅燈，不要變成假綠燈。
  安裝改用 `python -m pip`（Windows 的 setup-python 只保證 `python` 在 PATH 上）。

- `docs/HANDOFF.md`：開發機 2026-08-13 從 macOS 移轉到 Windows，§4「環境與路徑」
  整節改寫（舊的 `/Users/kimi/...` 與 `$CODE_WORK` 全部作廢），§6 對照表更新為
  「本機 = Windows」。同時記下移轉本身踩到的兩個坑：`core.filemode` 要設 `false`
  （否則在 Windows commit 會剝掉 `.sh` 的執行權限），以及用 robocopy 搬
  使用中的 git repo 會搬出「工作區混著多個 commit」的拼裝品。

  ⚠️ 連帶影響：**本機不再測得到 macOS 那條路徑**（以前開發機就是 Mac，
  等於天然有覆蓋），現在只剩 CI 的 `macos-latest` 在守。

- `docs/HANDOFF.md` §2／§3：待辦 ①②（AdminAutoTools 重跑 adopt、設
  `COPILOT_TRIGGER_PAT`）經查證**其實都已完成**，改標為完成並附驗證指令；
  ③（驗 `adopt.ps1`）因為開發機變成 Windows 而**從封鎖變成可執行**，升為現在的重點。
  新增待辦 ⑥：AdminAutoTools 的三支 copilot 薄殼釘的是 `@main` 而不是 `@v1`，
  等於繞過發佈閘門，要改回來。

---

## [1.2.2] — 2026-08-13

**`adopt.sh` 在 macOS 上完全跑不起來。** 一樣只動導入工具，reusable 與
`templates/` 一個字都沒動，指向 `@v1` 的專案 CI 行為完全不變。

1.2.1 的回歸測試「43 項全過」是在雲端（Linux + bash 5.x + GNU awk）跑出來的。
macOS 的預設環境是 **bash 3.2.57 + BSD awk**，兩者都會踩 —— 也就是說
`docs/ADOPT.md` 列在第一順位的平台，腳本從第 120 行就直接中止。

### 修正

- **bash 3.2 會把全形標點的首位元組吃進變數名。**
  `"── 公版：$STD（ref: ...）"` 這種寫法，在 UTF-8 locale 下的 bash 3.2
  會解析成變數 `STD\xef`，配上腳本的 `set -u` 就是
  `STD?: unbound variable`，執行立刻中止。

  bash 5.x 不會，`LC_ALL=C` 也不會 —— 所以 Linux CI 與雲端 session 都測不到。
  修法：`$VAR` 後面接非 ASCII 字元時一律改成 `${VAR}`（`adopt.sh` 6 處、
  `test-adopt.sh` 2 處）。

- **BSD awk 不接受 `-v` 的值裡有換行。**
  `filter_with_block` 與 `replace_with_block` 用 `-v` 傳多行字串
  （`known` / `additions` / `blk`），macOS 內建的 awk（BWK awk 20200816）會噴
  `awk: newline in string ... at source line 1` 並放棄整個程式，GNU awk 才容忍。
  改走 `ENVIRON[]` 傳遞 —— POSIX awk 皆支援，兩邊行為一致。

  腳本開頭有 `set -euo pipefail`，所以 awk 的非零狀態會讓它**當場中止** ——
  後面的 `mv "$f.tmp" "$f"` 不會執行，**原檔完好**，最多留下一個 0 bytes 的
  `.tmp`。症狀是「導入跑到一半整個停掉」，不是檔案被寫壞。

- 回歸測試現已在 macOS（bash 3.2 + BSD awk）實際跑過，43 項全過。
  這是 `test-adopt.sh` 第一次在 macOS 上執行。

- **`test-adopt.sh` 會把「環境缺套件」誤報成「測試失敗」。**
  「所有 workflow YAML 仍可解析」那一項只檢查 `python3` 存在，沒檢查
  **PyYAML 裝了沒**；`ImportError` 被 `2>/dev/null` 吃掉，於是印出
  `❌ YAML 解析失敗`。macOS runner 正好有 python3、沒有 PyYAML ——
  新加的 CI 第一次跑就踩到。

  改成先驗 `python3 -c 'import yaml'`，缺套件時走新的 `skip()`（`⊘`），
  與 `FAIL` 分開計數、不影響 exit code。CI 那邊則直接把 PyYAML 裝起來，
  讓這項真的驗到而不是跳過。

### 新增

- **`.github/workflows/adopt-tests.yml`：`test-adopt.sh` 首次進 CI，並跨
  `ubuntu-latest` × `macos-latest` 兩個平台跑。**

  在此之前這 43 項回歸測試**完全不在 CI 裡**，全靠人記得手動執行 ——
  1.2.2 這兩個 bug 能活到現在正是因為這個缺口。macOS job 刻意用
  `/bin/bash`（而非 `bash`）呼叫，避免 runner 的 PATH 上有 Homebrew 的
  bash 5.x 而測不到系統內建的 3.2.57。

  最後一步會比對 `git status --porcelain`，確保測試沒有污染本 repo ——
  呼應 2026-08-08 那次「破壞性測試跑在 ci-standards 自己身上、還 commit
  進 main」的事故。

  這支 workflow 是本 repo 自己的工具測試，**不是給 consumer 呼叫的公版**，
  也刻意不列為 required check（Gate 仍只有兩個）。

---

## [1.2.1] — 2026-08-12

**修的是「導入工具」，不是公版邏輯。** reusable 與 `templates/` 一個字都沒動，
所以指向 `@v1` 的專案 CI 行為完全不變 —— 但**停在 1.2.0 之前的專案要重跑一次
`adopt.sh` 才會真正拿到 1.2.0 的自動修迴圈**（1.2.0 那版的升級路徑補不進去）。

### 修正
- **`scripts/adopt.sh` / `adopt.ps1`：升級模式漏掉 1.2.0 的契約變更。**
  原本五支呼叫端一律走「就地合併」，而就地合併只碰 `with:` 區塊。
  1.2.0 真正改的是三支 `copilot-*` 薄殼的 `if:` 條件與 `secrets:` 區塊
  （多收 Copilot 的 `COMMENTED` review、把 `COPILOT_TRIGGER_PAT` 傳進公版），
  所以舊 consumer 升級後會拿到**新的 `uses:` 卻留著舊的 `if:` 和缺席的 `secrets:`**
  —— 版本號變了、自動修迴圈還是壞的。腳本雖然會印一行警告要人「從 templates/ 重新複製」，
  但一鍵導入卻要人手動補檔，等於這條路沒有真正打通。

  改成**檔案分三類**：
  - `ci.yml` / `security.yml`（真的帶專案設定）→ 維持就地合併
  - 三支 `copilot-*` 薄殼（`if:`/`with:` 接線/`secrets:` 都是公版契約）→ **整份換成新範本**，
    只把使用者自己打開過的旋鈕（`max-attempts`、`max-review-requests`）搬回來，
    舊檔留成 `.bak`；內容沒變就不留，維持冪等
  - 專案專屬的四個檔 → 維持絕不覆蓋

  「哪些旋鈕該搬」不寫死：判準是「舊檔有設、而新範本沒設」，且公版 reusable
  仍認得該 input（不認得的照樣移除並回報）。原本的契約檢查改成收尾用的
  post-condition —— 會叫就代表 `--std` 指到的公版比 1.2.0 舊。

  回歸測試新增 15 項（`scripts/test-adopt.sh` 情境 B），模擬停在 1.2.0 之前、
  且調過 `max-attempts` 的 consumer（AdminAutoTools 就是這個狀態）。

- **`scripts/adopt.ps1` 會把檔案寫錯地方（Windows 專屬）。**
  `Set-Location` 只改 PowerShell 的位置，不改行程的工作目錄；而腳本為了控制
  「UTF-8 無 BOM + LF」用的是 `[System.IO.File]` 這組 .NET API，相對路徑會解到
  **PowerShell 當初啟動的目錄**。用 `-Target` 指向別的專案時，`.github\...`
  會落在錯的地方。補上 `[System.IO.Directory]::SetCurrentDirectory()`。

- `docs/KNOWN-LIMITATIONS.md` 的 `action_required` 一節有**兩份重複的排查步驟**，
  而且都指向 fork PR 的核准設定 —— 那條路已知無效（Copilot 推的是同 repo 分支不是 fork；
  `POST /actions/runs/{id}/approve` 對這些 run 回 403，而該 API 只服務 fork PR）。
  改寫成「這是 GitHub 對 coding agent 的安全設計，沒有開關可調」，並保留那兩個佐證，
  免得日後有人再花時間去調那個沒用的設定。總表該列也從「這條要先解」一併更正。

### 變更
- `docs/ADOPT.md` 升級一節改寫成「三類檔案、三種策略」，並說明薄殼為什麼不能就地合併。
- 導入完的提示新增「設定 repo secret `COPILOT_TRIGGER_PAT`」——
  沒設的話 CI 會過，但自動修迴圈不會動工，是導入後最容易漏掉的一步。
- `docs/SETUP.md` 新增「只留一個 review 觸發源」與「Review thread 一律要求 resolve」兩節。
  GitHub 原生的「每個 PR 自動請 Copilot review」與公版的 `copilot-autoreview-gate`
  同時開著會互相打架：原生那條在 CI 之前就審，違反「先讓免費掃描器擋掉明顯問題、
  確定值得看了才花 AI credits」的設計順序，還會審到 Dependabot 的純版本更新
  （gate 刻意跳過那類）。2026-08-09 PR #15 就是實例 —— 降級模式（Copilot 自陳
  unable to run its full agentic suite）下的 review 提出結論錯誤的建議，
  照做之後把 `security-reusable.yml` 改出一個回歸。
  建議關掉原生自動 review，只留 gate 驅動的那條；thread resolution 則維持強制。

---

## [1.2.0] — 2026-08-09

**這一版讓「Copilot 依 review 意見自動修正」第一次真正動起來。**
實測（AdminAutoTools PR #52–#63）證明 1.1.0 的自動修正迴圈存在兩個致命斷點，
等於**從未實際運作過**——所有「採納 Copilot 意見」的修正 commit 其實都是人工完成的：

1. **觸發條件錯配**：autofix-review 薄殼只認 `changes_requested`，但 Copilot code review
   永遠只送 `COMMENTED`（它不會、也不能 request changes）→ Copilot 的意見從不觸發自動修正。
2. **mention 無效**：`@copilot` 留言由 `github-actions[bot]`（`GITHUB_TOKEN`）發出，
   coding agent 會忽略 bot 的 mention（GitHub 防 bot 迴圈機制）→ 就算觸發了也叫不動 Agent。

### 新增 —— Copilot 迴圈開通（ci-standards PR #12）

- `copilot-autofix-review-reusable.yml`：
  - 新增 `review-id` / `review-state` 輸入：COMMENTED review 先確認**真的有 inline 意見**
    才動作（Copilot「審完沒問題」也是送 COMMENTED，0 則意見即跳過，不吃 attempt 次數）；
    `review-state=commented` 但缺 `review-id` 時 fail-closed 直接跳過。
  - 新增 `copilot-trigger-pat` secret：`@copilot` mention 改由**有 Copilot 授權的使用者 PAT**
    發出；未設定時退回 bot token 並發 `::warning::`（留言照貼保留記帳，但 Agent 不會動工）。
- `copilot-autofix-reusable.yml`（CI/Security 失敗那條）：同樣新增 `copilot-trigger-pat`
  secret 與未設定警告 —— 這條的 mention 過去同樣是 bot 發的、同樣無效。
- `copilot-autoreview-reusable.yml`：步驟 5 移除無效的 `@copilot` mention，改為純去重
  標記＋狀態說明（「請審」走 API 本來就有效；「修」的職責交給 autofix-review 那條路）。
- consumer 範本 `copilot-autofix-review.yml` / `copilot-autofix-ci-security.yml`：
  觸發條件與 `secrets:` 傳遞同步更新（見下方相容性）。
- **觸發條件資安強化**（採納 PR #14 的 Copilot 審查意見）：真人 `changes_requested`
  限定信任身分（OWNER/MEMBER/COLLABORATOR）——公開 repo 上陌生帳號的 review
  不得驅動 agent 執行其指示；Copilot login 改精確比對（`contains` 可被相似帳號名繞過）。
- 本 repo **自用薄殼**同步至新契約（dogfooding：1.2.0 起 ci-standards 自己的 PR
  也走完整迴圈；需在本 repo secrets 設 `COPILOT_TRIGGER_PAT`）。
- `adopt` 契約檢查同時涵蓋 `secrets:` 與 COMMENTED 觸發條件兩塊——只補其一
  仍會被警告，避免「半升級」被誤判為相容。
- README 新增 **`COPILOT_TRIGGER_PAT` 設定步驟**（fine-grained PAT，
  Issues:write + Pull requests:write，範圍限單一 repo）。

### 修正 —— OSV-Scanner 不再被上游故障癱瘓（ci-standards PR #13）

- 🔴 **deps.dev 解析服務故障會讓所有 PR 全紅**（2026-08-08 起連續兩天實測）：
  osv-scanner 對 manifest（requirements.txt）做間接依賴解析時，Google deps.dev 回
  `rpc error: Internal`，即使**實際弱點數為 0** 也以 exit 1 收場 → Security Gate 全面擋門，
  且錯誤訊息被誤標成「Vulnerabilities found!」。
- 修法：偵測到「非零 exit + `failed resolution`/`rpc error` 字樣 + **第一輪弱點數為 0**」
  三個條件同時成立，才自動以 `--no-resolve` 重掃一次 —— 直接依賴照掃、有弱點照擋，
  僅 manifest 間接依賴當輪降級，並以 `::warning::` 明示。
  第一輪已掃出弱點時**不進 fallback**，避免視野較窄的第二輪把弱點判定蓋成綠燈
  （此守門條件採納自 Copilot code review 意見 —— 也是本迴圈第一次實戰自我修正）。

### 新增 —— 一鍵導入（自 [未發佈] 收入本版）

- **一鍵導入腳本**，跨平台雙版本：
  - `scripts/adopt.sh` —— macOS / Linux / Windows Git Bash
  - `scripts/adopt.ps1` —— Windows PowerShell 5.1（**系統內建，零安裝**）

  會自動偵測 Dockerfile / Python / shell script 並把 `ci.yml`、`security.yml` 的參數填好。

  **兩種模式**：目標沒有呼叫端就整份鋪上（`install`）；已經有舊版就改用**就地合併**
  （`upgrade`）—— 保留使用者調過的參數與自訂的 `on:` 觸發、保留 `with:` 裡的註解、
  **移除公版已廢除的 input**（留著會讓 workflow 直接 `invalid input` 起不來）、
  補上公版新增的 input、更新 `uses:` 的 ref，而 **job id 絕不更動**（分支保護綁著它）。

  「公版有哪些 input」是直接讀 reusable 的 `workflow_call.inputs` 宣告，
  不是腳本裡寫死的清單 —— 公版加減 input 時自動跟上。

  `copilot-instructions.md` / `copilot-setup-steps.yml` / `pull_request_template.md` /
  `dependabot.yml` 含專案專屬內容，**已存在時絕不覆蓋**，只另存一份 `.new` 供比對。
- `scripts/test-adopt.sh` —— 回歸測試，涵蓋全新導入、升級舊版、冪等、
  `--dry-run`、`--uses-repo` 五個情境共 26 項檢查。
- `adopt.sh` / `adopt.ps1` 新增 `--uses-repo` / `-UsesRepo` —— 搬到組織時
  一併換掉 `uses:` 的 `owner/repo`，不用另外 sed。

  **相依只有 `git`** —— 刻意不用 `gh` / `jq` / `yq` / `python` / `curl`，
  因為受管制的公司環境上那些都不保證裝得起來。導入本身是純檔案操作，不碰網路。
- `docs/ADOPT.md` —— 跨平台用法、內網／離線／Proxy 的做法，以及
  「哪些步驟其實不需要 `gh`」的對照表（結論：`gh` 完全是選配）。
- **`.gitattributes`** —— 強制 `.sh` / `.yml` / `.ps1` 以 LF 簽出。
  沒有它的話，Git for Windows 預設 `core.autocrlf=true` 會把 shell script
  轉成 CRLF，bash 會噴 `bad interpreter: /usr/bin/env: ...^M` ——
  而且 `\r` 不顯示，錯誤訊息完全看不出原因。推廣到 Windows 環境前必須先有這個。

### 變更
- README 的「步驟 1」改為以一鍵導入為主、手動複製收進 `<details>`。
  用一鍵版時步驟 2 的 ①② 可以跳過。

### 相容性 —— 既有 consumer 要做的事

- 公版新增的 input 與 secret 都是 optional，**舊薄殼呼叫新公版不會壞**，
  只是自動修正迴圈維持原本的「不會動」狀態。
- **要啟用迴圈，既有專案必須做兩件事**：
  1. 在 repo secrets 加 `COPILOT_TRIGGER_PAT`（設定步驟見 README）。
  2. **重新複製** `copilot-autofix-review.yml` 與 `copilot-autofix-ci-security.yml`
     兩支薄殼 —— 這是罕見的**薄殼契約變更**（`if:` 觸發條件 + `secrets:` 區塊），
     `adopt` 的升級模式只同步 `uses:` 與 `with:`，**不會**更新這兩個部分
     （腳本偵測到缺 `secrets:` 時會提醒）。
- 已知仍存在的人工關卡（GitHub 硬規定）：Copilot 推的 commit 觸發的 workflow run
  需要人按一次「Approve and run workflows」；替代法是自己推空 commit。
  詳見 `docs/KNOWN-LIMITATIONS.md`。

---

## [1.1.0] — 2026-08-06

**這一版把 `v1` 從 2026-07-25 的初版一路推到現在**，中間累積了三種會讓 PR 永久卡死的死鎖、
一個會讓相依弱點掃描靜默失效的漏洞，以及 Copilot 自動化迴圈的收斂機制。
`v1` 長期停在 1.0.0 期間，任何照文件導入的專案拿到的都是含上述問題的舊版。

### 新增 —— 公版能力

- `ci-reusable.yml` 新增 `run-python`、`run-actionlint`、`actionlint-paths`、
  `run-shellcheck`、`shellcheck-paths`。**非 Python 專案現在可以直接用公版**
  （`run-python: false`），不必自己另寫一支 CI，也就不會失去 `ci / CI Gate` 這個統一的 check 名稱。
- 本 repo 自己套用公版（dogfooding）：`.github/workflows/` 下的 `ci.yml`、`security.yml`
  與三支 `copilot-auto*` 薄殼，全部用 `./` 呼叫自己的 reusable ——
  改壞公版時當場就會紅，不會等到別人的專案才爆。
- `.github/copilot-instructions.md`、`.github/dependabot.yml`。

### 修正 —— 這是必須發佈的理由

- 🔴 **`CI Gate` 會把「沒跑到」當成「通過」**（2026-08-06 由本 repo 自己的 PR 實測踩到）。
  GitHub 因 runner 排隊過久取消了 `actionlint` 與 `shellcheck`，run 整體 `conclusion: failure`，
  但 `ci / CI Gate` 回報 **success** —— 而分支保護只認這個 Gate，等於**兩個檢查一行沒跑，PR 照樣可以合併**。

  原因：`ci-gate` 用的是黑名單（`只擋 failure|cancelled`），而被取消的 job 傳進
  `needs.<job>.result` 的值並不是 `cancelled`，所以漏掉了。
  同一批 job 之下 `security / Security Gate` 正確地失敗了 —— 它用的是白名單（`!= success` 就擋）。

  修法：兩個 Gate 一律改成白名單判定 —— **啟用了就必須是 `success`**，只有未啟用才允許非 success。
  `security-gate` 的 `trivy-image` 也有同型的洞（只擋 `failure`），一併補上。
- **`copilot-autofix` 的失敗清單可能是空的**：只挑 `conclusion == "failure"` 的 job，
  遇到「全部被取消」或 startup failure 時會貼出空清單。改為同時涵蓋
  `cancelled` / `timed_out` / `startup_failure`，全空時明講原因。
- **消除三種「PR 永遠 merge 不了」的死鎖**：`skipped` 的 required check 永遠不回報、
  呼叫端 `pull_request` 的 `paths-ignore` 會擋掉純文件 PR、required approvals 設 1 但沒人能 approve。
- **掃描失敗不再被當成通過**：OSV-Scanner 下載改用 `curl --fail` 並先驗 `--version`；
  非 0/1/128 的 exit code 一律視為掃描失敗而擋下（舊版把 127 當良性 warning 放行，
  等於**相依弱點掃描靜默失效卻依然綠燈**）。
- **掃描器釘死版本**：`semgrep/semgrep:1.171.0`、`ghcr.io/gitleaks/gitleaks:v8.30.1`、
  `rhysd/actionlint:1.7.12`。不釘的話上游新增規則會讓沒改碼的 repo 突然變紅，也是供應鏈風險。
- **Copilot 自動化迴圈收斂**：autoreview 加上次數上限與同 SHA 去重、autofix 加上 15 分鐘 cooldown
  與「升級後閉嘴」marker、補上貼 label 缺少的 `issues: write`（少了會靜默 403）。
- 所有 action 改為釘 commit SHA；`copilot-autofix-review-reusable.yml` 的
  `${{ github.repository }}` 改走 `env:`，不再直接插進 `run:` 字串。
- Dependabot `cooldown` 只保留 `default-days`（`semver-major-days` 會讓 github-actions
  ecosystem 判為 invalid config）。
- 修掉自我掃描抓到的 22 個 Semgrep findings。
- `setup-branch-protection.sh` 補上執行權限；重複執行改為 `PUT` 更新，不再建出第二份同名 ruleset。

### 相依更新

- `actions/checkout` v4 → v7.0.1、`actions/setup-python` v5 → v7.0.0、
  `actions/upload-artifact` v4 → v7.0.1、`github/codeql-action/upload-sarif` v3 → v4.37.3。
  全部維持 commit SHA 釘版本。

### 文件

- `docs/KNOWN-LIMITATIONS.md` —— **導入前必看**。實測過但還不能用的功能，
  每條附「怎麼測的 + 結果 + 逐步排查」。這些結論原本只存在於已關閉 PR 的留言裡。

  實測摘要：Gate 擋門、cooldown 去重、autoreview 去重全部正常；Copilot Code Review 正常；
  **Copilot Coding Agent 指派 Issue 可用**（會立刻開 PR），但
  ① Actions 貼的 `@copilot` 喚不醒它（GitHub 對 bot 觸發 bot 的防迴圈限制）、
  ② **Copilot 開的 PR，其 CI/Security run 全部卡在 `action_required`**
  → required check 永遠不回報 → 那個 PR 永遠 merge 不了。②才是自動修真正的擋路石。
- `docs/MIGRATION-TO-ORG.md` —— 搬到組織的完整 checklist，含所有寫死的 `owner/repo` 位置。
- `CONTRIBUTING.md`、`SECURITY.md`、`LICENSE`（MIT）、`CHANGELOG.md`、`.github/CODEOWNERS`、
  `.github/pull_request_template.md`（本 repo 自己的，原本只有給 consumer 的範本）。
- README 參數表補上遺漏的 5 個 `ci-reusable` input —— 這些 input 早就存在，
  但文件沒寫，等於功能沒人知道。
- README「專案不是 Python」改寫；運作原理圖補上 actionlint / shellcheck；
  檔案地圖補上 dogfooding workflow；版本策略改為雙 tag。
- `docs/DEVSECOPS-NOTES.md` 的釘版本說明與實作對齊（實際用 commit SHA 與直接下載 binary）。

### consumer 範本

- 去掉寫死的專案名稱，改成佔位符，並在 `copilot-instructions.md` 加上逐段「要不要改」對照表。
- `security.yml` 的 `scan-docker-image` 預設從 `true` 改回 `false`（與公版預設一致）——
  沒有 Dockerfile 的專案不會白起一個 job。**有 Dockerfile 的專案要自己改成 `true`。**

### 相容性

- 對既有呼叫端**完全相容**：新增的 input 都有預設值，不改任何 input 或 job 名稱，
  `ci / CI Gate` 與 `security / Security Gate` 這兩個 required check 名稱不變。
- 兩個行為變更，都是刻意的：
  1. 掃描器異常結束現在會擋下 PR（舊版放行）。
  2. 範本的 `scan-docker-image` 預設改為 `false` —— **只影響新導入的專案**，
     既有 repo 自己的 `security.yml` 不會被動到。

---

## [1.0.0] — 2026-07-25（`c19ff64`）

初版。`v1` tag 長期停在這裡。

⚠️ **不要使用這一版**：含 1.1.0 修掉的三種死鎖與掃描靜默失效問題，
且 `ci-reusable.yml` 只有 3 個 input，寫 `run-python: false` 會直接 invalid input 啟動失敗。
留著只作為回滾點。
