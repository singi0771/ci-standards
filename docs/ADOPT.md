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

## 腳本會自動判斷什麼

| 偵測 | 依據 | 影響的參數 |
|---|---|---|
| Dockerfile | 根目錄有 `Dockerfile` | `run-docker-build`、`scan-docker-image` |
| Python | `requirements.txt` / `pyproject.toml` / `setup.py` / 有 `.py` | `run-python` |
| Python 版本 | `.python-version`，沒有就用 `3.12` | `python-version` |
| shell script | 專案裡有 `.sh` | `run-shellcheck` |

`run-actionlint` 一律開啟 —— 導入之後你的 repo 就有 workflow 了，
而 actionlint 的 image 內建 shellcheck，會連 `run:` 區塊的 bash 一起檢查，很划算。

已存在的 `.github/workflows` 會先**備份**成 `.github/workflows.backup-N`，不會直接覆蓋。

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
