# Changelog

本 repo 是**中央公版**：所有專案用 `uses: .../@v1` 呼叫它。
一次改動會同時影響所有專案，所以每次發佈都必須記在這裡。

版本規則見 [README — 版本策略](README.md#版本策略)。每次發佈打兩個 tag：
不可變的 `vX.Y.Z`（回滾點）+ 會移動的 `vX`（大家指向的別名）。

格式參考 [Keep a Changelog](https://keepachangelog.com/zh-TW/1.1.0/)。

---

## [未發佈]

（目前沒有未發佈的變更。`v1` 指向 `v1.1.0`。）

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
