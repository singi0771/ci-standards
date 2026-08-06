# DevSecOps 顧問建議（依你的架構文章，逐項指教）

這份文件說明：哪些照文章加進公版了、哪些要小心、以及 SonarQube / ZAP 的重要提醒。

## 已依文章加進 `security-reusable.yml`

- **Semgrep 規則升級**：從 `--config=auto` 擴充為 `p/owasp-top-ten` + `p/security-audit` + `p/secrets` + `auto`，SAST 覆蓋更完整。
- **可選 Docker image 掃描**：新增 `scan-docker-image` 輸入（AdminAutoTools 有 Dockerfile，範本已設 true），build image 後用 Trivy 掃 CVE。
- **可選 SARIF 上傳**：新增 `upload-sarif` 輸入。private 且無 GHAS → 維持 false（用 artifact + job 成敗當守門員）；public 或有 GHAS → 可設 true，結果寫進 Security 分頁。
- **強化 Copilot instructions + PR template**：把文章的安全規範（輸入驗證、Docker 非 root、無 0.0.0.0/0 等）與 PR 檢查清單納入 consumer 範本。

## ⚠️ SonarQube Community —— 最需要注意的一點

文章把 SonarQube Community 放進 PR Gate，但 Community 版有兩個現實限制，**我建議先不要當 PR 必過關卡**：

1. **Community 版不支援 PR 分析 / 分支分析**。Pull request decoration 與 branch analysis 是 **Developer Edition（付費）** 才有的功能。Community 版原則上只分析 default branch，所以「每個 PR 都用 Sonar 當 gate」在免費版做不到（會分析不到 PR 差異、或只能整包重掃 main）。
2. **要自架伺服器**。`SONAR_HOST_URL` + `SONAR_TOKEN` 代表你得自己跑一台 SonarQube server + 資料庫（Docker 也要有人維運），這不是「零基礎設施的免費」。SonarCloud（SaaS）免費層則**只給 public repo**。

建議做法：
- 你的專案是 Python，**`ruff` + Semgrep（security-audit）已涵蓋大部分 Sonar 會抓的 code smell 與基本安全規則**，先不急著上 Sonar。
- 若真的要 Sonar，把它當成「**定期針對 main 分支的品質儀表板**」（self-hosted、排程跑），而不是 PR 必過 gate。不要把 Sonar 設成 required check（Community 版會卡住你的 PR 流程）。

## ⚠️ OWASP ZAP（DAST）—— 需要「跑起來的應用」

ZAP baseline 是對**正在執行的 Web App URL**掃描，不是掃程式碼。所以它需要先把應用部署到一個 preview / staging 環境才能掃，屬於文章講的 Phase 5。建議：
- **不要放進核心 PR gate**（會拖慢每個 PR、且需要環境）。
- 之後可做一支獨立 workflow：部署到暫時環境 → ZAP baseline → 回報，改用 `schedule` 或手動觸發。

## 其他幾點技術指教

- **action 釘版本，別用 `@master`**：文章的 `aquasecurity/trivy-action@master` 與 OSV 的 install script（抓 `main`）是供應鏈風險——上游一改你就默默中招。公版**一律釘 commit SHA**（不是版本 tag —— tag 可以被移動），例如 `aquasecurity/trivy-action@ed142fd0673e97e23eac54620cfb913e5ce36c25 # v0.36.0`。
- **container image 也要釘**：`semgrep/semgrep:1.171.0`、`ghcr.io/gitleaks/gitleaks:v8.30.1`、`rhysd/actionlint:1.7.12`。用 `:latest` 的話，上游新增規則會讓**沒改任何一行碼的 repo 突然變紅**，這比供應鏈風險更常實際發生。
- **OSV-Scanner 改為直接下載釘死版本的 binary**（不用 `osv-scanner-action`），下載時 `curl --fail`、執行前先驗 `--version`。這一步很關鍵：沒有它的話，GitHub 回 404/5xx 時 curl 會把錯誤頁面存成「執行檔」，後面執行失敗又被當成良性 warning 放行 → **相依弱點掃描靜默失效、Gate 照樣綠燈**。
- **gitleaks 用 docker 執行檔，不要用 `gitleaks-action`**：後者在**組織帳號**需要 `GITLEAKS_LICENSE`。公版已改用 `ghcr.io/gitleaks/gitleaks` 直接跑，免授權。
- **Dependency Review Action 在 private 需 GHAS**：文章提到的 dependency-review-action 在私有 repo 要 GHAS 才能用；OSV-Scanner 已免費涵蓋同樣需求，private 就用 OSV 即可。
- **Actions 額度**：Semgrep 多規則 + Docker build/scan 會多吃分鐘。`ci-standards` 設 public 後它自己的 Actions 不計額度；但 **consumer 的 private repo（如 AdminAutoTools）仍吃自己每月 3,000 分鐘**，留意用量。

## 這套的定位（務必對齊期待）

這是完整的 **Shift-left / 開發階段弱掃 + PR Gate**，涵蓋 SAST、相依 CVE、密鑰、IaC/Docker。但它**不是**完整資安防護——不含 WAF、EDR、SIEM、CSPM、runtime 偵測與滲透測試。把它當「把明顯炸彈擋在 main 之外」的第一道，很稱職。

## 建議導入順序（對齊你的 Phase）

1. **Phase 1（現在就有）**：gitleaks + Semgrep + OSV + Trivy FS → PR 守門。
2. **Phase 2**：加 Copilot Code Review + Coding Agent 修復閉環 + PR template + instructions（已附）。
3. **Phase 3**：`scan-docker-image: true` 打開 image 掃描 + IaC 強化。
4. **Phase 4（可選）**：Sonar 當 main 品質儀表板（self-hosted，非 gate）。
5. **Phase 5（成熟後）**：ZAP DAST + preview 環境 + SBOM / 簽章（cosign）。

> 一句話：先用 `Gitleaks + Semgrep + OSV + Trivy` 打底，Copilot 接「修 + 審」，Sonar/ZAP 再視需要加，別第一天全上。
