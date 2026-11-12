#!/usr/bin/env bash
# 幫正式分支上的一個 commit 打 release tag 並建立 GitHub Release。
# 由 .github/workflows/release-tag.yml 在正式分支收到 push 時呼叫；補打舊版本時也可在本機跑：
#   GH_TOKEN=... REPO=owner/name bash .github/scripts/release-tag.sh <commit sha>
#
# 標題與內文取自合併進來的 PR（merge commit 的訊息是「Merge pull request #N ...」，沒有發版資訊）；
# 找不到 PR（直接 push）才用 commit 訊息。tag 依標題決定：
#   release: v1.4.0 <重點>       → v1.4.0（已存在就失敗，版號要改）
#   release: 2026-10-30 <重點>   → v2026.10.30；同一天第二次起 v2026.10.30.2、.3…
#   其他（hotfix 等）             → 台北時間今天的日期 tag，規則同上
# 同一個 commit 已經有 v 開頭的 tag 就不重打（只有 Release 沒建成時補建）。
set -euo pipefail

sha="${1:?用法：release-tag.sh <commit sha>}"
: "${REPO:?需要 REPO=owner/name}"

sha=$(gh api "repos/$REPO/commits/$sha" --jq .sha)

existing=$(gh api "repos/$REPO/tags" --paginate --jq ".[] | select(.commit.sha == \"$sha\") | .name" | grep '^v' | head -n 1 || true)
tag=""
if [ -n "$existing" ]; then
  if gh release view "$existing" --repo "$REPO" > /dev/null 2>&1; then
    echo "::notice::$sha 已有 tag 與 Release：$existing，不重打。"
    exit 0
  fi
  # 上次 tag 建好、Release 沒建成（Re-run 的情況）：沿用這個 tag，只補 Release
  echo "::notice::$sha 已有 tag：$existing，補建 Release。"
  tag="$existing"
fi

notes=$(mktemp)
pr=$(gh api "repos/$REPO/commits/$sha/pulls" --jq "[.[] | select(.merge_commit_sha == \"$sha\")][0].number // empty")
if [ -n "$pr" ]; then
  subject=$(gh api "repos/$REPO/pulls/$pr" --jq .title)
  gh api "repos/$REPO/pulls/$pr" --jq '.body // ""' > "$notes"
else
  message=$(gh api "repos/$REPO/commits/$sha" --jq .commit.message)
  subject=$(printf '%s\n' "$message" | head -n 1)
  printf '%s\n' "$message" | tail -n +2 > "$notes"
fi
sed -i '/^🤖 Generated with/d' "$notes"

# 建立 tag ref。GitHub 建立 ref 是原子操作：同名 ref 已存在時回 422，不會覆蓋。
# 連續合併時各次 run 平行執行（workflow 刻意不設 concurrency），靠這裡避免兩次 run 拿到同一個流水號。
create_tag() {
  gh api "repos/$REPO/git/refs" -f "ref=refs/tags/$1" -f "sha=$sha" > /dev/null 2>&1
}

if [ -n "$tag" ]; then
  :   # 沿用既有 tag
elif [[ "$subject" =~ ^release:\ v?([0-9]+\.[0-9]+\.[0-9]+)([[:space:]]|$) ]]; then
  tag="v${BASH_REMATCH[1]}"
  if ! create_tag "$tag"; then
    echo "::error::$tag 已存在且指向別的 commit（或建立失敗）。發版標題的版號要往上加。"
    exit 1
  fi
else
  if [[ "$subject" =~ ^release:\ ([0-9]{4})-([0-9]{2})-([0-9]{2}) ]]; then
    day="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
  else
    day=$(TZ=Asia/Taipei date +%Y.%m.%d)
  fi
  # 日期固定長度，所以 v2026.10.30 這個前綴只會比到當天的 tag。
  # 從「現有數量 + 1」開始試，被其他 run 搶先（或中間有刪過的號）就往下一號。
  # 平行 run 搶號時，流水號順序可能與合併順序相反；以 Release 的 commit 為準。
  n=$(gh api "repos/$REPO/git/matching-refs/tags/v$day" --jq 'length')
  tag=""
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    n=$((n + 1))
    if [ "$n" -eq 1 ]; then candidate="v$day"; else candidate="v$day.$n"; fi
    if create_tag "$candidate"; then tag="$candidate"; break; fi
  done
  if [ -z "$tag" ]; then
    echo "::error::連試 10 個 v$day 流水號都建立失敗，請檢查權限（contents: write）或既有 tag。"
    exit 1
  fi
fi

# 標題：release: 2026-10-30 加速停車資料載入 (#16) → v2026.10.30 加速停車資料載入
title=$(printf '%s\n' "$subject" | sed -E 's/^release: (v?[0-9]+\.[0-9]+\.[0-9]+|[0-9]{4}-[0-9]{2}-[0-9]{2}) *//; s/ *\(#[0-9]+\)$//')
title="$tag${title:+ $title}"

# tag 已在上面建立，這裡用 --verify-tag 掛到同一個 tag 上
gh release create "$tag" --repo "$REPO" --verify-tag --title "$title" --notes-file "$notes"
echo "建立 $tag → $sha"
