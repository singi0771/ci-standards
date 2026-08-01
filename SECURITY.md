# 安全政策

## 回報弱點

**請不要開公開 Issue 回報安全問題。**

請用 GitHub 的私密回報管道：本 repo → **Security** 分頁 → **Report a vulnerability**
（若該功能未開啟，請直接私訊 repo 的 maintainer，見 [`.github/CODEOWNERS`](.github/CODEOWNERS)）。

回報時請盡量附上：影響的檔案與版本（哪個 tag）、重現步驟、以及你認為的影響範圍。

## 這個 repo 為什麼特別敏感

這裡是**中央公版**：所有專案用 `uses: .../@v1` 呼叫這裡的 workflow。
也就是說，**能改動這個 repo 的人，等於能在所有 consumer 專案的 CI 裡執行程式碼**。

具體的風險面：

| 風險 | 現有防護 |
|---|---|
| 供應鏈：第三方 action 被投毒 | 所有 action 釘 commit SHA、所有 container image 釘版本號；Dependabot 設 7 天 cooldown 才更新 |
| 供應鏈：掃描器下載被竄改或失敗 | `curl --fail` + 執行前驗 `--version`；未預期的 exit code 一律視為掃描失敗而擋下 |
| Shell injection：event payload 進 `run:` | 外部輸入一律先過 `env:`，用 `"$VAR"` 引用，不把 `${{ }}` 插進字串 |
| 權限過大 | workflow 一律宣告最小 `permissions`，需要什麼加什麼 |
| 惡意改動混進 main | main 有分支保護；本 repo 自己也跑完整的 CI + 安全掃描（dogfooding） |
| `v1` 被移到惡意 commit | 每次發佈同時打不可變的 `vX.Y.Z`，可比對與回滾 |

## 支援的版本

| 版本 | 狀態 |
|---|---|
| `v1`（目前指向的最新 `v1.x.y`） | ✅ 持續維護 |
| 更舊的 `v1.x.y` | ⚠️ 僅作為回滾點，不再修補 |

安全修補一律直接進最新版並移動 `v1`；不會回頭修舊的 minor 版本。

## 這套涵蓋範圍的說明

公版提供的是 **shift-left / 開發階段**的防護（SAST、相依 CVE、密鑰、IaC/Docker 設定）。
它**不是**完整資安防護 —— 不含 WAF、EDR、SIEM、CSPM、runtime 偵測、滲透測試、DAST。
詳見 [README — 這套涵蓋什麼、不涵蓋什麼](README.md#這套涵蓋什麼不涵蓋什麼)。
