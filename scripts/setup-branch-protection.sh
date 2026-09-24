#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# 一鍵為指定 repo 的分支建立/更新分支保護 ruleset：
#   - 必須開 PR 才能改（禁止直接 push）
#   - 要求對話解決
#   - 必須通過指定的 status check 才能 merge（預設是 Security Gate 與 CI Gate）
#   - 禁止 force push / 刪除分支
#
# 需求：已安裝並登入 GitHub CLI（gh auth login），且對目標 repo 有 **admin** 權限
#
# 用法：./scripts/setup-branch-protection.sh <owner>/<repo> [分支...]
#   ./scripts/setup-branch-protection.sh acme/app                 # 只保護 default branch
#   ./scripts/setup-branch-protection.sh acme/app main develop    # 兩條長壽分支一起保護
#   ./scripts/setup-branch-protection.sh acme/app 'release/*'     # 支援 fnmatch 樣式
#   ./scripts/setup-branch-protection.sh acme/app main --dry-run  # 只印 payload，不打 API
#
# 分支名稱刻意不寫死：用什麼分支模型（只有 main、main+develop、GitFlow…）
# 是各專案自己的決定，公版只提供「怎麼保護」。
#
# 可用環境變數覆寫（見下方說明）：
#   REQUIRED_APPROVALS=1 ./scripts/setup-branch-protection.sh <owner>/<repo>
#   STRICT_CHECKS=true   ./scripts/setup-branch-protection.sh <owner>/<repo>
#   REQUIRED_CHECKS="ci / CI Gate,security / Security Gate,adopt regression gate" ...
#   RULESET_NAME="自訂名稱" ...
# ─────────────────────────────────────────────────────────────
set -euo pipefail

# 旗標要先解析完，才輪到必填的 <owner>/<repo> ——
# 反過來的話 `--help` 會被當成 repo 名稱，直接去打 repos/--help/rulesets。
#
# --dry-run：只把要送出的 ruleset 印出來，不呼叫任何 API。
#            沒有 admin 權限時也能用它產出 payload 交給有權限的人。
usage() { sed -n '/^# 用法：/,/^# ────/p' "$0" | sed 's/^# \{0,1\}//;$d'; }

DRY_RUN=false
POSITIONAL=()
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "❌ 不認得的參數：$arg（用 --help 看用法）" >&2; exit 1 ;;
    *) POSITIONAL+=("$arg") ;;
  esac
done

if [ "${#POSITIONAL[@]}" -eq 0 ]; then
  echo "❌ 缺少目標 repo。" >&2; usage >&2; exit 1
fi
REPO="${POSITIONAL[0]}"
BRANCHES=("${POSITIONAL[@]:1}")

# 要保護哪些分支。沒給就是 default branch（維持舊行為）。
if [ "${#BRANCHES[@]}" -eq 0 ]; then
  BRANCHES=("~DEFAULT_BRANCH")
  # 沿用舊名稱，既有 repo 重跑才會是「更新」而不是多出一份。
  DEFAULT_RULESET_NAME="CI Standard - main protection"
else
  # 名稱要由**整份分支清單**決定，不能只取第一個 ——
  # 否則 `… main` 與 `… main develop` 會算成同一份 ruleset，
  # 後跑的那次會把前一次的 include 整個蓋掉（develop 的保護就這樣無聲消失）。
  _joined=""
  for _b in "${BRANCHES[@]}"; do
    if [ -n "$_joined" ]; then _joined="$_joined+"; fi
    _joined="$_joined$_b"
  done
  DEFAULT_RULESET_NAME="CI Standard - $_joined protection"
fi
RULESET_NAME="${RULESET_NAME:-$DEFAULT_RULESET_NAME}"

# 要求哪些 status check。逗號隔開，順序不影響。
#
# 只列彙總 gate、不要逐一列出各掃描 job —— 有 if 條件的 job 被 skip 時
# required check 永遠不回報，PR 會卡死。
# check 名稱的格式是「<呼叫端 job id> / <公版 job 名>」：
#   security.yml 的 job id 是 security；公版彙總 job 名是 Security Gate
#   ci.yml       的 job id 是 ci      ；公版彙總 job 名是 CI Gate
REQUIRED_CHECKS="${REQUIRED_CHECKS:-security / Security Gate,ci / CI Gate}"

# 需要幾個人 approve 才能 merge。
#
# 預設 0，這是刻意的 —— 設 1 而團隊只有你一個人時，PR 會永遠 merge 不了：
#   1) GitHub 不允許 PR 作者 approve 自己的 PR
#   2) ruleset 預設沒有 bypass，連 admin 都繞不過
# 0 依然強制「必須開 PR + 必須通過 status checks」，只是不強制人工 approve。
# 有第二位固定 reviewer 之後再改成 1。
REQUIRED_APPROVALS="${REQUIRED_APPROVALS:-0}"

# 是否要求分支必須與目標分支同步後才能 merge（strict / "Require branches to be up to date"）。
# 預設 false：開 strict 會讓目標分支一有新 commit 就要求每個 PR rebase + 重跑全套掃描，
# 導入初期非常擾人。流程穩定後再改成 true。
STRICT_CHECKS="${STRICT_CHECKS:-false}"

echo "→ 目標 repo：$REPO"
echo "  ruleset 名稱：$RULESET_NAME"
echo "  保護的分支：${BRANCHES[*]}"
echo "  required checks：$REQUIRED_CHECKS"
echo "  required approvals：$REQUIRED_APPROVALS"
echo "  strict status checks：$STRICT_CHECKS"

# ── 組 JSON：分支條件 ────────────────────────────────────────
# ruleset 的 include 只認 refs/heads/<樣式> 或 ~DEFAULT_BRANCH / ~ALL 這兩個保留字。
# 進 JSON 的字串一律先跳脫反斜線與雙引號，否則名稱裡有一個 " 就會產出壞掉的
# JSON，而 gh 回的是看不懂的 parse error。
json_escape() {
  _s="$1"
  _s="${_s//\\/\\\\}"
  _s="${_s//\"/\\\"}"
  printf '%s' "$_s"
}

INCLUDE=""
for b in "${BRANCHES[@]}"; do
  case "$b" in
    '~'*)            ref="$b" ;;
    refs/heads/*)    ref="$b" ;;
    *)               ref="refs/heads/$b" ;;
  esac
  if [ -n "$INCLUDE" ]; then INCLUDE="$INCLUDE, "; fi
  INCLUDE="$INCLUDE\"$(json_escape "$ref")\""
done

# ── 組 JSON：required status checks ──────────────────────────
# 逗號先換成換行再逐行讀，**不要動全域 IFS** ——
# 改了 IFS 會影響後面所有未加引號的展開，是很典型的 shell 地雷
# （Semgrep 的 bash.lang.security.ifs-tampering 就是在抓這個）。
# check 名稱本身含空白（"ci / CI Gate"），所以用 IFS= read -r 整行讀。
CHECKS=""
while IFS= read -r c; do
  # 去掉逗號後可能殘留的前後空白（"a, b" 這種寫法）
  c="${c#"${c%%[![:space:]]*}"}"
  c="${c%"${c##*[![:space:]]}"}"
  [ -n "$c" ] || continue
  if [ -n "$CHECKS" ]; then CHECKS="$CHECKS, "; fi
  CHECKS="$CHECKS{ \"context\": \"$(json_escape "$c")\" }"
done <<EOF
$(printf '%s' "$REQUIRED_CHECKS" | tr ',' '
')
EOF
if [ -z "$CHECKS" ]; then
  echo "❌ REQUIRED_CHECKS 是空的 —— 沒有任何 check 要求等於沒有守門" >&2
  exit 1
fi

PAYLOAD=$(cat <<JSON
{
  "name": "$(json_escape "$RULESET_NAME")",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": { "include": [$INCLUDE], "exclude": [] }
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
        "required_status_checks": [$CHECKS]
      }
    },
    { "type": "non_fast_forward" },
    { "type": "deletion" }
  ]
}
JSON
)

if [ "$DRY_RUN" = true ]; then
  echo
  echo "（--dry-run：以下是會送出的 ruleset，沒有呼叫任何 API）"
  echo "$PAYLOAD"
  exit 0
fi

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

# 同一個 repo 上兩份都叫 "CI Standard - …" 的 ruleset 會**疊加**生效，
# 出問題時極難 debug（規則看起來都對，但有一份在暗處多要求了東西）。
OTHERS=$(gh api "repos/$REPO/rulesets" \
  --jq ".[] | select(.name != \"$RULESET_NAME\") | select(.name | startswith(\"CI Standard - \")) | \"\(.id)\t\(.name)\"" 2>/dev/null || true)

echo
echo "✅ 完成。到 $REPO → Settings → Rules → Rulesets 可檢視。"

if [ -n "$OTHERS" ]; then
  echo
  echo "⚠️ 這個 repo 還有其他 CI Standard 的 ruleset，規則會**疊加**生效："
  echo "$OTHERS" | while IFS="$(printf '\t')" read -r oid oname; do
    echo "     id=$oid  $oname"
    echo "       確認不再需要就刪掉：gh api -X DELETE repos/$REPO/rulesets/$oid"
  done
fi
echo
echo "⚠️ 三件事要確認："
echo "   1. required check 名稱要和 Checks 分頁上實際出現的字串完全一致。"
echo "      務必等第一次 CI/Security 跑完再核對；名稱不符 = 永遠 pending = PR 卡死。"
echo "   2. 呼叫端 ci.yml / security.yml 的 pull_request 不可以有 paths-ignore，"
echo "      否則純文件 PR 不會觸發 workflow，required check 永遠不回報。"
echo "   3. 若呼叫端的 pull_request 有加 branches: 篩選，這裡保護的分支必須都在那份清單裡，"
echo "      否則那些分支的 PR 根本不會跑 workflow，required check 一樣永遠 pending。"
