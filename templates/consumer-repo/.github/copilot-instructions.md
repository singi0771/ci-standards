# Copilot 專案指引（Coding Agent / Code Review 都會讀）— AdminAutoTools 範本

## 專案概觀
- 用途：<一句話描述 AdminAutoTools 在做什麼>
- 技術棧：Python + Docker（含 docker-compose、nginx、openapi/openspec 規格）
- 進入點：`app.py`

## 開發與測試指令（Coding Agent 修完必須自己跑過）
- 安裝相依：`pip install -r requirements.txt`
- Lint：`ruff check .`
- 測試：`pytest -q`
- 本地啟動：`docker compose up --build`
- 規格檢查：`openspec`（若有 strict 檢查，修改後要跑過）

## 程式碼慣例
- 遵循 ruff 的 lint/format 規則
- 目錄：服務放 `services/`、資料模型放 `models.py` / `auth_models.py`、測試放 `tests/`
- 提交訊息用 Conventional Commits（feat/fix/chore/...）

## 安全要求（修復與審查都要遵守）
Application / 程式碼
- 絕不把密鑰、token、密碼、連線字串寫進程式碼或 `.env`（用 `.env.example` 當範本）；用環境變數。
- 所有外部輸入必須驗證、清理或參數化；SQL 一律用 parameterized query。
- 不得使用 `eval`、`exec`、動態命令執行。
- API 回應不得暴露 stack trace、token、內部路徑。
- 檔案上傳需檢查副檔名、MIME type、大小與儲存路徑。

Dependency
- 新增套件需在 PR 說明原因；避免無維護、低星或近期有重大 CVE 的套件。
- 修弱點時優先採用維護中版本，避免引入新的高風險相依。

Docker / IaC
- Dockerfile 不得用 `latest` tag；container 不得以 root 執行。
- Kubernetes 不得用 privileged mode；Terraform 不得對高風險 port 開放 `0.0.0.0/0`。

- 涉及認證、授權、加密的變更，在 PR 描述明確標註並說明理由。

## PR 要求
- 每個 PR 聚焦單一目的，附「為什麼」與「怎麼驗證」。
- 必須通過本 repo 的 CI 與 Security Scan（Semgrep / Trivy / OSV / gitleaks）。
- 不要停用或跳過既有安全檢查來讓 PR 變綠。
