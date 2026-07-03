# ci-standards — 團隊統一安全與 CI 中央公版

這個 repo 是**中央公版**。安全掃描與 CI 的邏輯只寫在這裡一次；所有專案用一行 `uses:` 呼叫它。
公版更新 → 打新 tag → 各專案指向新 tag 即同步，不必逐一改每個 repo。

> 適用環境：GitHub Team + Copilot Business、私有 repo。全部使用免費開源工具，私有 repo 無需 GitHub Advanced Security 也能跑。

---

## 目錄結構

```
ci-standards/
├── README.md                          ← 本文件
├── .github/workflows/
│   ├── security-reusable.yml          ← 安全掃描公版（Semgrep + Trivy + OSV + gitleaks）
│   └── ci-reusable.yml                ← Python + Docker CI 公版
├── docs/
│   └── SETUP.md                       ← 完整導入、Copilot 啟用、分支保護步驟
└── templates/consumer-repo/           ← 各專案要複製過去的「呼叫端」範本
    └── .github/
        ├── dependabot.yml
        ├── copilot-instructions.md
        └── workflows/
            ├── security.yml           ← 一行呼叫中央公版
            ├── ci.yml                 ← 一行呼叫中央公版
            └── copilot-setup-steps.yml
```

---

## 這是什麼流程？「弱點自動修復閉環」

```
免費掃描器「找」弱點  →  開 Issue  →  指派 Copilot Coding Agent「修」+ 開 PR
        →  Copilot Code Review「審」PR  →  你「決定」merge
```

免費掃描器負責找（不花 AI Credits），Copilot Business 負責修與審，你負責決定。

---

## 快速開始

### 1. 發佈這個公版
```bash
git tag v1
git push origin v1
# 之後小修可移動 v1；重大變更改 v2，避免一次影響所有 repo
```
然後到本 repo → **Settings → Actions → General → Access** 選
**Accessible from repositories in the organization**（私有公版必做，否則其他 repo 呼叫不到）。

### 2. 各專案導入
把 `templates/consumer-repo/.github` 複製進每個專案根目錄，改掉 caller 裡的組織名與 tag：
```bash
cp -R templates/consumer-repo/.github .   # 在目標專案根目錄執行
# 編輯 .github/workflows/security.yml 與 ci.yml 的 uses: 那行
```
呼叫範例：
```yaml
jobs:
  security:
    uses: singi0771/ci-standards/.github/workflows/security-reusable.yml@v1
    with:
      python-version: "3.12"
      severity: "CRITICAL,HIGH"
      fail-on-findings: true
```

### 3. 啟用 Copilot 兩個 Agent、設分支保護
詳見 [`docs/SETUP.md`](docs/SETUP.md)。

---

## 公版可調參數（inputs）

| 參數 | 預設 | 說明 |
|---|---|---|
| `python-version` | `3.12` | 掃描 / CI 環境的 Python 版本 |
| `severity` | `CRITICAL,HIGH` | Trivy 要擋下的嚴重度 |
| `fail-on-findings` | `true` | `true`=掃到問題就擋 merge；`false`=只回報不擋 |
| `run-docker-build` | `true` | CI 是否驗證 Docker image 能 build |

## 為什麼私有 repo 也能免費跑

- 不把結果上傳到需付費的 **Security 分頁（code scanning）**，改用「job 成敗當守門員 + artifact」。
- gitleaks 用 **docker 執行檔**跑，避開 gitleaks-action 對組織帳號的授權要求。
- 全部工具皆為開源免費，只消耗 GitHub Actions 分鐘。
