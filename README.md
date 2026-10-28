# ci-standards

團隊共用的 GitHub Actions CI 與安全掃描公版。各專案以 `uses: singi0771/ci-standards/...@v2` 呼叫本 repo 的 reusable workflow，
掃描邏輯、工具版本與規則集中維護於本 repo；公版更新並移動 `v2` tag 後，所有呼叫端自動套用。

- 支援私有 repo，全部使用開源工具，不需要 GitHub Advanced Security。
- 安全掃描：Semgrep、OSV-Scanner、Trivy、gitleaks、zizmor。
- CI：Python（ruff、pytest）、.NET（format、build、test）、Docker build 與 hadolint、actionlint、shellcheck、PR 來源分支政策。
- Branch Guard：main 收到直接 push、強制 push，或 Gate 未通過即 merge 時，開 Issue 通知指定人員。
- 每條線各有一個總結 job（`Security Gate`、`CI Gate`），分支保護只需設定這兩個 required check。

導入前請先閱讀 [已知限制](docs/KNOWN-LIMITATIONS.md)。

---

## 目錄

1. [架構](#架構)
2. [導入](#導入)
3. [升級](#升級)
4. [參數](#參數)
5. [分支保護](#分支保護)
6. [分支模型](#分支模型)
7. [情境設定](#情境設定)
8. [疑難排解](#疑難排解)
9. [Actions 用量](#actions-用量)
10. [版本策略](#版本策略)
11. [檔案結構](#檔案結構)
12. [涵蓋範圍](#涵蓋範圍)
13. [相關文件](#相關文件)

---

## 架構

```
專案 repo                               ci-standards
─────────────────                       ────────────────────────
.github/workflows/security.yml  ──uses──▶ security-reusable.yml
                                           ├─ Semgrep          程式碼弱點（SAST）
                                           ├─ OSV-Scanner      相依套件 CVE
                                           ├─ Trivy            檔案系統 / IaC / Dockerfile 設定，可選 SBOM
                                           ├─ gitleaks         密鑰外洩（含 git 歷史）
                                           ├─ zizmor           workflow 安全                    （選用）
                                           ├─ Trivy image      Docker image CVE                 （選用）
                                           └─ Security Gate

.github/workflows/ci.yml        ──uses──▶ ci-reusable.yml
                                           ├─ Python           ruff、pytest                     （選用）
                                           ├─ .NET             dotnet format / build / test     （選用）
                                           ├─ Docker build     含 hadolint                      （選用）
                                           ├─ Lint             actionlint、shellcheck           （選用）
                                           ├─ PR 來源分支政策                                    （選用）
                                           └─ CI Gate
```

**Gate 判定規則**：子 job 有啟用就必須 `success`；未啟用的 `skipped` 不影響結果。Gate 以 `if: always()` 執行。

只把 Gate 設為 required check 的原因：

- 公版增減工具時，各專案的 ruleset 不需調整。
- 有 `if` 條件的 job 停用時為 `skipped`，若直接設為 required check，GitHub 會視為通過或永遠 pending。

公版只負責偵測與阻擋，不會修改專案程式碼。

---

## 導入

導入內容為專案 `.github/` 下的兩支呼叫端 workflow 與三個設定檔，不需要 clone 或 fork 本 repo。

### 前置需求

| 項目 | 需求 |
|---|---|
| 工具 | `git`。Windows 使用內建 PowerShell 5.1；macOS / Linux 需要 `bash`、`curl` |
| 權限 | 目標 repo 的寫入權限（推分支、開 PR）。設定分支保護需要 admin |
| 網路 | 可連 `github.com`、`raw.githubusercontent.com`（HTTPS 443）。內網、離線環境見 [`docs/ADOPT.md`](docs/ADOPT.md) |

### 執行導入腳本

在**專案根目錄**執行。第一行下載腳本至暫存目錄，第二行執行。

**Windows（PowerShell）**

```powershell
Invoke-WebRequest -UseBasicParsing https://raw.githubusercontent.com/singi0771/ci-standards/v2/scripts/adopt.ps1 -OutFile $env:TEMP\adopt.ps1
powershell -ExecutionPolicy Bypass -File $env:TEMP\adopt.ps1 -Notify "@帳號 @組織/team"
```

**macOS / Linux / Git Bash**

```bash
curl -fsSL https://raw.githubusercontent.com/singi0771/ci-standards/v2/scripts/adopt.sh -o /tmp/adopt.sh
bash /tmp/adopt.sh --notify "@帳號 @組織/team"
```

- `-Notify` / `--notify` 指定 [Branch Guard](#branch-guard) 的通知對象，於導入時決定。未指定則不建立 `branch-guard.yml`。
- 加上 `-DryRun`（PowerShell）或 `--dry-run`（bash）只列出偵測結果與預計變更，不寫入檔案。
- `-ExecutionPolicy Bypass` 只作用於該次執行，不變更系統設定。
- 腳本會以 HTTPS 淺層 clone 公版範本至暫存目錄，結束後自動刪除。

腳本行為：

| 項目 | 行為 |
|---|---|
| 技術偵測 | 偵測 Python、.NET、Dockerfile、shell script，寫入對應的 `run-*` 參數 |
| `workflows/ci.yml`、`workflows/security.yml` | 不存在則新增；已存在則升級：`uses:` 改為 `@v2`、移除已廢除的 input、補上新 input，既有設定值保留 |
| `workflows/branch-guard.yml` | 有指定通知對象才新增，`notify` 寫入正規化後的名單；已存在則依上列規則升級，既有 `notify` 保留 |
| `zizmor.yml`、`dependabot.yml`、`pull_request_template.md` | 不存在則新增；已存在則不覆蓋，另存 `.new` 供比對 |
| 其他 | 不刪除檔案、不 commit、不推送 |

參數：

| bash | PowerShell | 說明 |
|---|---|---|
| `--target <dir>` | `-Target <dir>` | 目標專案目錄，預設為目前目錄 |
| `--ref <tag>` | `-Ref <tag>` | 呼叫端指向的公版版本，預設 `v2` |
| `--std <path>` | `-Std <path>` | 使用本機既有的公版 clone，不另行下載 |
| `--uses-repo <owner/repo>` | `-UsesRepo <owner/repo>` | 公版遷移至組織後，替換 `uses:` 的 owner/repo |
| `--notify "<名單>"` | `-Notify "<名單>"` | Branch Guard 通知對象：GitHub 帳號或 team，空白或逗號分隔，`@` 可省略。格式不符時中止 |
| `--dry-run` | `-DryRun` | 僅預覽 |

### 後續步驟

1. **檢查變更**：`git diff`。確認 `run-*` 參數與專案實際技術一致（設定說明見[參數](#參數)）。
   若有 `.new` 檔，比對後合併需要的內容並刪除 `.new`。
2. **開 PR**：

   ```bash
   git checkout -b chore/adopt-ci-standards
   git add .github
   git commit -m "chore: 導入 ci-standards"
   git push -u origin chore/adopt-ci-standards
   ```

   於 GitHub 建立 PR。草稿 PR 不會觸發檢查，標記為 Ready for review 後才執行。
3. **處理首次結果**：首次執行通常會有掃描結果。於 Actions → 該 run → Summary 查看失敗項目，
   依[疑難排解](#疑難排解)與[誤判抑制](#誤判抑制)處理。發現項目過多時可先以 `fail-on-findings: false` 過渡，見[導入過渡期](#導入過渡期)。
4. **設定分支保護**：兩個 Gate 至少執行過一次後，見[分支保護](#分支保護)。無法設定時見[無法設定分支保護時](#無法設定分支保護時)。

採用 develop 流程（功能分支 → develop → main）時，另需設定來源分支政策，見[分支模型](#分支模型)。

### 導入檢查清單

- [ ] `ci.yml`、`security.yml` 的 `uses:` 指向 `singi0771/ci-standards/...@v2`
- [ ] `run-python`、`run-dotnet`、`run-docker-build`、`scan-docker-image` 與專案技術一致
- [ ] 呼叫端的 `pull_request` 未設定 `paths-ignore`
- [ ] job id 維持 `ci`、`security`
- [ ] 無殘留 `.new` 檔
- [ ] PR 上 `ci / CI Gate`、`security / Security Gate` 皆通過
- [ ] 已設定分支保護，或已於 `CONTRIBUTING.md` / PR 範本註明「兩個 Gate 通過後才可 merge」
- [ ] `branch-guard.yml` 的 `notify` 為實際負責人；repo 已啟用 Issues

### 呼叫端範例

導入腳本產生的檔案如下，手動導入時可複製 [`templates/consumer-repo/.github/`](templates/consumer-repo/.github) 後依此調整：

```yaml
# .github/workflows/ci.yml（節錄）
jobs:
  ci:                              # job id 不可變更，check 名稱為 "ci / CI Gate"
    uses: singi0771/ci-standards/.github/workflows/ci-reusable.yml@v2
    with:
      run-python: true
      python-version: "3.12"
      # run-dotnet: true
      run-docker-build: true
      run-hadolint: true
```

```yaml
# .github/workflows/security.yml（節錄）
jobs:
  security:                        # job id 不可變更，check 名稱為 "security / Security Gate"
    uses: singi0771/ci-standards/.github/workflows/security-reusable.yml@v2
    with:
      severity: "CRITICAL,HIGH"
      fail-on-findings: true
      scan-docker-image: false
      run-zizmor: true
```

| 檔案 | 用途 |
|---|---|
| `workflows/ci.yml` | 呼叫 CI 公版 |
| `workflows/security.yml` | 呼叫安全掃描公版；每週一 03:00 UTC 另有排程重掃 |
| `zizmor.yml` | zizmor 放行規則（已放行指向公版的版本 tag） |
| `dependabot.yml` | pip 每週；docker、github-actions 每月。`nuget`、`npm` 範例在檔尾註解 |
| `pull_request_template.md` | PR 檢查清單 |

---

## 升級

### 同一主版本內

不需任何動作。`v2` tag 移動後，下次執行即套用新版。新增的 input 皆有預設值；需要使用新參數時重新執行導入腳本即可。

### 從 v1 升級到 v2

2.0.0 的破壞性變更（完整內容見 [CHANGELOG](CHANGELOG.md)）：

| 變更 | 影響 |
|---|---|
| `ci-reusable` 的 `run-python` 預設改為 `false` | 未明確設定的 Python 專案不再執行 ruff / pytest |
| `security-reusable` 移除 `python-version`、`upload-sarif` | 呼叫端仍傳入時 workflow 無法啟動（`invalid input`） |
| `fail-on-findings: false` 不再忽略掃描工具本身的錯誤 | 規則或弱點資料庫下載失敗、工具異常時 Gate 為失敗 |
| `dockerfile` 預設改為空字串（自動搜尋全 repo） | 子目錄的 Dockerfile 也會被 build 與掃描 |
| 移除 Copilot 自動修正 / 自動審查 workflow | 專案內殘留的 `copilot-*` 呼叫端會 `startup_failure` |

升級步驟：

1. 刪除 Copilot 呼叫端（導入腳本不刪除既有檔案）：

   ```bash
   git rm .github/workflows/copilot-autofix-ci-security.yml \
          .github/workflows/copilot-autofix-review.yml \
          .github/workflows/copilot-autoreview-gate.yml \
          .github/workflows/copilot-setup-steps.yml
   ```

   repo secret `COPILOT_TRIGGER_PAT` 可一併刪除；`.github/zizmor.yml` 中針對上述檔案的放行規則一併移除。
2. 執行[導入腳本](#執行導入腳本)。腳本會將 `uses:` 改為 `@v2`、移除已廢除的 input、依偵測結果寫入 `run-python` / `run-dotnet`。
3. 檢查腳本輸出的「觸發條件（v2）」：
   - `ci.yml` 為 v1 範本原樣：已自動補上 `edited` 觸發，並更新 job 的 `if` 與 `concurrency`。
   - 顯示「沒有自動改」：觸發條件曾被修改，需依 [`templates/consumer-repo/.github/workflows/ci.yml`](templates/consumer-repo/.github/workflows/ci.yml) 手動調整。設有 `restricted-base-branches` 時必須處理。
4. 確認 Python 專案的 `run-python` 為 `true`。
5. 開 PR，兩個 Gate 通過後 merge。

分支保護不需調整，check 名稱未變更。重新執行 `setup-branch-protection.sh` 可套用 2.0.0 新增的 check 來源綁定。

---

## 參數

### `security-reusable.yml`

| 參數 | 型別 | 預設 | 說明 |
|---|---|---|---|
| `severity` | string | `CRITICAL,HIGH` | Trivy 阻擋的嚴重度 |
| `fail-on-findings` | boolean | `true` | `false` 時發現項目不使 Gate 失敗（導入過渡期使用）。掃描工具本身錯誤、OSV-Scanner 異常結束仍為失敗 |
| `scan-docker-image` | boolean | `false` | build image 並以 Trivy 掃描。每個 image 約增加 2–3 分鐘 |
| `dockerfile` | string | `""` | 同 `ci-reusable` 的 `dockerfile` |
| `docker-context` | string | `"."` | 同 `ci-reusable` 的 `docker-context` |
| `run-zizmor` | boolean | `false` | 以 [zizmor](https://docs.zizmor.sh/) 檢查 `.github/workflows`：腳本注入、危險觸發器、未釘 SHA 的 action、權限過大。放行規則置於 `.github/zizmor.yml` |
| `zizmor-min-severity` | string | `low` | zizmor 回報門檻：`low` / `medium` / `high` |
| `semgrep-rules` | string | `p/owasp-top-ten p/security-audit p/secrets auto` | Semgrep 規則包，以空白分隔。`auto` 依語言選擇規則並會回傳匿名使用統計 |
| `trivy-scanners` | string | `vuln,misconfig` | Trivy 檔案系統掃描項目：`vuln` / `misconfig` / `secret` / `license`。`secret` 預設關閉（gitleaks 已涵蓋） |
| `generate-sbom` | boolean | `false` | 產生 CycloneDX SBOM，存為 artifact `sbom-cyclonedx` |

Semgrep 結果一律存為 artifact `semgrep-sarif`，不上傳 Security 分頁。

### `ci-reusable.yml`

| 參數 | 型別 | 預設 | 說明 |
|---|---|---|---|
| `run-python` | boolean | `false` | 執行 ruff 與 pytest。`pyproject.toml` 含 `[project]` 或 `[build-system]` 時先 `pip install -e .` |
| `python-version` | string | `3.12` | Python 版本 |
| `ruff-version` | string | `0.16.0` | 固定的 ruff 版本。lint 規則由專案的 `pyproject.toml` 設定 |
| `run-dotnet` | boolean | `false` | 執行 `dotnet restore` → `format --verify-no-changes` → `build -c Release` → `test` |
| `dotnet-version` | string | `""` | SDK 版本，多個以換行分隔。空白時依序採用 `global.json`、專案檔的 `TargetFramework(s)`、`10.0.x` |
| `dotnet-project` | string | `""` | `.sln` / `.slnx` / `.csproj` 路徑。空白時自動搜尋；找到兩個以上時失敗 |
| `run-dotnet-format` | boolean | `true` | 執行 `dotnet format --verify-no-changes`（依 `.editorconfig`） |
| `dotnet-runner` | string | `ubuntu-latest` | WPF、WinForms、.NET Framework 專案設為 `windows-latest`（分鐘數 2 倍） |
| `run-docker-build` | boolean | `true` | 驗證 image 可 build（不推送） |
| `dockerfile` | string | `""` | 空白時搜尋全 repo 的 `Dockerfile`、`*.Dockerfile`、`Dockerfile.*`（略過 `node_modules`）。可列多個，以空白分隔，格式為 `路徑` 或 `路徑:context`。明確列出的路徑不存在時失敗 |
| `docker-context` | string | `"."` | 未指定 `:context` 時的 build context |
| `run-hadolint` | boolean | `false` | build 前以 [hadolint](https://github.com/hadolint/hadolint) 檢查 Dockerfile，warning 以上失敗 |
| `run-actionlint` | boolean | `false` | 檢查 workflow 語法，含 `run:` 區塊的 shellcheck |
| `actionlint-paths` | string | `""` | 額外檢查的 workflow glob。`.github/workflows` 一律檢查 |
| `run-shellcheck` | boolean | `false` | 以 shellcheck 檢查 `.sh` |
| `shellcheck-paths` | string | `""` | `.sh` glob。空白時搜尋全 repo |
| `restricted-base-branches` | string | `""` | 受管制的 base 分支，空白分隔、支援 glob。見[來源分支政策](#來源分支政策) |
| `allowed-head-branches` | string | `""` | 允許合併進受管制分支的來源分支。前者有值時必填 |

---

## 分支保護

### 方案限制

私有 repo 的 ruleset 需要 GitHub Pro、Team 以上方案。Free 方案的私有 repo 呼叫 API 會回傳
`403 Upgrade to GitHub Pro or make this repository public to enable this feature.`
無法設定時見[無法設定分支保護時](#無法設定分支保護時)。

### 以腳本設定

需要 `gh` 與目標 repo 的 admin 權限。兩個 Gate 至少執行過一次後再設定。

```bash
curl -fsSL https://raw.githubusercontent.com/singi0771/ci-standards/v2/scripts/setup-branch-protection.sh -o /tmp/setup-branch-protection.sh
bash /tmp/setup-branch-protection.sh <owner>/<repo>                         # 保護 default branch
bash /tmp/setup-branch-protection.sh <owner>/<repo> main develop            # 指定多個分支
bash /tmp/setup-branch-protection.sh <owner>/<repo> main develop --dry-run  # 僅輸出 payload
```

建立的 ruleset 內容：必須經由 PR、對話須解決、`security / Security Gate` 與 `ci / CI Gate` 須通過、禁止 force push 與刪除分支。

| 環境變數 | 預設 | 說明 |
|---|---|---|
| `REQUIRED_APPROVALS` | `0` | 必要核准數。單人團隊設為 1 會導致 PR 無法 merge（作者無法核准自己的 PR，ruleset 預設無 bypass） |
| `STRICT_CHECKS` | `false` | `true` 時要求 PR 分支與目標分支同步後才可 merge |
| `CHECKS_INTEGRATION_ID` | `15368` | required check 限定由 GitHub Actions 回報，防止以 commit status API 偽造。空字串為不限定 |

腳本可重複執行，同名 ruleset 會更新而非新增。

### 手動設定

Settings → Rules → Rulesets → New branch ruleset：

- Enforcement status：**Active**
- Require a pull request before merging（approvals 0，勾選對話須解決）
- Require status checks to pass，來源選 **GitHub Actions**：`security / Security Gate`、`ci / CI Gate`
- Block force pushes、Restrict deletions

check 名稱格式為 `<呼叫端 job id> / <公版 job 名稱>`，須與 Checks 分頁顯示的名稱完全一致。只設定兩個 Gate，不加入個別 job。

### 注意事項

- 呼叫端的 `pull_request` **不可設定 `paths-ignore`**。被過濾的 PR 不會產生 required check，將永遠 pending。
- 建議於 Settings → Billing 將 Actions 的 spending limit 設為 `$0`，詳見 [`docs/SETUP.md`](docs/SETUP.md)。

### 無法設定分支保護時

Free 方案的私有 repo，或由公司統一管理、專案成員無 admin 權限的 repo，仍可導入公版。差異在於 **Gate 失敗無法阻擋 merge**。

| 機制 | 狀態 |
|---|---|
| PR 上的 CI / Security 與 Summary | 正常執行 |
| 來源分支政策 | 正常判定，僅無法阻擋 |
| 每週排程重掃 | 正常執行 |
| [Branch Guard](#branch-guard) | 正常執行：直接 push、強制 push、強制 merge 時開 Issue 通知 |

補強措施：

1. 於 PR 範本與 `CONTRIBUTING.md` 規定「兩個 Gate 通過後才可 merge」。
2. 導入時以 `--notify` 啟用 Branch Guard；收到 Issue 時 `git revert` 該變更，修正後重新發 PR。
3. 限縮具 Write 權限的成員。
4. 需要強制阻擋時，改用付費方案、遷移至組織，或改為 public repo，之後執行分支保護腳本即可，呼叫端不需調整。

### Branch Guard

`branch-guard.yml` 於受保護分支（預設 `main`）收到 push 時執行，判定這次 push 的來源。
分支保護擋不住的操作（無 ruleset 的 repo、admin bypass）由此在事後揭露。

| 情況 | 判定方式 |
|---|---|
| 直接 push | 分支頂端 commit 不是任何「合併進該分支的 PR」的 `merge_commit_sha`。`git push origin develop:main` 亦屬此類 |
| 強制 push | push 事件的 `forced` 為 `true` |
| 強制 merge | 有對應 PR，但合併當下 `required-checks` 中任一 check 不是 `success`（失敗、未完成或未執行）|

偵測到違規時：

1. 開 Issue（label `branch-guard`，不存在時自動建立），內容含違規項目、推送者、commit 與 PR 連結。
2. `notify` 中的個人帳號指派為 Issue 負責人並 @；team 僅 @（GitHub 不能指派 team）。GitHub 依此寄送站內與 email 通知。
3. 該次執行標為失敗。

GitHub 內建的 workflow 失敗通知只寄給觸發者，即違規者本人，因此另以 Issue 通知。

```yaml
on:
  push:
    branches: [main]          # 要守 develop 時改為 [main, develop]；不可加 paths-ignore

jobs:
  guard:
    uses: singi0771/ci-standards/.github/workflows/branch-guard-reusable.yml@v2
    permissions:
      contents: read
      pull-requests: read
      checks: read
      issues: write
    with:
      notify: "@alice @acme/platform-team"
```

| input | 預設 | 說明 |
|---|---|---|
| `notify` | `""` | 通知對象，空白分隔。空白時照常開 Issue 但不通知任何人 |
| `required-checks` | `ci / CI Gate,security / Security Gate` | 合併當下須為 `success` 的 check，應與分支保護的 required check 相同 |
| `label` | `branch-guard` | Issue 的 label |

限制：

- 只能事後揭露，無法阻擋。
- repo 停用 Issues 時無法開 Issue，僅執行結果標為失敗。
- 使用 merge queue 時，required check 執行於 merge group 而非 PR head，會誤判為強制 merge。
- 每次 push 到受保護分支皆執行一次，約耗用 1 分鐘 Actions 額度。

---

## 分支模型

公版不預設分支模型，以下設定皆位於呼叫端。

### 觸發條件

範本的 `ci.yml` 只對 PR 執行（所有 base 分支）；`security.yml` 另有每週排程重掃：

```yaml
on:
  pull_request:
    types: [opened, synchronize, reopened, ready_for_review, edited]
```

合併進 main / develop 後不再重跑：

- PR 檢查的是合併後的結果（`refs/pull/N/merge`），合併後再跑多半是同一份程式碼。
- develop → main 的 PR 會再驗一次 develop 累積的變更。PR 開啟期間 develop 有新 commit 時，PR 收到 `synchronize` 自動重跑，前一輪的結果不再算數。
- 直接 push 與 Gate 未通過即 merge 由 [Branch Guard](#branch-guard) 偵測。

例外：以 Actions 的 `GITHUB_TOKEN` merge 或 push 時，GitHub 不觸發任何 workflow，PR 不會重跑。自動化流程請使用個人或 GitHub App 的 token。

- `on:` 不支援 `${{ }}` 運算式，分支名稱須直接寫入。
- 加上 `pull_request.branches` 篩選後，未列入分支的 PR 不會產生 `ci / CI Gate`，這些分支不可設為 required check。
- `edited` 用於 PR 變更 base 分支時重新判定來源分支政策。僅修改標題或內文的 `edited` 不執行，由 job 的 `if` 與 `concurrency` 控制：

```yaml
concurrency:
  group: ${{ github.event.action == 'edited' && github.event.changes.base == null && format('ci-edit-{0}', github.run_id) || format('ci-{0}', github.ref) }}
  cancel-in-progress: true

jobs:
  ci:
    if: ${{ github.event_name != 'pull_request' || (!github.event.pull_request.draft && (github.event.action != 'edited' || github.event.changes.base != null)) }}
```

### 來源分支政策

限制特定 base 分支只接受指定來源分支的 PR：

```yaml
with:
  restricted-base-branches: "main"
  allowed-head-branches: "develop hotfix/*"
```

判定順序：

1. base 不在 `restricted-base-branches` 內：通過。
2. `allowed-head-branches` 為空：失敗。
3. PR 來自 fork：失敗。
4. head 符合 `allowed-head-branches` 任一樣式：通過；否則失敗。

`*` 會比對 `/`（`hotfix/*` 包含 `hotfix/a/b`）。結果併入 `ci / CI Gate`，不需新增 required check。
此檢查用於防止誤操作，須搭配 ruleset 才能阻擋直接 push 或強制 merge。

### develop 流程設定

```
功能分支 ──PR──▶ develop ──PR──▶ main
```

| 目標 | 設定 |
|---|---|
| develop、main 禁止直接 push、須通過 Gate、禁止 force push 與刪除 | `setup-branch-protection.sh <owner>/<repo> main develop` |
| main 只接受 develop 的 PR | `restricted-base-branches: "main"`、`allowed-head-branches: "develop"` |
| develop 也偵測直接 push | `branch-guard.yml` 的 `on.push.branches: [main, develop]` |
| 新 PR 預設發往 develop | Settings → General → Default branch 設為 `develop` |

分支名稱可自訂，腳本與 input 皆依實際填寫的名稱運作。

---

## 情境設定

### .NET 專案

```yaml
with:
  run-python: false
  run-dotnet: true
  # dotnet-project: "src/App.sln"     # 有兩個以上方案檔或專案檔時必填
  # dotnet-version: "8.0.x"
  # run-dotnet-format: false          # 既有專案格式尚未整理時暫時關閉
  # dotnet-runner: windows-latest     # WPF / WinForms / .NET Framework
```

- 無測試專案時 `dotnet test` 不會失敗。
- 有 `packages.lock.json` 時啟用 NuGet 快取。
- 導入腳本偵測 `.sln`、`.slnx`、`.csproj`、`.fsproj`、`.vbproj`（四層內）。
- 安全掃描不需調整。Dependabot 需依 `dependabot.yml` 檔尾範例加入 `nuget`。

### 非 Python 專案

`security-reusable.yml` 與語言無關。`ci-reusable.yml` 關閉語言相關 job 後仍可使用其他檢查，並產生 `ci / CI Gate`：

```yaml
with:
  run-python: false
  run-docker-build: true
  run-hadolint: true
  run-actionlint: true
  run-shellcheck: true
```

公版未內建的語言檢查，於專案內另建 job，使用不同 job id（例如 `node`），並視需要加入 required check。`ci` job id 不可變更。

### 前端專案

| 項目 | 狀態 |
|---|---|
| Semgrep | 涵蓋 JS / TS。`.vue` 單檔元件支援有限 |
| OSV-Scanner、Trivy | 讀取 `package-lock.json`、`yarn.lock`、`pnpm-lock.yaml` |
| gitleaks | 涵蓋 |
| lint、型別檢查、測試、build | **公版尚未提供**，需於專案內自建 job |

```yaml
  node:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@<commit SHA>
        with:
          persist-credentials: false
      - uses: actions/setup-node@<commit SHA>
        with:
          node-version: "22"
          cache: npm
      - run: npm ci
      - run: npm run lint --if-present
      - run: npm test --if-present
      - run: npm run build --if-present
```

action 須釘選 commit SHA，否則 zizmor 會回報。

### Dockerfile

- 無 Dockerfile：`ci.yml` 設 `run-docker-build: false`，`security.yml` 設 `scan-docker-image: false`。
- 預設自動搜尋全 repo 的 Dockerfile。只檢查部分檔案或指定 build context 時：

```yaml
with:
  dockerfile: "src/Web.Api/Dockerfile web/Dockerfile:web"
  docker-context: "."
```

`ci.yml` 與 `security.yml` 需分別設定。

### 導入過渡期

發現項目過多時先設 `fail-on-findings: false`，分批修正後改回 `true`。此設定不會忽略掃描工具本身的錯誤。

### 誤判抑制

| 工具 | 檔案 | 格式 |
|---|---|---|
| Semgrep | `.semgrepignore` | 路徑 glob，每行一筆 |
| gitleaks | `.gitleaksignore` | `commit:path:rule:line` fingerprint，每行一筆 |
| Trivy | `.trivyignore` | CVE / GHSA ID，每行一筆 |
| zizmor | `.github/zizmor.yml` | `rules.<規則>.ignore`，見 [zizmor 文件](https://docs.zizmor.sh/configuration/) |
| hadolint | `.hadolint.yaml` | `ignored: [DL3008]` |

每筆抑制須於 PR 說明誤判理由。

---

## 疑難排解

| 症狀 | 原因 | 處理 |
|---|---|---|
| Windows 上 `curl` 回報 `CRYPT_E_NO_REVOCATION_CHECK` | 公司網路無法進行憑證撤銷檢查 | 改用 PowerShell 的 `Invoke-WebRequest`，或 `curl --ssl-no-revoke` |
| 導入腳本 clone 失敗 | 內網 proxy | 設定 `git config --global http.proxy`，或以 `-Std` / `--std` 指定本機 clone |
| `workflow was not found` / `not allowed` | 本 repo 為 private 且未開放存取 | 本 repo Settings → Actions → General → Access 開放組織存取 |
| PR 上沒有 `security / Security Gate` | 尚未執行過，或 job id 被修改 | 先完成一次執行，確認 job id |
| `Invalid input, upload-sarif is not defined`（或 `python-version`） | 2.0.0 已移除這兩個 input | 自 `security.yml` 移除，或重新執行導入腳本 |
| 升級後 Python lint / test 未執行 | 2.0.0 起 `run-python` 預設 `false` | 設定 `run-python: true` |
| pytest exit code 5 | 無測試 | 公版視為通過；仍失敗時檢查其他錯誤 |
| OSV-Scanner 失敗 | 相依套件有已知 CVE | 升級套件（通常已有 Dependabot PR） |
| OSV-Scanner `rpc error: Internal` 且弱點數為 0 | deps.dev 服務異常 | 公版會自動改用 `--no-resolve` 重掃；持續失敗時檢查 log 的 `failed resolution` |
| gitleaks 回報已撤銷的 token | 密鑰存在於 git 歷史 | 確認已撤銷後加入 `.gitleaksignore` |
| zizmor `unpinned-uses` | action 使用 tag 而非 SHA | 改釘 commit SHA |
| zizmor `template-injection` | `run:` 直接使用 `${{ github.event.* }}` | 改經由 `env:` 傳入並以 `"$VAR"` 引用 |
| zizmor `dangerous-triggers` | 使用 `pull_request_target` / `workflow_run` | 確認不執行 PR 程式碼後放行，否則改用 `pull_request` |
| zizmor `excessive-permissions` | 未宣告 `permissions:` | 加上 `permissions: contents: read` |
| `sha256sum: WARNING: 1 computed checksum did NOT match` | 上游檔案變更或校驗碼未更新 | 至本 repo 開 Issue |
| `.NET build + test`：找到多個方案 / 專案檔 | 無法自動決定建置目標 | 設定 `dotnet-project` |
| `.NET build + test` format 步驟失敗 | 不符 `.editorconfig` | 本機執行 `dotnet format` 後 commit |
| `.NET build + test` 找不到 WindowsDesktop SDK | 目標為 `net*-windows` 或 .NET Framework | 設定 `dotnet-runner: windows-latest` |
| `fail-on-findings: false` 仍失敗 | 掃描工具本身錯誤或 OSV-Scanner 異常結束 | 檢查 log，多為暫時性網路問題，重新執行 |
| `setup-branch-protection.sh` 回傳 403 | Free 方案私有 repo | 見[無法設定分支保護時](#無法設定分支保護時) |

---

## Actions 用量

私有 repo 依分鐘計費，每個 job 不足一分鐘以一分鐘計；Windows runner 2 倍、macOS 10 倍。

參考值（Python + Docker 私有專案，每次 PR 推送）：CI 4–5 分鐘、Security 5–6 分鐘。

| 公版已採用 | 可自行調整 |
|---|---|
| 草稿 PR 不執行 | `scan-docker-image` 無 Dockerfile 時關閉 |
| 連續推送自動取消前一次執行 | 排程改為每月：`cron: "0 3 1 * *"` |
| 只在 PR 上執行，合併後不重跑 | Billing 將 spending limit 設為 `$0` |
| actionlint 與 shellcheck、hadolint 與 Docker build 合併為同一 job | `dotnet-runner` 非必要不使用 Windows |
| Trivy 預設不掃 secret；Dependabot docker / actions 每月 | |

---

## 版本策略

每次發佈建立兩個 tag：不可變的 `vX.Y.Z` 與可移動的主版本 `vX`。目前主版本為 `v2`。

```bash
git tag -a v2.0.1 -m "..." && git push origin v2.0.1
git tag -f v2 && git push -f origin v2
```

| 變更類型 | 版本 |
|---|---|
| 修正錯誤、調整規則、升級 action、新增有預設值的 input | `v2.x.y`，移動 `v2` |
| 變更或移除 input、變更預設值、變更 job 名稱、移除 workflow | `v3.0.0`，建立 `v3` |

| 主版本 | 狀態 |
|---|---|
| `v2` | 目前版本，新導入使用 |
| `v1` | 僅修正錯誤（最後功能版 1.4.0）。`v1` 不可指向 2.x 的 commit |

- 修改公版後須移動 `v2`，否則呼叫端不會套用。
- 每次發佈須保留 `v2.x.y`，作為 `v2` 移動錯誤時的還原點。
- 未發佈的變更：`git log --oneline v2..main -- .github/workflows templates scripts`
- 發佈程序見 [`docs/HANDOFF.md`](docs/HANDOFF.md) §3；版本紀錄見 [CHANGELOG](CHANGELOG.md)。

---

## 檔案結構

```
ci-standards/
├── .github/
│   ├── workflows/
│   │   ├── ci-reusable.yml          公版：CI
│   │   ├── security-reusable.yml    公版：安全掃描
│   │   ├── branch-guard-reusable.yml 公版：直接 push / 強制 merge 偵測與通知
│   │   ├── ci.yml                   本 repo 的呼叫端（以 ./ 呼叫 ci-reusable.yml）
│   │   ├── security.yml             本 repo 的呼叫端（以 ./ 呼叫 security-reusable.yml）
│   │   ├── branch-guard.yml         本 repo 的呼叫端（以 ./ 呼叫 branch-guard-reusable.yml）
│   │   └── adopt-tests.yml          導入腳本測試（ubuntu / macOS / Windows）
│   ├── zizmor.yml
│   ├── dependabot.yml
│   ├── copilot-instructions.md      本 repo 的修改規範
│   ├── pull_request_template.md
│   ├── ISSUE_TEMPLATE/
│   └── CODEOWNERS
├── scripts/
│   ├── adopt.sh                     導入腳本（bash）
│   ├── adopt.ps1                    導入腳本（PowerShell 5.1，UTF-8 with BOM）
│   ├── setup-branch-protection.sh   分支保護設定（需要 gh）
│   └── test-adopt.sh                導入腳本回歸測試
├── templates/consumer-repo/.github/ 呼叫端範本
├── docs/
├── CHANGELOG.md
├── CONTRIBUTING.md
└── SECURITY.md
```

**呼叫端與範本的一致性**：`ci.yml` / `security.yml` 以 `./` 呼叫同一 commit 的 reusable workflow，修改公版的 PR 即以修改後的版本執行，兩者無需同步。
需要保持一致的是本 repo 呼叫端與 `templates/consumer-repo/` 範本：觸發條件、`permissions`、`concurrency`、job 的 `if` 必須相同；
僅 `uses:`、`with:` 可不同。修改其中一方時須同步修改另一方。

---

## 涵蓋範圍

| 面向 | 工具 | 偵測 | 不偵測 |
|---|---|---|---|
| SAST | Semgrep | SQL injection、eval、不安全的反序列化等寫法 | 執行期邏輯漏洞 |
| 相依套件 CVE | OSV-Scanner、Dependabot | lockfile / manifest 中的已知 CVE | 無 lockfile 時的間接相依 |
| IaC / Dockerfile 設定 | Trivy | root 執行、privileged、對外全開、授權條款 | 執行期設定漂移 |
| 密鑰外洩 | gitleaks | token、密碼、私鑰（含歷史） | 無固定格式的密鑰 |
| workflow 安全 | zizmor | 腳本注入、危險觸發器、未釘 SHA、權限過大 | 外部工具本身的漏洞 |
| Image CVE | Trivy image | OS 與語言套件 CVE | 尚無修正版的 CVE |
| Dockerfile 寫法 | hadolint | 未釘版本、`latest`、shell 問題 | — |
| 程式碼品質 | ruff、pytest、dotnet、actionlint、shellcheck | lint、建置、測試、語法 | Node 專案（尚未提供） |

不涵蓋：WAF、EDR、SIEM、CSPM、執行期偵測、滲透測試、DAST、SBOM 簽章。

私有 repo 免費使用的作法：不使用付費的 code scanning 上傳，以 job 結果與 artifact 取代；gitleaks 以執行檔執行；以 OSV-Scanner 取代 dependency-review-action。

本 repo 的供應鏈防護：action 釘選 commit SHA、image 釘選 digest、下載的執行檔驗證 sha256。詳見 [SECURITY.md](SECURITY.md)；工具選型見 [`docs/DEVSECOPS-NOTES.md`](docs/DEVSECOPS-NOTES.md)。

---

## 相關文件

| 文件 | 內容 |
|---|---|
| [`docs/KNOWN-LIMITATIONS.md`](docs/KNOWN-LIMITATIONS.md) | 已知限制 |
| [`docs/FLOW.md`](docs/FLOW.md) | PR 流程與各檔案職責 |
| [`docs/ADOPT.md`](docs/ADOPT.md) | 導入腳本細節、內網與離線環境 |
| [`docs/SETUP.md`](docs/SETUP.md) | 管理者：發佈、方案與額度 |
| [`docs/MIGRATION-TO-ORG.md`](docs/MIGRATION-TO-ORG.md) | 遷移至組織 |
| [`docs/HANDOFF.md`](docs/HANDOFF.md) | 現況、待辦與發佈程序 |
| [`docs/DEVSECOPS-NOTES.md`](docs/DEVSECOPS-NOTES.md) | 工具選型 |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | 修改公版、提出需求 |
| [`CHANGELOG.md`](CHANGELOG.md) | 版本紀錄 |
| [`SECURITY.md`](SECURITY.md) | 弱點回報 |
