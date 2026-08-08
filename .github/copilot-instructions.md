# Copilot 專案指引 — ci-standards（中央 CI/安全公版）

## 專案概觀
- 用途：團隊統一的 CI / 安全掃描「中央公版」。各專案用一行 `uses:` 呼叫，邏輯集中在此。
- 這裡**沒有應用程式碼**：內容是 GitHub Actions workflow（YAML + 內嵌 bash）、shell script 與文件。
- 消費端指向 `@v1` tag，所以**這個 repo 的每一次改動都會同時影響所有專案**。

## 開發與測試指令（修完必須自己跑過）
- Workflow 語法：`docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:1.7.12 -color`
  （這個 image 內建 shellcheck，會連 `run:` 區塊的 bash 一起檢查）
- Shell script：`shellcheck scripts/*.sh`
- 沒有 pytest / ruff —— 本 repo 的 CI 已把 `run-python` 關掉，不要為了「讓它有測試」而硬加。

## 改動這個 repo 的鐵則

**1. 不要讓「檢查失敗」變成「檢查通過」。**
掃描工具異常結束（下載失敗、command not found、內部錯誤）一律要擋下，不可以當 warning 放行。
下載工具用 `curl --fail`，執行前先驗 `--version`。

**2. 有 `if` 條件的 job 絕不可以是 required status check。**
關掉時會變 `skipped`，而 skipped 的 required check 永遠不回報 → PR 永久卡在 pending。
新增 job 一律加進 `ci-gate` / `security-gate` 的 `needs`，由 gate 判斷（只有 `failure` / `cancelled` 才擋）。

**3. 外部 action 與 container image 一律釘版本。**
不要用 `@main` / `@master` / `:latest`。理由有二：供應鏈風險，以及上游升版新增規則會讓
沒改碼的 repo 突然變紅。

**4. 改 input 名稱或 job 名稱＝破壞性變更。**
消費端的 ruleset 綁著 job 名稱（`ci / CI Gate`、`security / Security Gate`），
改名會讓既有專案的 required check 永遠 pending。這種改動要開 `v2`，不能移 `v1`。

**5. 自動化留言要有收斂機制。**
任何會在 PR 留言的自動流程都必須有：次數上限、隱藏 marker 去重、達上限後停止（不是繼續重貼）。
沒有上限的迴圈會燒光 AI credits 並把通知塞爆。

## 安全要求
- 絕不把密鑰、token 寫進 workflow 或 script；用 `${{ secrets.* }}` 或 `github.token`。
- workflow 的 `permissions` 用最小權限，需要什麼加什麼（例如貼 label 需要 `issues: write`）。
- 外部輸入（`inputs.*`、event payload）進 shell 一律**先經 `env:` 再用 `"$VAR"` 引用**，
  不要直接把 `${{ }}` 插進 `run:` 字串裡（shell injection）。

## PR 要求
- 每個 PR 聚焦單一目的，附「為什麼」與「怎麼驗證」。
- 必須通過本 repo 的 CI（actionlint + shellcheck）與 Security Scan。
- 不要停用或跳過既有檢查來讓 PR 變綠。
