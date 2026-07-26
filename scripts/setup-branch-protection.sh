#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# 一鍵為指定 repo 的 default branch 建立/更新分支保護 ruleset：
#   - 必須開 PR 才能改 main（禁止直接 push）
#   - 要求對話解決
#   - 必須通過 Security Gate 與 CI Gate 才能 merge
#   - 禁止 force push / 刪除分支
#
# 需求：已安裝並登入 GitHub CLI（gh auth login），且對目標 repo 有 admin 權限
# 用法：./scripts/setup-branch-protection.sh <owner>/<repo>
#   例：./scripts/setup-branch-protection.sh cecigehlpj/AdminAutoTools
#
# 可用環境變數覆寫（見下方說明）：
#   REQUIRED_APPROVALS=1 ./scripts/setup-branch-protection.sh <owner>/<repo>
#   STRICT_CHECKS=true   ./scripts/setup-branch-protection.sh <owner>/<repo>
# ─────────────────────────────────────────────────────────────
set -euo pipefail

REPO="${1:?用法: $0 <owner>/<repo>}"
RULESET_NAME="CI Standard - main protection"

# 需要幾個人 approve 才能 merge。
#
# 預設 0，這是刻意的 —— 設 1 而團隊只有你一個人時，PR 會永遠 merge 不了：
#   1) GitHub 不允許 PR 作者 approve 自己的 PR
#   2) Copilot code review 送出的是 COMMENT 類型 review，它不會 approve
#   3) ruleset 預設沒有 bypass，連 admin 都繞不過
# 0 依然強制「必須開 PR + 必須通過 status checks」，只是不強制人工 approve。
# 有第二位固定 reviewer 之後再改成 1。
REQUIRED_APPROVALS="${REQUIRED_APPROVALS:-0}"

# 是否要求分支必須與 main 同步後才能 merge（strict / "Require branches to be up to date"）。
# 預設 false：Copilot 自動修正會頻繁 push，開 strict 會讓 PR 一直被要求 rebase + 重跑全套掃描，
# 導入初期非常擾人。流程穩定後再改成 true。
STRICT_CHECKS="${STRICT_CHECKS:-false}"

echo "→ 目標 repo：$REPO"
echo "  required approvals：$REQUIRED_APPROVALS"
echo "  strict status checks：$STRICT_CHECKS"

# required_status_checks 的 context 必須對應「呼叫端 job id / 公版 job 名」。
#   security.yml 的 job id 是 security；公版彙總 job 名是 Security Gate
#   ci.yml       的 job id 是 ci      ；公版彙總 job 名是 CI Gate
# 只認彙總 gate、不要逐一列出各掃描 job —— 有 if 條件的 job 被 skip 時
# required check 永遠不回報，PR 會卡死。
PAYLOAD=$(cat <<JSON
{
  "name": "$RULESET_NAME",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] }
  },
  "rules": [
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": $REQUIRED_APPROVALS,
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": true
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": $STRICT_CHECKS,
        "required_status_checks": [
          { "context": "security / Security Gate" },
          { "context": "ci / CI Gate" }
        ]
      }
    },
    { "type": "non_fast_forward" },
    { "type": "deletion" }
  ]
}
JSON
)

# 找有沒有同名 ruleset。原本是無條件 POST，重跑一次就會多出一份同名 ruleset，
# 兩份規則疊加之後很難 debug。
EXISTING_ID=$(gh api "repos/$REPO/rulesets" \
  --jq ".[] | select(.name == \"$RULESET_NAME\") | .id" 2>/dev/null | head -1 || true)

if [ -n "$EXISTING_ID" ]; then
  echo "→ 已存在同名 ruleset（id=$EXISTING_ID），改為更新..."
  echo "$PAYLOAD" | gh api -X PUT "repos/$REPO/rulesets/$EXISTING_ID" \
    -H "Accept: application/vnd.github+json" --input -
else
  echo "→ 建立新的 ruleset..."
  echo "$PAYLOAD" | gh api -X POST "repos/$REPO/rulesets" \
    -H "Accept: application/vnd.github+json" --input -
fi

echo
echo "✅ 完成。到 $REPO → Settings → Rules → Rulesets 可檢視。"
echo
echo "⚠️ 兩件事要確認："
echo "   1. required check 名稱要和 Checks 分頁上實際出現的字串完全一致。"
echo "      務必等第一次 CI/Security 跑完再核對；名稱不符 = 永遠 pending = PR 卡死。"
echo "   2. 呼叫端 ci.yml / security.yml 的 pull_request 不可以有 paths-ignore，"
echo "      否則純文件 PR 不會觸發 workflow，required check 永遠不回報。"
