# 一鍵導入（跨平台）

把公版導入一個專案，用 `scripts/` 底下的腳本，一行搞定。

| 你的環境 | 用哪一支 |
|---|---|
| macOS / Linux | `scripts/adopt.sh` |
| **Windows（PowerShell）** | `scripts/adopt.ps1` ← 內建就有，不用裝東西 |
| Windows（Git Bash） | `scripts/adopt.sh` 也可以 |

兩支功能完全相同，產出的檔案 byte-identical —— CI 的 Windows job 會真的用 PowerShell 5.1
跑一次 `adopt.ps1`、用 Git Bash 跑一次 `adopt.sh`，對同樣的範例專案（含 `--uses-repo`）`diff -r` 整個 `.github/` ——
全新導入一個、升級一個（升級那個刻意塞了 CRLF、`with:` 裡的空行、行尾註解這類最容易讓兩支分岔的寫法）。

---

## 需要裝什麼？—— 只有 git

這是刻意的設計取捨。腳本**不使用** `gh`、`jq`、`yq`、`python`、`curl`，
因為在受管制的公司環境裡那些都不保證裝得起來。

導入這一步是**純檔案操作**：複製一個資料夾 + 改幾個 YAML 值。
不需要網路（除非要讓腳本自己去抓公版）。

### 到底哪些步驟需要 `gh`？

| 階段 | 需要 | 沒有 `gh` 的替代 |
|---|---|---|
| **導入（複製範本 + 改參數）** | 檔案操作 | — 本來就不需要 |
| 推分支 | `git`（HTTPS 443） | — |
| 開 PR | — | **瀏覽器開就好** |
| 設分支保護 | GitHub API | 瀏覽器手動建 ruleset，或**組織層級 ruleset 一次涵蓋所有 repo**。repo 設不了分支保護（例如 Free 方案的 private repo）也能導入，見 [README — 沒辦法設分支保護時](../README.md#沒辦法設分支保護時) |

**結論：`gh` 完全是選配的。** 它只讓 `setup-branch-protection.sh` 和 `gh pr create` 方便一點。

> 規模化之後，分支保護的正解是**組織層級 ruleset** —— 在 org 設定一次，
> 涵蓋所有 repo，連腳本都不用跑。見 [MIGRATION-TO-ORG.md](MIGRATION-TO-ORG.md)。

---

## 用法

### macOS / Linux / Git Bash

```bash
cd /path/to/your-project
/path/to/ci-standards/scripts/adopt.sh
```

### Windows PowerShell

```powershell
cd C:\path\to\your-project
powershell -ExecutionPolicy Bypass -File C:\path\to\ci-standards\scripts\adopt.ps1
```

> **為什麼要加 `-ExecutionPolicy Bypass`**：公司電腦常用群組原則禁止執行 `.ps1`。
> 這個寫法只影響這一次執行，**不會改到機器的執行原則**，所以不需要管理員權限，
> 也不會被資安稽核盯上。（若貴公司強制 `AllSigned`，這招無效 —— 改用 Git Bash 跑 `.sh`。）

### 參數

| bash | PowerShell | 說明 |
|---|---|---|
| `--target <dir>` | `-Target <dir>` | 要導入的專案目錄（預設：目前目錄） |
| `--std <path>` | `-Std <path>` | 公版 clone 的位置（預設：自動找） |
| `--ref <tag>` | `-Ref <tag>` | 要指向的公版版本（預設 `v2`；2.0.0 之前是 `v1`） |
| `--uses-repo <owner/repo>` | `-UsesRepo <owner/repo>` | 公版搬到組織後換掉 `uses:` 的 owner/repo（`zizmor.yml` 的放行規則會一起換） |
| `--dry-run` | `-DryRun` | 只印偵測結果，不動檔案 |

**先跑 `--dry-run` 看它偵測到什麼**，確認無誤再真的跑。

---

## 兩種模式：全新導入 vs 升級

腳本會看目標有沒有 `.github/workflows/ci.yml` 或 `security.yml` 來決定模式。

### `install` —— 目標還沒有呼叫端

整份範本鋪上去，依偵測結果填好參數。

### `upgrade` —— 目標已經有舊版呼叫端

這是最容易出事的路徑，所以規則寫死。**檔案分三類，各有各的策略**：

| 類別 | 檔案 | 策略 |
|---|---|---|
| 帶專案設定 | `ci.yml`、`security.yml` | **就地合併**（保留你的值） |
| 專案專屬 | `pull_request_template.md`、`dependabot.yml`、`zizmor.yml` | **絕不覆蓋**（只放一份 `.new`） |

> 2.0.0 之前還有第三類「只負責觸發的呼叫端 workflow」（三支 `copilot-*`），
> 升級時整份換新。Copilot 流程移除後那一類已經沒有成員，腳本裡對應的程式碼也一併刪了。
> **已導入的專案要自己 `git rm` 那三支**（加上 `copilot-setup-steps.yml`）——
> 導入腳本從不刪專案裡既有的檔案，留著會指向不存在的 reusable、每次 PR 直接 `startup_failure`。

#### 1. 帶專案設定的：就地合併

| 情況 | 行為 | 為什麼 |
|---|---|---|
| 你調過的參數（`severity`、`fail-on-findings`、`python-version`…） | **保留原值** | 那是你針對這個專案的決定，偵測結果不該蓋過去 |
| 你自訂的 `on:` 觸發（例如改過的 cron） | **完全不動** | 只改 `uses:` 那一行與 `with:` 區塊，其餘原樣。所以「草稿 PR 跳過」這種寫在 `on:` 的新設計，升級不會幫你加，要的話照範本手動改。**唯一的例外**見下面「v1 → v2 的觸發條件修補」 |
| `with:` 裡的註解、空行 | **保留** | `# max-attempts: "3"` 這種提示不該消失；區塊中間的空行不會被當成區塊結束 |
| 公版**已廢除**的 input | **移除並回報** | 留著會讓 workflow 直接 `invalid input` 起不來。升到 v2 時會拿掉 `security.yml` 的 `python-version`、`upload-sarif` |
| 公版**新增**的 input | 補上（用偵測值） | 只補「你檔案裡沒有」的，不覆寫既有的。例如 `run-hadolint`（有 Dockerfile 才 true）、`run-zizmor: true`、`run-dotnet`；原本靠預設值而沒寫 `run-python` 的，會依偵測結果寫明 |
| `uses:` 的 ref | 更新成 `--ref` | 這才是真正生效的那一行。行尾有空白或註解也認得；只動指向 `ci-reusable` / `security-reusable` 的那行 |
| CRLF 換行 | 統一成 LF | 兩支腳本的產出才會一致 |
| **job id（`ci` / `security`）** | **絕不更動** | 分支保護的 check 名稱綁著它，改了 ruleset 就對不上 |

「公版有哪些 input」是**直接讀公版 reusable 的 `workflow_call.inputs` 宣告**得來的，
不是腳本裡寫死一份清單 —— 公版加減 input 時自動跟上，不會漂移。
讀不到那份宣告（公版 clone 不完整、格式變了）時**腳本會中止**，不會把你 `with:` 的設定全部當成已廢除刪掉。

#### v1 → v2 的觸發條件修補

1.4.0 的範本修了「PR 改 base 就能繞過來源分支政策」，`ci.yml` 要改三行：`pull_request.types` 加 `edited`、
job 的 `if` 與 `concurrency` 跟著改（只改標題 / 內文的 edited 不重跑、也不取消正在跑的那一輪）。
1.4.0 的 adopt 不會幫既有專案改這三行；2.0.0 起升級時會處理：

- 你的 `ci.yml` 這三行**還是 v1 範本原樣** → 腳本自動換掉，報告裡「觸發條件（v2）」那行會寫出來
- 用 **1.4.0 範本**導入的 → 本來就是新寫法，不會再動
- **改過**其中任何一行 → 不動，只印 ⚠️ 提醒，請照 `templates/consumer-repo/.github/workflows/ci.yml` 手動補

三行要嘛一起換、要嘛都不動，不會只改一半。

`security.yml` 的 `concurrency` 若還是 v1 範本那行（`group: security-${{ github.ref }}`），也會換成依事件分組的寫法，
讓每週排程重掃跟 push 不再互相取消；改過的同樣不動。

#### 2. 絕不覆蓋的檔案

這三個含專案專屬內容，已存在時腳本只放一份 `.new` 給你比對：

- `pull_request_template.md` ← 你可能加過自己的檢查項
- `dependabot.yml` ← 你可能加過 npm 區塊、改過排程
- `zizmor.yml` ← 你會在裡面放自己的放行規則（不存在時會建立，`--uses-repo` 會順手換 owner）

比對完記得把 `.new`（和 `.bak`）刪掉。

### 可重複執行

同樣的指令跑第二次不會產生任何差異（有回歸測試涵蓋）。

---

## 腳本會自動判斷什麼

| 偵測 | 依據 | 影響的參數 |
|---|---|---|
| Dockerfile | 全 repo 任何一層有 `Dockerfile`、`*.Dockerfile`、`Dockerfile.*`（略過 `node_modules`）；有好幾個也照開，公版會逐一 build | `run-docker-build`、`run-hadolint`、`scan-docker-image`（2.0.0 起**不寫 `dockerfile:`** —— 公版留空就會自己找全 repo；你原本寫好的 `dockerfile:` 升級時原樣保留） |
| Python | `requirements.txt` / `pyproject.toml` / `setup.py` / 有 `.py` | `run-python`（2.0.0 起公版預設 `false`，所以一定會明確寫出 `true` 或 `false`） |
| Python 版本 | `.python-version`（UTF-8 BOM 與 CRLF 會去掉），沒有就用 `3.12` | `python-version`（只有 `ci.yml`；`security-reusable` 2.0.0 起已沒有這個 input） |
| .NET | 全 repo 任何一層有 `.sln` / `.slnx` / `.csproj` / `.fsproj` / `.vbproj` | `run-dotnet`。方案檔不只一個（或沒有方案檔、專案檔不只一個）時會提醒你補 `dotnet-project` |
| shell script | 全 repo 任何一層有 `.sh` | `run-shellcheck` |

偵測範圍刻意跟公版 reusable「實際會檢查的範圍」一致：全 repo、不限深度、略過 `.git` 與 `node_modules`，
檔名分大小寫（`api.dockerfile` 不算 —— 公版的 Docker build 也不會去建它）。
範圍比公版小的話，深層的 Dockerfile / `.sh` 會被判成「沒有」，adopt 把開關明寫成 `false`，那項檢查就安靜地關掉了。
Python 例外：只看根目錄的相依清單與兩層內的 `.py`。`adopt.ps1` 的判斷完全相同。
前端（`package.json`）目前**不偵測**，因為公版還沒有 Node 的 CI job —— 安全掃描那邊不用設定就會掃 JS / TS 與 lock 檔，
見 [README — 前端](../README.md#前端react--vue--node)。

`run-actionlint` 與 `run-zizmor` 一律開啟 —— 導入之後你的 repo 就有 workflow 了，
語法跟安全都該檢查；兩個加起來不到一分鐘。

偵測值只在「該 key 原本不存在」時才會寫入 —— 升級既有專案時不會覆寫你調過的設定。

## 回歸測試

`scripts/test-adopt.sh` 涵蓋十一個情境共 79 項檢查（沒裝 PyYAML 的機器會跳過「產生的 YAML 是否合法」那一項），改動腳本後請先跑過：

```bash
./scripts/test-adopt.sh
```

| 情境 | 驗什麼 |
|---|---|
| A 全新導入 | 偵測結果正確寫入（含 `run-hadolint`、`run-zizmor`）、`zizmor.yml` 有建立、`security.yml` 不傳已移除的 `python-version`、不產生多餘的 `.new` |
| A2 全新導入（.NET） | 偵測到 .NET 寫入 `run-dotnet: true`、Dockerfile 在子目錄也找得到、`.python-version` 帶 BOM 時版本號乾淨 |
| B 升級舊版 | 保留使用者參數與 cron、移除廢除的 input（含 `upload-sarif`）、補上新 input、`uses:` ref 更新（行尾有空白／註解也要）、`with:` 裡的空行與註解不會讓區塊提早結束、**job id 不變**、`pull_request_template.md` 未被覆蓋、補上 `zizmor.yml`、改過的觸發條件不被自動改 |
| C 重複執行 | 跑第二次沒有任何 diff |
| G v1 範本升級 | v1 範本原樣的 `ci.yml` 三行觸發條件被換成 v2、`security.yml` 的 concurrency 依事件分組、`uses:` 改指向 `@v2`、CRLF 統一成 LF、再跑一次不會重複改 |
| G' 半套觸發條件 | 使用者只手動加了 `edited`、`if` / concurrency 還是 v1 時，也會補齊 |
| H 讀不到 inputs | 公版 reusable 的 inputs 讀不到時中止，使用者的 `with:` 設定原封不動 |
| I 偵測範圍 | 深層目錄的 Dockerfile / `.sh` 偵測得到、`node_modules` 不算、小寫 `api.dockerfile` 不算、相對路徑呼叫不帶 `--std` 也找得到公版、1.4.0 範本的觸發條件不再被改動 |
| J Dockerfile 不在根目錄 | 子資料夾的 Dockerfile 也會開 Docker 檢查但不寫 `dockerfile:`、升級時保留使用者自己寫的 `dockerfile:`（不會重複一行）、多個 Dockerfile 也照開 |
| D `--dry-run` | 一個檔案都沒動 |
| E `--uses-repo` | 搬到組織時 `owner/repo` 正確替換，`zizmor.yml` 的放行規則也跟著換 —— 新建的、既有的（使用者自己的規則要留著）、另存的 `.new` 都要 |
| F 巢狀結構 | 目標是外層資料夾時，提示往下一層找 |

CI（`adopt-tests.yml`）會在 ubuntu / macOS / Windows 三個平台跑這份測試，Windows 那台還會：
用 **PowerShell 5.1** 載入 `adopt.ps1` 確認 UTF-8 BOM 沒掉，以及真的跑 `adopt.ps1` 與 `adopt.sh`
比對產出 byte-identical（全新導入與一個難搞的升級 fixture 各比一次）。只動文件的 PR 會整個跳過（macOS runner 算 10 倍分鐘）；
`templates/` 底下的 `.md` 不算文件，因為它們會被原樣複製到專案裡。

### ⚠️ 一定要在 macOS 上也跑一次

**Linux 全過不代表 macOS 會過。** macOS 的預設環境跟 CI 差很多：

| | Linux / CI / 雲端 session | macOS 預設 |
|---|---|---|
| bash | 5.x | **3.2.57**（2007 年，因授權問題不再更新） |
| awk | GNU awk | **BWK awk**（BSD 系） |

1.2.2 修的兩個 bug 都只在 macOS 重現，而 Linux 上全過：

- bash 3.2 在 UTF-8 locale 下會把全形標點的首位元組**吃進變數名**
  （`"$STD（ref…"` → 變數 `STD\xef`），配上 `set -u` 直接中止。
  寫中文訊息時，`$VAR` 後面接非 ASCII 一律用 `${VAR}`。
- BSD awk **不接受 `-v` 的值裡有換行**（GNU awk 容忍）。多行字串改走
  `ENVIRON[]`。腳本有 `set -euo pipefail`，所以 awk 一失敗就當場中止、
  後面的 `mv` 不會執行 —— **原檔完好**，只會留下 0 bytes 的 `.tmp`。
  症狀是導入跑到一半停掉，不是檔案被寫壞。

---

## 內網 / 受限環境的注意事項

| 狀況 | 對策 |
|---|---|
| **SSH（22 埠）被擋** | 全程用 HTTPS remote。腳本不用 SSH |
| **裝不了新工具** | 只需要 git，不需要任何額外安裝 |
| **Proxy 需要認證** | 腳本自己不連網。要讓它 clone 公版的話，沿用既有的 `git config --global http.proxy` |
| **完全離線** | 先在有網路的機器 clone 一份 ci-standards，用隨身碟／內部檔案伺服器帶過去，再用 `--std` 指過去 |
| **內部 GitHub Enterprise** | 用 `--std` 指向內部鏡像的 clone；範本裡的 `uses:` 網址記得一起改 |
| **`.ps1` 被群組原則擋** | `powershell -ExecutionPolicy Bypass -File ...`；再不行就用 Git Bash 跑 `.sh` |

### ⚠️ Windows 最容易踩的雷：CRLF

Git for Windows 預設 `core.autocrlf=true`，簽出時會把 LF 換成 CRLF。
對 shell script 是致命的：

```
bash: ./adopt.sh: /usr/bin/env: bad interpreter: No such file or directory
```

錯誤訊息完全看不出原因（`\r` 不會顯示在畫面上）。

本 repo 已經用 [`.gitattributes`](../.gitattributes) 強制 `.sh` / `.yml` / `.ps1`
以 **LF** 簽出，所以直接 clone 本 repo 不會有這個問題。

**但如果你把腳本用複製貼上、email 附件、或 Windows 記事本另存的方式搬過去，就可能中招。**
中了的話：

```bash
# 檢查
file scripts/adopt.sh          # 出現 "CRLF line terminators" 就是中了

# 修
sed -i 's/\r$//' scripts/adopt.sh      # Linux / Git Bash
```

導入到**你自己的專案**之後，也建議在那個專案放一份 `.gitattributes`
（可以直接抄本 repo 的），否則 Windows 同事簽出後一樣會踩到。

### ⚠️ `adopt.ps1` 必須存成 UTF-8 **有** BOM

Windows PowerShell 5.1 讀 `.ps1` 沒看到 BOM 就用 ANSI codepage（繁中 = cp950）解讀，
中文全變亂碼、連 parse 都過不了。pwsh 7 沒這個問題，所以很容易一直沒發現。
用記事本以外的編輯器另存時要注意編碼選項；CI 的 Windows job 會檢查 BOM 還在不在。

---

## 導入之後

腳本跑完會把後續步驟印在畫面上。重點：

1. 檢查 `git diff --stat`
2. 開 PR（瀏覽器就行）
3. **等第一次 CI 跑完再開分支保護** —— check 名稱要先存在於 GitHub，否則 ruleset 對不上。
   設不了（Free 方案的 private repo、公司統一管制）就跳過，見 [README — 沒辦法設分支保護時](../README.md#沒辦法設分支保護時)
4. 從 v1 升上來的專案：刪掉 `copilot-*` 呼叫端、看報告裡「觸發條件（v2）」那行，見 [README — 從 v1 升級到 v2](../README.md#從-v1-升級到-v2)
5. 第一次一定會有東西紅，那是掃描器真的找到問題。**不要為了讓它變綠就關掉檢查**
6. zizmor 挑到你自己寫的 workflow 的毛病（沒釘 SHA、權限太大）多半是真的該修；確定是誤判才放進 `.github/zizmor.yml`

完整說明見 [README — 5 分鐘導入](../README.md#5-分鐘導入一個新專案)。
