# 工具怎麼選：為什麼是這幾套、哪些評估過但沒放進來

這份文件回答兩個問題：公版裡的每一個掃描器**為什麼是它**，以及那些常被問到的工具**為什麼沒進來**。
選擇的原則只有三條：

1. **免費、開源、private repo 不需要 GHAS 也能跑。**
2. **一個問題一個工具，不重疊。** 重疊的檢查抓到同一個問題兩次，除了多付一分鐘沒有好處。
3. **每個 job 至少算一分鐘。** 跑不到 30 秒的檢查併進既有 job，不另開。

最後更新：2026-09-14（1.3.0）。

---

## 公版裡的每一套：抓什麼、為什麼是它

| 工具 | 抓什麼 | 為什麼是它、不是別的 |
|---|---|---|
| **Semgrep**（SAST） | 程式碼裡的弱點寫法：SQL injection、`eval`、不安全的反序列化、硬編碼密鑰… | 免費、多語言、規則包（`p/owasp-top-ten`、`p/security-audit`）可以直接用。private repo 用不了 CodeQL，它是最接近的免費替代。規則包用 `semgrep-rules` 可換 |
| **OSV-Scanner**（相依套件 CVE） | lockfile / manifest 裡的套件有沒有已知 CVE，資料來源是 Google 的 OSV 資料庫 | 跟 `pip-audit` 查的是同一個資料庫，但 OSV-Scanner 不限 Python，一支就涵蓋 npm / Go / Rust。dependency-review-action 在 private repo 要 GHAS |
| **Trivy**（檔案系統 / IaC） | 相依弱點（第二道）+ Dockerfile / Kubernetes / Terraform 的錯誤設定；可選授權條款、SBOM | 一支工具同時做 vuln、misconfig、license、SBOM，少開三個 job。Checkov / KICS 的 IaC 規則跟它重疊很高 |
| **gitleaks**（密鑰） | token、密碼、私鑰有沒有 commit 進 repo，**連 git 歷史一起掃** | 規則庫最完整的免費密鑰掃描器。用 docker 執行檔直接跑，避開 `gitleaks-action` 對組織帳號的授權要求 |
| **zizmor**（workflow 安全，1.3.0 新增） | `.github/workflows` 本身：把 PR 標題塞進 `run:` 的腳本注入、`pull_request_target` / `workflow_run` 這類危險觸發器、沒釘 SHA 的 action、權限給太大、checkout 留下 token 又上傳 artifact | 這是 actionlint 管不到的一整類問題（actionlint 只看語法）。tj-actions/changed-files 那次供應鏈事件之後，這類檢查變成必備。Rust 寫的，跑完不用一秒 |
| **Trivy image**（可選） | build 出來的 image 裡 OS 套件與語言套件的 CVE | 跟檔案系統掃描是同一支工具，不用多學一套。預設只擋上游已修的 CVE（`ignore-unfixed`），不然 base image 永遠紅 |
| **hadolint**（可選，1.3.0 新增） | Dockerfile 的寫法：沒釘版本的 apt 套件、用 `latest`、`RUN` 裡的 shell 問題 | Trivy 的 misconfig 只抓「會出資安問題」的那幾條，hadolint 抓得更廣。放在 Docker build 那個 job 裡當一個步驟，不多付一分鐘 |
| **actionlint + shellcheck** | workflow 語法、`run:` 區塊與 `.sh` 的 bash 問題 | 兩個都是各自領域的標準工具。1.3.0 起合成一個 job、actionlint 改抓執行檔不拉 docker image |
| **ruff + pytest** | Python lint 與測試 | ruff 一支取代 flake8 + isort + 大部分 bandit（開 `S` 規則）；版本釘死避免規則漂移 |

---

## 評估過但沒放進來的（逐一說明）

| 工具 | 做什麼 | 為什麼沒放 | 什麼情況下該考慮 |
|---|---|---|---|
| **Bandit** | Python 專用 SAST | 跟 Semgrep 的 `p/security-audit` + ruff 的 `S` 規則幾乎全部重疊，多一個 job 多一分鐘卻抓不到新東西 | 純 Python 團隊想要 Bandit 特有的幾條規則：在 `pyproject.toml` 開 ruff 的 `select = ["S"]` 就好，不必另裝 |
| **pip-audit** | Python 套件 CVE | 查的是同一個 OSV 資料庫，OSV-Scanner 已涵蓋 | 想在本機開發時順手查：`pip-audit` 當本機工具很好，CI 上不必重複 |
| **Checkov / KICS / tfsec** | IaC（Terraform / K8s / CloudFormation）錯誤設定 | Trivy 的 `misconfig` 掃描器用的是同一批 policy 概念，規則重疊八成以上 | Terraform 很重、需要 Checkov 特有的 graph 檢查（跨資源關聯）時，開 Issue 討論加成可選 job |
| **TruffleHog** | 密鑰掃描，會**實際打 API 驗證密鑰是否還有效** | 跟 gitleaks 重疊；驗證功能很好但會對外連線，private repo 的密鑰拿去打第三方 API 要先問過資安 | 大量歷史密鑰要分「還活著 / 已撤銷」時，本機跑一次 `trufflehog --only-verified` |
| **detect-secrets** | 密鑰掃描（Yelp） | 規則比 gitleaks 少，優勢是 baseline 檔工作流；gitleaks 的 `.gitleaksignore` 已夠用 | 不考慮 |
| **CodeQL** | GitHub 原生 SAST，品質最好 | private repo 需要 GHAS（付費）；public repo 免費 | repo 是 public 或買了 GHAS：直接用 GitHub 的預設 CodeQL 設定，跟本公版並存沒衝突 |
| **SonarQube Community** | 程式品質儀表板 | Community 版**不支援 PR 分析**（那是 Developer Edition 付費功能），又要自己架伺服器；SonarCloud 免費層只給 public repo。當 PR gate 做不到，只能整包掃 main | 想要品質趨勢圖：自己架一台、排程掃 main，**不要設成 required check** |
| **OWASP ZAP**（DAST） | 對**跑起來的網站**做動態掃描 | 要先有 preview / staging 環境才能掃，跟 PR gate 的「幾分鐘內給答案」不合 | 有 staging 之後另開一支 workflow：部署 → ZAP baseline → 回報，用 schedule 或手動觸發 |
| **OpenSSF Scorecard** | 整個 repo 的安全姿態評分（分支保護、釘版本、有沒有 SECURITY.md…） | 是「repo 健康檢查」不是「這個 PR 有沒有問題」；private repo 功能受限 | public repo 可以每週跑一次當儀表板，不當 gate |
| **Syft + Grype** | SBOM 產生 + 比對 CVE | Trivy 已能產 SBOM（`generate-sbom`）也能掃，功能重疊 | 客戶指定要 Syft 格式的 SBOM 時 |
| **Dockle** | image 的 CIS benchmark 檢查 | 跟 Trivy image + hadolint 重疊大半 | 有合規要求要出 CIS 報告時 |
| **cosign**（簽章） | 簽 image / artifact | 公版不推 image、不發 release，沒有東西可簽 | 開始推 image 到 registry 時，在那支發佈 workflow 裡加 |
| **Dependency Review Action** | PR 引入的新相依有沒有 CVE | private repo 要 GHAS | public repo 可加，跟 OSV-Scanner 並存無妨 |

---

## 幾個技術上的取捨

- **action 釘 commit SHA，不釘 tag。** tag 可以被移動，SHA 不行。這也是 zizmor `unpinned-uses` 預設要求的。
  唯一的例外是指向本公版的 `@v1` —— 那是刻意讓所有專案自動跟版的設計，用 `.github/zizmor.yml` 放行，
  並用不可變的 `vX.Y.Z` 當退回點（見 SECURITY.md）。
- **container image 釘 tag + digest。** `semgrep/semgrep:1.171.0@sha256:…`、`ghcr.io/gitleaks/gitleaks:v8.30.1@sha256:…`。
  只釘 tag 的話上游重推同一個 tag 你不會知道。digest 查法：`docker buildx imagetools inspect <image>:<tag>`。
- **直接下載的執行檔釘版本 + sha256。** OSV-Scanner、actionlint、zizmor、hadolint 都是 `curl --fail` 抓下來 →
  `sha256sum -c` → `--version` 驗過才用。少任何一步，下載失敗或被換包都會變成「掃描沒跑卻綠燈」。
  代價是 Dependabot 不會幫這幾個升版，要人工升（步驟寫在 CONTRIBUTING.md）。
- **Semgrep 的 `auto` 規則包會回傳匿名使用統計**（哪些規則跑了、跑多久，不含程式碼）。
  不能接受的話把 `semgrep-rules` 裡的 `auto` 拿掉，換成明確的語言包如 `p/python`。
- **Trivy 預設不掃 secret。** gitleaks 已經連歷史一起掃，Trivy 再掃一次工作區是重複的；
  真的想要就 `trivy-scanners: "vuln,misconfig,secret"`。
- **gitleaks 用 docker 執行檔，不用 `gitleaks-action`。** 後者在**組織帳號**要 `GITLEAKS_LICENSE`。
- **OSV-Scanner 直接下載執行檔，不用 `osv-scanner-action`。** 那個 action 的安裝腳本抓 `main`，等於沒釘版本。

---

## 這套的定位（先把期待講清楚）

這是完整的**開發階段弱點掃描 + PR 守門**，涵蓋 SAST、相依 CVE、密鑰、IaC / Docker 設定、workflow 安全。
但它**不是**完整資安防護 —— 不含 WAF、EDR、SIEM、CSPM、runtime 偵測與滲透測試。
把它當「把明顯炸彈擋在 main 之外」的第一道，很稱職。

## 建議導入順序

1. **第一階段（現在就有）**：gitleaks + Semgrep + OSV + Trivy FS + zizmor → PR 守門。
2. **第二階段**：加 Copilot Code Review + Coding Agent 的修復流程 + PR template + instructions（已附）。
3. **第三階段**：`scan-docker-image: true` 打開 image 掃描、`run-hadolint: true`、`generate-sbom: true`。
4. **第四階段（可選）**：SonarQube 當 main 的品質儀表板（自己架，不當 gate）。
5. **第五階段（成熟後）**：ZAP DAST + preview 環境 + SBOM 簽章（cosign）。

> 一句話：先用 `gitleaks + Semgrep + OSV + Trivy + zizmor` 打好基礎，Copilot 接「修 + 審」，Sonar / ZAP 再視需要加，別第一天全上。
