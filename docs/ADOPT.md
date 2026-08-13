# 一鍵導入（跨平台）

把公版導入一個專案，用 `scripts/` 底下的腳本，一行搞定。

| 你的環境 | 用哪一支 |
|---|---|
| macOS / Linux | `scripts/adopt.sh` |
| **Windows（PowerShell）** | `scripts/adopt.ps1` ← 內建就有，不用裝東西 |
| Windows（Git Bash） | `scripts/adopt.sh` 也可以 |

兩支功能完全相同。

---

## 需要裝什麼？—— 只有 git

這是刻意的設計取捨。腳本**不使用** `gh`、`jq`、`yq`、`python`、`curl`，
因為在受管制的公司環境裡那些都不保證裝得起來。

導入這一步是**純檔案操作**：複製一個資料夾 + 改兩個 YAML 值。
不需要網路（除非要讓腳本自己去抓公版）。

### 到底哪些步驟需要 `gh`？

| 階段 | 需要 | 沒有 `gh` 的替代 |
|---|---|---|
| **導入（複製範本 + 改參數）** | 檔案操作 | — 本來就不需要 |
| 推分支 | `git`（HTTPS 443） | — |
| 開 PR | — | **瀏覽器開就好** |
| 設分支保護 | GitHub API | 瀏覽器手動建 ruleset，或**組織層級 ruleset 一次涵蓋所有 repo** |

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
| `--ref <tag>` | `-Ref <tag>` | 要指向的公版版本（預設 `v1`） |
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
| 純薄殼 | `copilot-autofix-ci-security.yml`、`copilot-autofix-review.yml`、`copilot-autoreview-gate.yml` | **整份換新**（只搬回你的旋鈕，舊檔留 `.bak`） |
| 專案專屬 | `copilot-instructions.md` 等四個 | **絕不覆蓋**（只放一份 `.new`） |

#### 1. 帶專案設定的：就地合併

| 情況 | 行為 | 為什麼 |
|---|---|---|
| 你調過的參數（`severity`、`fail-on-findings`、`python-version`…） | **保留原值** | 那是你針對這個專案的決定，偵測結果不該蓋過去 |
| 你自訂的 `on:` 觸發（例如改過的 cron） | **完全不動** | 只改 `uses:` 那一行與 `with:` 區塊，其餘原樣 |
| `with:` 裡的註解 | **保留** | `# max-attempts: "3"` 這種提示不該消失 |
| 公版**已廢除**的 input | **移除並回報** | 留著會讓 workflow 直接 `invalid input` 起不來 |
| 公版**新增**的 input | 補上（用偵測值） | 只補「你檔案裡沒有」的，不覆寫既有的 |
| `uses:` 的 ref | 更新成 `--ref` | 這才是真正生效的那一行 |
| **job id（`ci` / `security`）** | **絕不更動** | 分支保護的 check 名稱綁著它，改了 ruleset 就對不上 |

「公版有哪些 input」是**直接讀公版 reusable 的 `workflow_call.inputs` 宣告**得來的，
不是腳本裡寫死一份清單 —— 公版加減 input 時自動跟上，不會漂移。

#### 2. 純薄殼的：整份換新

三支 `copilot-*` 薄殼裡，`if:` 條件、`with:` 的事件接線、`secrets:` 區塊
**全部屬於公版契約**，不是你的設定。你能調的只有註解裡標出來的那幾個旋鈕
（`max-attempts`、`max-review-requests`）。所以升級時整份換成新範本，
只把「你有設、而範本沒設」的旋鈕搬回來，舊檔留成 `.bak`。

**為什麼不能跟第 1 類一樣就地合併？** 因為就地合併只碰 `with:`。
1.2.0 改的是 `if:` 與 `secrets:`：

- `if:` 要多收 Copilot 的 `COMMENTED` review（Copilot 永遠不送 `changes_requested`）
- `secrets: copilot-trigger-pat` 要把真人 PAT 傳進公版（`github-actions[bot]` 發的
  `@copilot` mention 會被 coding agent 忽略）

只合併 `with:` 的話，舊 consumer 升級後會拿到新的 `uses:` 卻留著舊的 `if:`
和缺席的 `secrets:` —— **版本號變了、自動修迴圈還是壞的，而且 CI 全綠沒有訊號**。

> 換新會蓋掉你自己加在薄殼裡的東西（額外的 job、改過的 `permissions`）。
> 那些不常見，但真的有的話 `.bak` 裡找得回來 —— 確認完再刪。

#### 3. 絕不覆蓋的檔案

這四個含專案專屬內容，已存在時腳本只放一份 `.new` 給你比對：

- `copilot-instructions.md` ← **最重要**，是你手寫的專案規範
- `copilot-setup-steps.yml` ← 專案的環境準備步驟
- `pull_request_template.md`
- `dependabot.yml` ← 你可能加過 npm 區塊、改過排程

比對完記得把 `.new`（和 `.bak`）刪掉。

### 冪等

同樣的指令跑第二次不會產生任何差異（有回歸測試涵蓋）。

---

## 腳本會自動判斷什麼

| 偵測 | 依據 | 影響的參數 |
|---|---|---|
| Dockerfile | 根目錄有 `Dockerfile` | `run-docker-build`、`scan-docker-image` |
| Python | `requirements.txt` / `pyproject.toml` / `setup.py` / 有 `.py` | `run-python` |
| Python 版本 | `.python-version`，沒有就用 `3.12` | `python-version` |
| shell script | 專案裡有 `.sh` | `run-shellcheck` |

`run-actionlint` 一律開啟 —— 導入之後你的 repo 就有 workflow 了，
而 actionlint 的 image 內建 shellcheck，會連 `run:` 區塊的 bash 一起檢查，很划算。

偵測值只在「該 key 原本不存在」時才會寫入 —— 升級既有專案時不會覆寫你調過的設定。

## 回歸測試

`scripts/test-adopt.sh` 涵蓋六個情境共 43 項檢查，改動腳本後請先跑過：

```bash
./scripts/test-adopt.sh
```

| 情境 | 驗什麼 |
|---|---|
| A 全新導入 | 偵測結果正確寫入、不產生多餘的 `.new` |
| B 升級舊版 | 保留使用者參數與 cron、移除廢除的 input、補上新 input、`uses:` ref 更新、**job id 不變**、`copilot-instructions.md` 未被覆蓋、三支薄殼整份換新且旋鈕搬回 |
| C 冪等 | 跑第二次沒有任何 diff |
| D `--dry-run` | 一個檔案都沒動 |
| E `--uses-repo` | 搬到組織時 `owner/repo` 正確替換 |
| F 巢狀結構 | 目標是外層資料夾時，提示往下一層找 |

### ⚠️ 一定要在 macOS 上也跑一次

**Linux 全過不代表 macOS 會過。** macOS 的預設環境跟 CI 差很多：

| | Linux / CI / 雲端 session | macOS 預設 |
|---|---|---|
| bash | 5.x | **3.2.57**（2007 年，因授權問題不再更新） |
| awk | GNU awk | **BWK awk**（BSD 系） |

1.2.2 修的兩個 bug 都只在 macOS 重現，而 Linux 上 43 項全過：

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

### ⚠️ Windows 最容易踩的坑：CRLF

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

---

## 導入之後

腳本跑完會把後續步驟印在畫面上。重點：

1. **⚠️ 一定要改 `.github/copilot-instructions.md`** —— 這是導入後最常見的失敗原因
2. 檢查 `git diff --stat`
3. 開 PR（瀏覽器就行）
4. **等第一次 CI 跑完再開分支保護** —— check 名稱要先存在於 GitHub，否則 ruleset 對不上
5. 第一次一定會有東西紅，那是掃描器真的找到問題。**不要為了讓它變綠就關掉檢查**

完整說明見 [README — 5 分鐘導入](../README.md#5-分鐘導入一個新專案)。
