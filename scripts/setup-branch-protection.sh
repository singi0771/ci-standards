#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# 一鍵為指定 repo 的 default branch 建立分支保護 ruleset：
#   - 必須開 PR 才能改 main
#   - 至少 1 人 approve、要求對話解決
#   - 必須通過 Security Gate 與 CI 才能 merge
#   - 禁止 force push / 刪除分支
#
# 需求：已安裝並登入 GitHub CLI（gh auth login）
# 用法：./scripts/setup-branch-protection.sh <owner>/<repo>
#   例：./scripts/setup-branch-protection.sh cecigehlpj/AdminAutoTools
# ─────────────────────────────────────────────────────────────
set -euo pipefail

REPO="${1:?用法: $0 <owner>/<repo>}"

echo "→ 為 $REPO 建立分支保護 ruleset..."

# required_status_checks 的 context 必須對應「呼叫端 job 名 / reusable job 名」。
# 若你改過 caller job 名稱（security.yml 的 job: security、ci.yml 的 job: ci），請一併調整下面。
gh api -X POST "repos/$REPO/rulesets" \
  -H "Accept: application/vnd.github+json" \
  --input - <<'JSON'
{
  "name": "CI Standard - main protection",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] }
  },
  "rules": [
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 1,
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": true
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": true,
        "required_status_checks": [
          { "context": "security / Security Gate" },
          { "context": "ci / Python lint + test" }
        ]
      }
    },
    { "type": "non_fast_forward" },
    { "type": "deletion" }
  ]
}
JSON

echo "✅ 完成。到 $REPO → Settings → Rules → Rulesets 可檢視。"
echo "⚠️ 提醒：required check 的名稱要和實際 Checks 分頁一致；"
echo "   第一次 workflow 跑完後，若名稱不同請到 ruleset 調整。"
