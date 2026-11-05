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
# 同一個 commit 已經有 v 開頭的 tag 就不重打。
set -euo pipefail

sha="${1:?用法：release-tag.sh <commit sha>}"
: "${REPO:?需要 REPO=owner/name}"

sha=$(gh api "repos/$REPO/commits/$sha" --jq .sha)

existing=$(gh api "repos/$REPO/tags" --paginate --jq ".[] | select(.commit.sha == \"$sha\") | .name" | grep '^v' || true)
if [ -n "$existing" ]; then
  echo "::notice::$sha 已有 tag：$existing，不重打。"
  exit 0
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

if [[ "$subject" =~ ^release:\ v?([0-9]+\.[0-9]+\.[0-9]+)([[:space:]]|$) ]]; then
  tag="v${BASH_REMATCH[1]}"
  if gh api "repos/$REPO/git/ref/tags/$tag" > /dev/null 2>&1; then
    echo "::error::$tag 已存在且指向別的 commit。發版標題的版號要往上加。"
    exit 1
  fi
else
  if [[ "$subject" =~ ^release:\ ([0-9]{4})-([0-9]{2})-([0-9]{2}) ]]; then
    day="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
  else
    day=$(TZ=Asia/Taipei date +%Y.%m.%d)
  fi
  # 日期固定長度，所以 v2026.10.30 這個前綴只會比到當天的 tag
  count=$(gh api "repos/$REPO/git/matching-refs/tags/v$day" --jq 'length')
  tag="v$day"
  if [ "$count" -gt 0 ]; then
    tag="v$day.$((count + 1))"
  fi
fi

# 標題：release: 2026-10-30 加速停車資料載入 (#16) → v2026.10.30 加速停車資料載入
title=$(printf '%s\n' "$subject" | sed -E 's/^release: (v?[0-9]+\.[0-9]+\.[0-9]+|[0-9]{4}-[0-9]{2}-[0-9]{2}) *//; s/ *\(#[0-9]+\)$//')
title="$tag${title:+ $title}"

gh release create "$tag" --repo "$REPO" --target "$sha" --title "$title" --notes-file "$notes"
echo "建立 $tag → $sha"
