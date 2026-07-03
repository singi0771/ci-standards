# 導入與設定指南

## 步驟 1 — 發佈中央公版
1. 這個 `ci-standards` repo push 到 GitHub 的 `main`。
2. 打版本 tag：
   ```bash
   git tag v1
   git push origin v1
   ```
3. **開放組織內其他 repo 呼叫**（私有公版必做）：
   本 repo → Settings → Actions → General → Access → **Accessible from repositories in the organization**。

## 步驟 2 — 各專案導入 caller
在每個專案（例如 AdminAutoTools）根目錄：
```bash
cp -R templates/consumer-repo/.github .
```
編輯 `.github/workflows/security.yml` 與 `ci.yml`，把 `uses:` 那行的組織名與 `@v1` 改成你的值，然後：
```bash
git add .github
git commit -m "Adopt org CI/security standard + Copilot config"
git push
```

## 步驟 3 — 啟用 Copilot 的兩個 Agent（Business 已含）

**Copilot Code Review（自動審 PR）**
1. Org → Settings → Copilot → Policies：開啟 **Copilot code review**。
2. repo 或 ruleset 設「自動要求 Copilot review」，讓每個 PR 自動被審。
3. `copilot-instructions.md` 會被 Copilot 參考（專案慣例與安全要求）。

**Copilot Coding Agent（把 Issue 變 PR）**
1. Org → Settings → Copilot → Policies：確認 **Copilot coding agent** 已啟用。
2. 開一個 Issue → 右側 Assignees **指派給 Copilot**（或用 Agents / Create issue 入口）。
3. Copilot 先跑 `copilot-setup-steps.yml` 準備環境，再修碼、跑測試、開 PR。

> 用量提醒：兩個 Agent 都會扣 AI Credits（1,900/人/月）+ Actions 分鐘。先從小型、明確的 Issue 開始。

## 步驟 4 — 分支保護，讓閉環「非過不可」

**推薦：一鍵腳本（需已 `gh auth login`）**
```bash
./scripts/setup-branch-protection.sh <owner>/<repo>
# 例：./scripts/setup-branch-protection.sh cecigehlpj/AdminAutoTools
```
這會建立 ruleset：要求 PR + 至少 1 approve + 對話解決 + 通過 **Security Gate** 與 **CI** + 禁止 force push/刪除。

**或手動：** 目標 repo → Settings → Rules → Rulesets → 針對 `main`：
- 勾 **Require a pull request before merging**（至少 1 approve）
- 勾 **Require status checks to pass**，只要加入這一個彙總關卡即可：
  **`security / Security Gate`**（它已 `needs` 所有掃描；任何一項失敗它就失敗）
- 另可加 **`ci / Python lint + test`**

> 為什麼用 Security Gate：公版新增了一個彙總 job，把 Semgrep/OSV/Trivy/gitleaks 的成敗收斂成「一個」required check，分支保護只要顧這一個，之後增減掃描工具都不必再改 ruleset。

## 步驟 5 — 防止意外超額付費
Settings → Billing → Spending limit：把 Actions 設為 **$0**。

## 步驟 6 — 每月檢視
- 各 repo 的 Actions run 狀態與 Security Scan artifact。
- Org → Billing：AI Credits 與 Actions 分鐘用量。
