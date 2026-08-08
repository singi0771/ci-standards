#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# adopt.sh 的回歸測試。
#
#   ./scripts/test-adopt.sh
#
# 涵蓋兩條路徑，因為它們的失敗模式完全不同：
#   A. 全新導入 —— 什麼都沒有的 repo
#   B. 升級     —— 已經有舊版呼叫端的 repo（AdminAutoTools 就是這種）
#
# 升級這條特別重要：沖掉使用者調過的參數、或留下公版已廢除的 input，
# 都會讓對方的 CI 直接壞掉，而且是安靜地壞掉。
# ─────────────────────────────────────────────────────────────
set -euo pipefail

STD="$(cd "$(dirname "$0")/.." && pwd)"
ADOPT="$STD/scripts/adopt.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 立刻離開呼叫者的目錄。
# 2026-08-08 的事故：舊版 new_repo 用命令替換取路徑，cd 只發生在子 shell，
# 所有情境都跑在 ci-standards 自己身上，把 .github/ 整組改掉還跟著 commit 進 main。
# 現在起點就在暫存區，就算某個 cd 失敗也不會波及真的 repo。
cd "$WORK"

PASS=0; FAIL=0

ok()   { printf '  ✅ %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  ❌ %s\n' "$1"; FAIL=$((FAIL+1)); }
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1（預期 [$3］，實際 [$2]）"; fi; }

has()    { if grep -qF "$2" "$1"; then ok "$3"; else bad "$3"; fi; }
hasnt()  { if grep -qF "$2" "$1"; then bad "$3"; else ok "$3"; fi; }

# ⚠️ 不要寫成 new_repo x —— 命令替換會開子 shell，cd 不會影響主 shell，
# 所有測試就會跑在呼叫者的當前目錄上（我第一版就是這樣把真的 repo 改掉了）。
# 這裡直接在主 shell 切目錄，不回傳值。
new_repo() {
  REPO_DIR="$WORK/$1"
  mkdir -p "$REPO_DIR"
  cd "$REPO_DIR"
  # 再確認一次真的切過去了 —— 這是上次事故的關鍵防線
  if [ "$PWD" != "$REPO_DIR" ]; then
    printf '❌ 沒有切到暫存目錄（現在在 %s），中止以免動到真的 repo\n' "$PWD" >&2
    exit 1
  fi
  git init -q .
  git config user.email t@t
  git config user.name t
  git commit -q --allow-empty -m init
}

# ═════════════════════════════════════════════════════════════
printf '\n▸ 情境 A：全新導入（Python + Docker + shell script）\n'
# ═════════════════════════════════════════════════════════════
new_repo fresh
printf 'FROM python:3.11\n' > Dockerfile
printf 'flask\n'            > requirements.txt
printf '3.11\n'             > .python-version
mkdir -p bin && printf '#!/bin/sh\ntrue\n' > bin/x.sh
"$ADOPT" --std "$STD" >/dev/null

CI=".github/workflows/ci.yml"; SEC=".github/workflows/security.yml"
has "$CI"  'run-python: true'          "run-python 依偵測設為 true"
has "$CI"  'run-docker-build: true'    "run-docker-build 依 Dockerfile 設為 true"
has "$CI"  'run-shellcheck: true'      "run-shellcheck 依 .sh 設為 true"
has "$CI"  'python-version: "3.11"'    "python-version 讀到 .python-version"
has "$SEC" 'scan-docker-image: true'   "scan-docker-image 依 Dockerfile 設為 true"
has ".github/copilot-instructions.md" 'Copilot 專案指引' "copilot-instructions.md 有建立"
if [ ! -e ".github/copilot-instructions.md.new" ]; then ok "全新導入不會產生多餘的 .new"; else bad "不該產生 .new"; fi

# ═════════════════════════════════════════════════════════════
printf '\n▸ 情境 B：升級既有的舊版呼叫端\n'
# ═════════════════════════════════════════════════════════════
new_repo upgrade
printf 'FROM python:3.12\n' > Dockerfile
printf 'flask\n'            > requirements.txt
mkdir -p .github/workflows

# 模擬 v1.0.0 時代的呼叫端：參數少、有已廢除的 input、使用者調過設定、
# 而且改過 cron 與 job 的觸發條件。
cat > .github/workflows/ci.yml <<'OLD'
name: CI
on:
  push:
    branches: [main]
  pull_request:
jobs:
  ci:
    uses: singi0771/ci-standards/.github/workflows/ci-reusable.yml@v1
    with:
      python-version: "3.9"
      run-docker-build: false
      legacy-option: true
OLD

cat > .github/workflows/security.yml <<'OLD'
name: Security Scan
on:
  pull_request:
  schedule:
    - cron: "30 19 * * 3"        # 這個專案自己調過的排程，必須保留
jobs:
  security:
    uses: singi0771/ci-standards/.github/workflows/security-reusable.yml@v1
    with:
      python-version: "3.9"
      severity: "CRITICAL,HIGH,MEDIUM"
      fail-on-findings: false
      obsolete-flag: "x"
OLD

printf '# 我們自己寫的 Copilot 指引\n專案專屬內容，絕不能被沖掉。\n' > .github/copilot-instructions.md

"$ADOPT" --std "$STD" --ref v1.1.0 >/dev/null

# ── 使用者調過的參數必須原封不動 ──
has "$CI"  'python-version: "3.9"'              "保留使用者的 python-version（不被偵測值覆寫）"
has "$CI"  'run-docker-build: false'            "保留使用者刻意關掉的 run-docker-build"
has "$SEC" 'severity: "CRITICAL,HIGH,MEDIUM"'   "保留使用者調寬的 severity"
has "$SEC" 'fail-on-findings: false'            "保留使用者的過渡設定 fail-on-findings"
has "$SEC" 'cron: "30 19 * * 3"'                "保留使用者自訂的 cron（on: 區塊未被覆蓋）"

# ── 公版已廢除的 input 必須移除 ──
hasnt "$CI"  'legacy-option'  "移除公版已不存在的 legacy-option"
hasnt "$SEC" 'obsolete-flag'  "移除公版已不存在的 obsolete-flag"

# ── 公版新增的 input 要補上 ──
has "$CI" 'run-actionlint:'   "補上新版才有的 run-actionlint"
has "$CI" 'run-python:'       "補上新版才有的 run-python"

# ── uses: 要更新 ref ──
has "$CI"  'ci-reusable.yml@v1.1.0'        "ci.yml 的 uses: ref 已更新"
has "$SEC" 'security-reusable.yml@v1.1.0'  "security.yml 的 uses: ref 已更新"

# ── job id 不可以被動到（分支保護綁著它）──
has "$CI"  '  ci:'        "job id 'ci' 未被更動"
has "$SEC" '  security:'  "job id 'security' 未被更動"

# ── 專案專屬檔案絕不覆蓋 ──
has ".github/copilot-instructions.md" '專案專屬內容，絕不能被沖掉' "既有 copilot-instructions.md 未被覆蓋"
if [ -f ".github/copilot-instructions.md.new" ]; then ok "新版範本另存為 .new 供比對"; else bad "應產生 .new"; fi

# ── 產生的 YAML 必須合法 ──
if command -v python3 >/dev/null 2>&1; then
  if python3 -c "
import yaml,glob,sys
for f in glob.glob('.github/workflows/*.yml'): yaml.safe_load(open(f))
" 2>/dev/null; then ok "升級後所有 workflow YAML 仍可解析"; else bad "YAML 解析失敗"; fi
fi

# ═════════════════════════════════════════════════════════════
printf '\n▸ 情境 C：冪等性（同樣的指令跑兩次，第二次不應再改動）\n'
# ═════════════════════════════════════════════════════════════
rm -f .github/copilot-instructions.md.new
git add -A >/dev/null 2>&1; git commit -qm "after first adopt"
"$ADOPT" --std "$STD" --ref v1.1.0 >/dev/null
rm -f .github/copilot-instructions.md.new
if [ -z "$(git status --porcelain)" ]; then ok "第二次執行沒有產生任何差異"; else
  bad "第二次執行仍有變動："; git --no-pager diff --stat
fi

# ═════════════════════════════════════════════════════════════
printf '\n▸ 情境 D：--dry-run 不得動到任何檔案\n'
# ═════════════════════════════════════════════════════════════
new_repo dryrun
"$ADOPT" --std "$STD" --dry-run >/dev/null
if [ ! -d .github ]; then ok "--dry-run 沒有建立任何檔案"; else bad "--dry-run 動到檔案了"; fi

# ═════════════════════════════════════════════════════════════
printf '\n▸ 情境 E：--uses-repo（搬到組織時換掉 owner/repo）\n'
# ═════════════════════════════════════════════════════════════
new_repo orgmove
"$ADOPT" --std "$STD" --uses-repo "ACME/ci-standards" >/dev/null
has "$CI" 'ACME/ci-standards/.github/workflows/ci-reusable.yml@v1' "uses: 的 owner/repo 已換成 ACME"

# ═════════════════════════════════════════════════════════════
printf '\n▸ 情境 F：巢狀結構（外層資料夾包著真正的 clone）\n'
# ═════════════════════════════════════════════════════════════
# OneDrive / 網路磁碟常見：CodingProject/AdminAutoTools/AdminAutoTools/
# 只回「不是 git repo」會讓人以為 clone 壞了，應該要提示往下一層。
mkdir -p "$WORK/wrapper"
cd "$WORK/wrapper"
new_repo wrapper/inner
cd "$WORK/wrapper"
OUT="$("$ADOPT" --std "$STD" --dry-run 2>&1 || true)"
case "$OUT" in
  *"你要的應該是其中之一"*) ok "外層目錄會提示往下一層找" ;;
  *) bad "外層目錄沒有提示子目錄（實際輸出：$OUT）" ;;
esac
case "$OUT" in
  *"/wrapper/inner"*) ok "提示中列出了正確的子目錄" ;;
  *) bad "提示中沒有列出 inner" ;;
esac

# 真的沒有任何 git repo 時，維持原本的簡短訊息
mkdir -p "$WORK/empty-dir"
cd "$WORK/empty-dir"
OUT="$("$ADOPT" --std "$STD" --dry-run 2>&1 || true)"
case "$OUT" in
  *"請先 git init 或 clone"*) ok "沒有子 repo 時維持原訊息" ;;
  *) bad "沒有子 repo 時訊息不對（實際輸出：$OUT）" ;;
esac

# ═════════════════════════════════════════════════════════════
printf '\n───────────────────────────────\n'
printf '通過 %d／失敗 %d\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
printf '全部通過 ✅\n'
