# Changelog

本 repo 是**中央公版**：所有專案用 `uses: .../@v1` 呼叫它。
一次改動會同時影響所有專案，所以每次發佈都必須記在這裡。

版本規則見 [README — 版本策略](README.md#版本策略)。每次發佈打兩個 tag：
不可變的 `vX.Y.Z`（回滾點）+ 會移動的 `vX`（大家指向的別名）。

格式參考 [Keep a Changelog](https://keepachangelog.com/zh-TW/1.1.0/)。

---

## [未發佈]

### 新增
- `docs/KNOWN-LIMITATIONS.md` —— 記錄實測過但還不能用的功能（Copilot Coding Agent、
  `upload-sarif`、Copilot 觸發的 run 卡 `action_required`），含逐步排查流程。
  這些結論原本只存在於已關閉 PR 的留言裡。

  補測（2026-08-01）：**Copilot Coding Agent 其實是可用的** —— 指派 Issue 會立刻開出 PR。
  7/26 那次「直接指派到人類的 PR」是無效測試（不是官方觸發入口），因此一度誤判為方案／
  policy 問題。問題現已收斂為兩點：`github-actions[bot]` 貼的 `@copilot` 喚不醒 Agent；
  以及 **Copilot 開的 PR，其 CI/Security run 全部卡在 `action_required`**
  → required check 永遠不回報 → 那個 PR 永遠 merge 不了。後者才是自動修真正的擋路石。
- `docs/MIGRATION-TO-ORG.md` —— 搬到組織的完整 checklist。
- `CONTRIBUTING.md`、`SECURITY.md`、`LICENSE`、`CHANGELOG.md`、`.github/CODEOWNERS`
- `.github/pull_request_template.md` —— 本 repo 自己的 PR 檢查清單（原本只有給 consumer 的範本）

### 變更
- README 的 `ci-reusable` 參數表補上遺漏的 5 個 input：`run-python`、`run-actionlint`、
  `actionlint-paths`、`run-shellcheck`、`shellcheck-paths`。這些 input 在 v1.1.0 就存在，
  但文件沒寫，等於功能沒人知道。
- README「專案不是 Python」改寫：現在用 `run-python: false` 即可照用公版，
  不再需要「自己另寫一支 CI」。
- README 運作原理圖補上 CI 的 actionlint / shellcheck 兩個子 job。
- README 檔案地圖補上本 repo 自己的 dogfooding workflow 與新文件。
- README 版本策略改為「不可變版本號 + 移動別名」雙 tag。
- `docs/DEVSECOPS-NOTES.md` 的釘版本說明與實作對齊（實際已改用 commit SHA 與直接下載 binary，
  不是文件寫的 `trivy-action@0.28.0` / `osv-scanner-action@v2`）。

### 修正
- `copilot-autofix-review-reusable.yml`：`${{ github.repository }}` 不再直接插進 `run:` 字串，
  改走 `env:`。與本 repo `copilot-instructions.md` 的鐵則一致 —— 公版是給人抄的，寫法會被抄走。

---

## [1.1.0] — 待發佈

> ⚠️ **這一版的內容早就在 `main` 上，但 `v1` tag 一直停在 1.0.0（`c19ff64`）**，
> 所以任何指向 `@v1` 的專案拿到的都還是舊版。發佈動作＝移動 `v1` + 打 `v1.1.0`。

### 新增
- `ci-reusable.yml` 新增 `run-python`、`run-actionlint`、`actionlint-paths`、
  `run-shellcheck`、`shellcheck-paths`，讓非 Python 專案也能直接用公版。
- 本 repo 自己套用公版（dogfooding）：`.github/workflows/` 下的 `ci.yml`、`security.yml`
  與三支 `copilot-auto*` 薄殼，全部用 `./` 呼叫自己的 reusable。
- `.github/copilot-instructions.md`、`.github/dependabot.yml`。

### 修正（重要，這是必須發佈的理由）
- **消除三種「PR 永遠 merge 不了」的死鎖**：`skipped` 的 required check 永遠不回報、
  呼叫端 `pull_request` 的 `paths-ignore` 會擋掉純文件 PR、required approvals 設 1 但沒人能 approve。
- **掃描失敗不再被當成通過**：OSV-Scanner 下載改用 `curl --fail` 並先驗 `--version`；
  非 0/1/128 的 exit code 一律視為掃描失敗而擋下（舊版把 127 當良性 warning 放行，
  等於**相依弱點掃描靜默失效卻依然綠燈**）。
- **掃描器釘死版本**：`semgrep/semgrep:1.171.0`、`ghcr.io/gitleaks/gitleaks:v8.30.1`、
  `rhysd/actionlint:1.7.12`。不釘的話上游新增規則會讓沒改碼的 repo 突然變紅，也是供應鏈風險。
- **Copilot 自動化迴圈收斂**：autoreview 加上次數上限與同 SHA 去重、autofix 加上 15 分鐘 cooldown
  與「升級後閉嘴」marker、補上貼 label 缺少的 `issues: write`（少了會靜默 403）。
- 所有 action 改為釘 commit SHA。
- Dependabot `cooldown` 只保留 `default-days`（`semver-major-days` 會讓 github-actions
  ecosystem 判為 invalid config）。
- 修掉自我掃描抓到的 22 個 Semgrep findings。
- `setup-branch-protection.sh` 補上執行權限；重複執行改為 `PUT` 更新，不再建出第二份同名 ruleset。

### 相容性
- 對既有呼叫端**完全相容**：新增的 input 都有預設值，不改任何 input 或 job 名稱。
- 唯一的行為變更：掃描器異常結束現在會擋下 PR（舊版放行）。這是刻意的修正。

---

## [1.0.0] — 2026-07-25（`c19ff64`）

初版。`v1` tag 長期停在這裡。

⚠️ **不要使用這一版**：含上面 1.1.0 修掉的三種死鎖與掃描靜默失效問題，
且 `ci-reusable.yml` 只有 3 個 input，寫 `run-python: false` 會直接 invalid input 啟動失敗。
留著只作為回滾歷史紀錄。
