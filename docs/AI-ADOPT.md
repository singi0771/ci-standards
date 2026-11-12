# 以 AI 導入 ci-standards

本文件供 AI 代理（Claude Code、GitHub Copilot 等）導入公版時依序執行。人工導入見 [README — 導入](../README.md#導入)。
除標示「選配」者外，每一步皆須完成；無法完成的步驟須在回報中列出。

## 1. 前置檢查

```bash
git status --porcelain                         # 須無未提交變更
git remote -v                                  # 須有 GitHub origin
gh repo view <owner/repo> --json viewerPermission,hasIssuesEnabled,defaultBranchRef
```

| 結果 | 處理 |
|---|---|
| `viewerPermission` 非 `WRITE`／`MAINTAIN`／`ADMIN` | 帳號錯誤或權限不足，停止並告知使用者 |
| `hasIssuesEnabled` 為 `false` | 告知使用者啟用 Issues（Settings → General → Features）。未啟用時 Branch Guard 無法開 Issue，違規不會通知任何人 |
| 已有 `.github/workflows/ci.yml` 呼叫公版 | 屬升級，見第 9 節 |

## 2. 向使用者確認三項設定

不得自行假設，須取得使用者答覆：

| 設定 | 參數 | 說明 |
|---|---|---|
| 通知對象 | `--notify` / `-Notify` | **必填**。Branch Guard 偵測到直接 push、強制 push、Gate 未通過即 merge 時，指派並通知的 GitHub 帳號或 team，例如 `@alice @acme/platform-team`。通常為專案負責人 |
| 分支流程 | `--flow` / `-Flow` | `develop`（功能分支 → develop → 正式分支）或 `trunk`（功能分支 → 正式分支）。未指定時，有 develop 分支即視為 `develop`。團隊專案建議 `develop` |
| 正式分支 | `--prod` / `-Prod` | 未指定時依序取 origin/HEAD、`main`、`master`。腳本會印出偵測結果，須與使用者確認 |

## 3. 建立 develop 分支（`develop` 流程且尚無此分支時）

```bash
git branch develop origin/<正式分支>
git push -u origin develop
```

## 4. 執行導入腳本

於功能分支（`develop` 流程從 develop 開出）在專案根目錄執行，先以 dry-run 確認偵測結果：

```powershell
Invoke-WebRequest -UseBasicParsing https://raw.githubusercontent.com/singi0771/ci-standards/v2/scripts/adopt.ps1 -OutFile $env:TEMP\adopt.ps1
powershell -ExecutionPolicy Bypass -File $env:TEMP\adopt.ps1 -Notify "@帳號" -Flow develop -DryRun
powershell -ExecutionPolicy Bypass -File $env:TEMP\adopt.ps1 -Notify "@帳號" -Flow develop
```

```bash
curl -fsSL https://raw.githubusercontent.com/singi0771/ci-standards/v2/scripts/adopt.sh -o /tmp/adopt.sh
bash /tmp/adopt.sh --notify "@帳號" --flow develop --dry-run
bash /tmp/adopt.sh --notify "@帳號" --flow develop
```

不要自行從 `templates/` 複製檔案。腳本依偵測結果設定下列項目：

| 檔案 | 內容 |
|---|---|
| `ci.yml`、`security.yml` | `run-*` 開關；`develop` 流程另設來源分支政策（正式分支只收 develop、`hotfix/*` 的 PR） |
| `branch-guard.yml` | `notify`；守護分支為正式分支，`develop` 流程另加 develop |
| `dependabot.yml` | 只列專案實際使用的生態系；`develop` 流程每一項設 `target-branch: "develop"` |
| `zizmor.yml`、`pull_request_template.md` | 範本 |

## 5. 檢查腳本輸出

| 輸出 | 處理 |
|---|---|
| `*.new` 檔案 | 與既有檔案比對，採用需要的段落後刪除 `.new`，不得提交 |
| 「在 vX 不存在」的 input | workflow 會 `startup_failure`，Gate 永遠不回報。移除該 input |
| 「觸發條件不是範本原樣」 | 對照 `templates/consumer-repo/.github/workflows/ci.yml` 手動修改。設有來源分支政策時必須處理 |
| Copilot 呼叫端殘留 | 依輸出的 `git rm` 指令刪除 |
| 多個 .NET 方案／專案檔 | 於 `ci.yml` 的 `with:` 加 `dotnet-project`。只有一個方案檔時（含 `docker-compose.dcproj` 的方案亦同）維持空白，勿改指單一專案檔 |
| `.editorconfig` 與 `.gitattributes` 換行不一致 | 依提示於 `.gitattributes` 加 `*.cs text eol=<值>`，執行 `git add --renormalize .` 後一併提交（見 README「dotnet format 回報 ENDOFLINE」） |

## 6. 開 PR 與處理首次掃描

1. 提交 `.github/` 變更，PR 發往 develop（`trunk` 流程發往正式分支）。
2. 等待 `ci / CI Gate`、`security / Security Gate`。
3. 失敗時依 [README — 疑難排解](../README.md#疑難排解)、[誤判抑制](../README.md#誤判抑制) 處理，將原因與修法告知使用者後修在同一個 PR。
   **不得**關閉或刪除掃描 job、以 `.semgrepignore` 排除主要程式檔等方式讓 Gate 轉綠。

## 7. 合併規則

須告知使用者，並寫入專案的貢獻說明（如有）：

- develop → 正式分支以 **merge commit** 合併，不使用 squash。squash 會使兩分支歷史分岔，之後發版 PR 衝突，衝突中的 PR 不觸發 CI／Security。
- 不開啟「Automatically delete head branches」。發版 PR 合併後會刪除 develop。
- Gate 未通過不得合併。無法設定分支保護的 repo 由 Branch Guard 事後開 Issue。

### 選配：合併後刪除來源分支

不開自動刪除時，已合併的分支會留在遠端。詢問使用者是否由 AI 代理於合併後刪除；採用時：

- `develop` 與正式分支一律不刪；`hotfix/*` 合回 develop 後才刪。
- 來源分支非 develop／正式分支時，以 `gh pr merge <n> --merge --delete-branch` 合併。
  發版 PR（develop → 正式分支）**不得**加 `--delete-branch`，否則 develop 會被刪除。
- 本機分支以 `git branch -d` 刪除（未合併者會被拒絕），不使用 `-D`。
- 既有殘留分支：以下指令列出已合併者，經使用者確認後以 `git push origin --delete <分支>` 刪除。
  ```bash
  git fetch --prune
  git branch -r --merged origin/<正式分支> | grep -vE 'origin/(HEAD|develop|<正式分支>)$'
  ```

## 8. 選配：自動 release tag

正式分支每收到一次 push（發版 PR、hotfix），自動打 tag 並建立 GitHub Release。詢問使用者是否需要；需要時：

1. 複製 [`templates/optional/release-tag/.github/`](../templates/optional/release-tag/.github) 至專案 `.github/`。
2. 將 `release-tag.yml` 的 `branches: [main]` 改為正式分支。
3. 發版 PR 標題以 `release: vX.Y.Z <摘要>` 或 `release: YYYY-MM-DD <摘要>` 開頭，tag 依此產生；其他標題以當日日期為 tag。

## 9. 升級（已導入，更換版本）

```bash
bash /tmp/adopt.sh --ref v2 --flow develop      # 既有 branch-guard.yml 的 notify 已有值時可省略 --notify
```

先閱讀 [CHANGELOG](../CHANGELOG.md) 自目前版本起各版的「需要專案動作」，逐項告知使用者。
既有設定值、`on:` 觸發條件、專案專屬檔案皆保留；其餘依第 5、6 節處理。

## 10. 回報

完成後向使用者回報：

- [ ] 新增與修改的檔案、偵測到的技術
- [ ] 分支流程、正式分支、Branch Guard 通知對象
- [ ] repo 是否已啟用 Issues
- [ ] 兩個 Gate 的結果與處理過的掃描項目
- [ ] 需使用者以 admin 權限處理的項目（分支保護、Issues）
- [ ] 是否啟用自動 release tag
- [ ] 是否採用合併後刪除來源分支，及已刪除的分支
- [ ] 建議使用者於本 repo 設定 **Watch → Custom → Releases**，以收到公版更新通知
