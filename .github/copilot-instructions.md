# Copilot 專案指引 — ci-standards（中央 CI / 安全公版）

## 專案概觀
- 用途：團隊統一的 CI / 安全掃描「中央公版」。各專案用一行 `uses:` 呼叫，邏輯集中在此。
- 這裡**沒有應用程式碼**：內容是 GitHub Actions workflow（YAML + 內嵌 bash）、shell / PowerShell script 與文件。
- 使用端指向 `@v1` tag，所以**這個 repo 的每一次改動都會同時影響所有專案**。

## 開發與測試指令（修完必須自己跑過）
- Workflow 語法：`actionlint -color`（PATH 上有 shellcheck 的話會連 `run:` 區塊的 bash 一起檢查）；
  範本也要：`actionlint -color templates/consumer-repo/.github/workflows/*.yml`
- Workflow 安全：`zizmor .`（會連 `templates/` 一起掃，設定在 `.github/zizmor.yml`）
- Shell script：`shellcheck scripts/*.sh`
- 導入腳本回歸測試：`bash scripts/test-adopt.sh`（會自己 cd 到暫存目錄，不會動到本 repo）
- 沒有 pytest / ruff —— 本 repo 的 CI 已把 `run-python` 關掉，不要為了「讓它有測試」而硬加。

## 改動這個 repo 的鐵則

**1. 不要讓「檢查失敗」變成「檢查通過」。**
掃描工具異常結束（下載失敗、command not found、內部錯誤）一律要擋下，不可以當 warning 放行。
下載工具用 `curl --fail`，比對 sha256，執行前先驗 `--version`。

**2. 有 `if` 條件的 job 絕不可以是 required status check。**
關掉時會變 `skipped`，GitHub 要嘛把它當通過、要嘛永遠 pending，兩種都不對。
新增 job 一律加進 `ci-gate` / `security-gate` 的 `needs`，由 gate 判斷（開了就必須 success）。

**3. 外部 action、container image、下載的執行檔一律釘死。**
action 釘 commit SHA、image 釘 tag + digest、執行檔釘版本 + sha256。不要用 `@main` / `@master` / `:latest`。
理由有二：供應鏈風險，以及上游升版新增規則會讓沒改程式的 repo 突然變紅。

**4. 改 input 名稱或 job 名稱＝破壞性變更。**
使用端的 ruleset 綁著 job 名稱（`ci / CI Gate`、`security / Security Gate`），
改名會讓既有專案的 required check 永遠 pending。這種改動要開 `v2`，不能移 `v1`。

**5. 自動化留言要有停止條件。**
任何會在 PR 留言的自動流程都必須有：次數上限、隱藏標記防重複、達上限後停止（不是繼續重貼）。
沒有上限的迴圈會燒光 AI credits 並把通知塞爆。

**6. 每多一個 job 就多付一分鐘。**
GitHub 每個 job 不滿一分鐘也算一分鐘。跑不到 30 秒的檢查要併進既有 job 當一個步驟，不要另開 job。

## 安全要求
- 絕不把密鑰、token 寫進 workflow 或 script；用 `${{ secrets.* }}` 或 `github.token`。
- workflow 的 `permissions` 用最小權限，需要什麼加什麼（例如貼 label 需要 `issues: write`）。
- 外部輸入（`inputs.*`、event payload）進 shell 一律**先經 `env:` 再用 `"$VAR"` 引用**，
  不要直接把 `${{ }}` 塞進 `run:` 字串裡（shell injection）。
- `actions/checkout` 一律 `persist-credentials: false`，除非那個 job 真的要 push。

## PR 要求
- 每個 PR 聚焦單一目的，附「為什麼」與「怎麼驗證」。
- 必須通過本 repo 的 CI（actionlint + shellcheck）、Security Scan（含 zizmor）與 adopt 回歸測試。
- 不要停用或跳過既有檢查來讓 PR 變綠。
