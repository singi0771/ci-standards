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
# 升級這條特別重要：洗掉使用者調過的參數、或留下公版已廢除的 input，
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

PASS=0; FAIL=0; SKIP=0

ok()   { printf '  ✅ %s\n' "$1"; PASS=$((PASS+1)); }
bad()  { printf '  ❌ %s\n' "$1"; FAIL=$((FAIL+1)); }
# 「這台機器缺少某個選配工具」不等於「測試失敗」——分開記，否則環境差異
# 會被誤報成回歸（macOS runner 有 python3 但沒有 PyYAML，就是這種情況）
skip() { printf '  ⊘ %s（跳過）\n' "$1"; SKIP=$((SKIP+1)); }
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
has "$CI"  'run-hadolint: true'        "run-hadolint 依 Dockerfile 設為 true"
has "$CI"  'python-version: "3.11"'    "python-version 讀到 .python-version"
has "$CI"  'run-dotnet: false'         "沒有 .NET 專案時 run-dotnet 為 false"
has "$CI"  'ci-reusable.yml@v2'        "全新導入預設指向 @v2"
has "$CI"  'ready_for_review, edited]' "範本的 pull_request 有 edited（改 base 時重跑來源分支政策）"
has "$SEC" 'scan-docker-image: true'   "scan-docker-image 依 Dockerfile 設為 true"
has "$SEC" 'run-zizmor: true'          "run-zizmor 預設打開"
hasnt "$SEC" 'python-version'          "security.yml 不再傳沒有任何步驟用到的 python-version"
has ".github/zizmor.yml" 'singi0771/ci-standards/*' "zizmor.yml 有建立，且放行規則指向公版"
if [ -f ".github/pull_request_template.md" ]; then ok "pull_request_template.md 有建立"; else bad "應建立 pull_request_template.md"; fi
if [ ! -e ".github/zizmor.yml.new" ]; then ok "全新導入不會產生多餘的 .new"; else bad "不該產生 .new"; fi

# ═════════════════════════════════════════════════════════════
printf '\n▸ 情境 A2：全新導入（.NET 專案、Dockerfile 在子目錄、.python-version 帶 BOM）\n'
# ═════════════════════════════════════════════════════════════
new_repo dotnet
mkdir -p src/App deploy
printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' > src/App/App.csproj
printf 'Microsoft Visual Studio Solution File\n' > App.sln
printf 'FROM mcr.microsoft.com/dotnet/aspnet:10.0\n' > deploy/Dockerfile
# PowerShell 5.1 的 Set-Content -Encoding UTF8 會寫 BOM、Windows 編輯器會寫 CRLF
printf '\357\273\2773.11\r\n' > .python-version
"$ADOPT" --std "$STD" >/dev/null
has "$CI"  'run-dotnet: true'          "偵測到 .sln / .csproj → run-dotnet 為 true"
has "$CI"  'run-python: false'         "沒有 Python 時 run-python 為 false（v2 起語言檢查預設關）"
has "$CI"  'run-docker-build: true'    "子目錄的 Dockerfile 也算有 Dockerfile"
has "$CI"  'python-version: "3.11"'    ".python-version 的 BOM 與 CRLF 被去掉"

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
    uses: singi0771/ci-standards/.github/workflows/ci-reusable.yml@v1   # 公版
    with:
      python-version: "3.9"
      run-docker-build: false

      # 分支政策（空行之後的 key 也要被正確過濾）
      restricted-base-branches: "main"
      allowed-head-branches: "develop hotfix/*"
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
    with:   # 這個專案調過的設定
      python-version: "3.9"
      severity: "CRITICAL,HIGH,MEDIUM"
      fail-on-findings: false
      upload-sarif: false
      obsolete-flag: "x"
OLD

# 專案專屬檔案：使用者改過的內容絕不能被洗掉
printf '# 我們自己的 PR 檢查清單\n專案專屬內容，絕不能被洗掉。\n' > .github/pull_request_template.md

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
hasnt "$SEC" 'python-version' "移除 v2 拿掉的 security python-version"
hasnt "$SEC" 'upload-sarif'   "移除 v2 拿掉的 upload-sarif"
check "空行後面的 key 不會被重複補上（run-python 只出現一次）" "$(grep -c 'run-python:' "$CI")" "1"
has "$CI" '# 分支政策（空行之後的 key 也要被正確過濾）' "with: 區塊裡的空行與註解原樣保留"

# ── 選配的分支政策設定：公版認得，升級時必須原封不動 ──
# 分支名稱是專案自己的決定，adopt 不能替它改或刪掉。
has "$CI" 'restricted-base-branches: "main"'            "保留使用者設定的 restricted-base-branches"
has "$CI" 'allowed-head-branches: "develop hotfix/*"'   "保留使用者設定的 allowed-head-branches"

# ── 公版新增的 input 要補上 ──
has "$CI" 'run-actionlint:'   "補上新版才有的 run-actionlint"
has "$CI" 'run-python:'       "補上新版才有的 run-python"
has "$CI" 'run-hadolint:'     "補上新版才有的 run-hadolint"
has "$SEC" 'run-zizmor:'      "補上新版才有的 run-zizmor"
if [ -f ".github/zizmor.yml" ]; then ok "升級時補上原本沒有的 zizmor.yml"; else bad "升級時應補上 zizmor.yml"; fi

# ── uses: 要更新 ref ──
has "$CI"  'ci-reusable.yml@v1.1.0   # 公版' "uses: 行尾有註解時 ref 照樣更新、註解原樣保留"
has "$SEC" 'security-reusable.yml@v1.1.0'      "uses: 行尾有空白時 ref 照樣更新"
has "$SEC" 'run-zizmor:'                       "with: 後面有註解也認得出區塊（有補上新 input）"

# ── job id 不可以被動到（分支保護綁著它）──
has "$CI"  '  ci:'        "job id 'ci' 未被更動"
has "$SEC" '  security:'  "job id 'security' 未被更動"

# ── 專案專屬檔案絕不覆蓋 ──
has ".github/pull_request_template.md" '專案專屬內容，絕不能被洗掉' "既有 pull_request_template.md 未被覆蓋"
if [ -f ".github/pull_request_template.md.new" ]; then ok "新版範本另存為 .new 供比對"; else bad "應產生 .new"; fi

# ── 觸發條件不是 v1 範本原樣 → 不自動改（只回報），檔案裡也不會出現 edited ──
hasnt "$CI" 'edited' "觸發條件被使用者改過時，不自作主張加 edited"

# ── 產生的 YAML 必須合法 ──
# 先確認 PyYAML 真的裝得起來 —— 只檢查 python3 存在是不夠的：
# macOS runner 有 python3 但沒有 PyYAML，ImportError 會被 2>/dev/null 吃掉，
# 於是「環境缺套件」被誤報成「YAML 解析失敗」。
if python3 -c 'import yaml' >/dev/null 2>&1; then
  # ⚠️ encoding='utf-8' 不能省。Windows 的 Python 預設用 **locale 編碼**
  #    （繁中版是 cp950），而這些 workflow 含中文註解、是 UTF-8 —— 於是
  #    `open(f)` 直接噴 UnicodeDecodeError，把「這台機器的 locale 不是 UTF-8」
  #    誤報成「adopt 產生的 YAML 壞了」。Linux/macOS 的 locale 就是 UTF-8，
  #    所以這條路徑在雲端永遠測不到（跟 1.2.2 的 macOS 教訓同一類）。
  #    Python 3.15 才會把預設改成 UTF-8，在那之前一律明寫。
  #
  # 錯誤訊息要留著：原本這裡是 2>/dev/null，失敗時只印「YAML 解析失敗」，
  # 完全看不出是哪一檔、什麼原因，診斷成本很高。
  if yaml_err="$(python3 -c "
import yaml,glob
for f in sorted(glob.glob('.github/workflows/*.yml')):
    try:
        yaml.safe_load(open(f, encoding='utf-8'))
    except Exception as e:
        # PyYAML 的訊息是多行（原因一行、位置一行），壓成一行才不會被 tail -1 截掉原因
        raise SystemExit('%s: %s' % (f, ' '.join(str(e).split())))
" 2>&1)"; then
    ok "升級後所有 workflow YAML 仍可解析"
  else
    bad "YAML 解析失敗：$(printf '%s' "$yaml_err" | tail -1)"
  fi
elif command -v python3 >/dev/null 2>&1; then
  skip "workflow YAML 解析檢查（python3 有，但沒裝 PyYAML）"
else
  skip "workflow YAML 解析檢查（找不到 python3）"
fi

# ═════════════════════════════════════════════════════════════
printf '\n▸ 情境 C：重複執行（同樣的指令跑兩次，第二次不應再改動）\n'
# ═════════════════════════════════════════════════════════════
# 使用者處理完 .new / .bak 之後的正常狀態
rm -f .github/pull_request_template.md.new
git add -A >/dev/null 2>&1; git commit -qm "after first adopt"
"$ADOPT" --std "$STD" --ref v1.1.0 >/dev/null
rm -f .github/pull_request_template.md.new
if [ -z "$(git status --porcelain)" ]; then ok "第二次執行沒有產生任何差異"; else
  bad "第二次執行仍有變動："; git --no-pager diff --stat; git status --porcelain
fi

# ═════════════════════════════════════════════════════════════
printf '\n▸ 情境 G：v1 範本原樣的呼叫端升級到 v2（觸發條件修補、CRLF）\n'
# ═════════════════════════════════════════════════════════════
new_repo v1-template
mkdir -p .github/workflows
cat > "$WORK/v1-ci.lf" <<'OLD'
name: CI
on:
  pull_request:
    types: [opened, synchronize, reopened, ready_for_review]
permissions:
  contents: read
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
jobs:
  ci:
    if: ${{ github.event_name != 'pull_request' || !github.event.pull_request.draft }}
    uses: singi0771/ci-standards/.github/workflows/ci-reusable.yml@v1
    with:
      python-version: "3.12"
      run-python: true
      restricted-base-branches: "main"
      allowed-head-branches: "develop"
OLD
# 用 CRLF 寫：Windows 上 core.autocrlf=true 簽出的檔案就是這樣
sed 's/$/\r/' "$WORK/v1-ci.lf" > "$CI"
cat > "$SEC" <<'OLD'
name: Security Scan
on:
  pull_request:
concurrency:
  group: security-${{ github.ref }}
  cancel-in-progress: true
jobs:
  security:
    uses: singi0771/ci-standards/.github/workflows/security-reusable.yml@v1
    with:
      upload-sarif: false
      run-zizmor: true
OLD
"$ADOPT" --std "$STD" >/dev/null
has "$CI"  'ready_for_review, edited]'                                     "v1 範本的 types 補上 edited"
has "$CI"  "github.event.action != 'edited' || github.event.changes.base"  "job if 一起改成「只有改 base 的 edited 才跑」"
has "$CI"  "format('ci-edit-{0}', github.run_id)"                                         "concurrency 一起改（改標題不會取消正在跑的 CI）"
has "$CI"  'ci-reusable.yml@v2'                                            "uses: 改指向 @v2"
# shellcheck disable=SC2016  # 故意不展開：比對的是檔案裡的 ${{ }} 原文
has "$SEC" 'group: security-${{ github.event_name }}-${{ github.ref }}'    "security.yml 的 concurrency 依事件分組"
if grep -q "$(printf '\r')" "$CI"; then bad "CRLF 呼叫端合併後應統一成 LF"; else ok "CRLF 呼叫端合併後統一成 LF（與 adopt.ps1 一致）"; fi
cp "$CI" "$WORK/v1-ci-after"
"$ADOPT" --std "$STD" >/dev/null
if cmp -s "$CI" "$WORK/v1-ci-after"; then ok "觸發條件修補可重複執行（第二次不再變動）"; else bad "第二次執行又改了 ci.yml"; fi

# 半套：使用者手動加了 edited，但 if / concurrency 還是 v1 —— 也要補齊
new_repo v1-half
mkdir -p .github/workflows
sed -e 's/ready_for_review\]/ready_for_review, edited]/' "$WORK/v1-ci.lf" > "$CI"
"$ADOPT" --std "$STD" >/dev/null
has "$CI"  "github.event.action != 'edited' || github.event.changes.base"  "只加了 edited 的半套狀態：job if 也補上"
has "$CI"  "format('ci-edit-{0}', github.run_id)"                                         "只加了 edited 的半套狀態：concurrency 也補上"

# ═════════════════════════════════════════════════════════════
printf '\n▸ 情境 I：偵測範圍要跟公版 reusable 實際檢查的範圍一致\n'
# ═════════════════════════════════════════════════════════════
new_repo deep
mkdir -p services/api/build tools/ci/scripts/x node_modules/pkg
printf 'FROM alpine\n' > services/api/build/Dockerfile          # 第 4 層：公版會 build 它
printf '#!/bin/sh\ntrue\n' > tools/ci/scripts/x/run.sh          # 第 5 層：公版會 shellcheck 它
printf '#!/bin/sh\ntrue\n' > node_modules/pkg/postinstall.sh   # node_modules：公版不看
"$ADOPT" --std "$STD" >/dev/null
has "$CI" 'run-docker-build: true' "深層目錄的 Dockerfile 也偵測得到"
has "$CI" 'run-shellcheck: true'   "深層目錄的 .sh 也偵測得到"
new_repo lowercase-dockerfile
printf 'FROM alpine\n' > api.dockerfile                        # 公版的 find 分大小寫，不會 build 它
"$ADOPT" --std "$STD" >/dev/null
has "$CI" 'run-docker-build: false' "小寫的 api.dockerfile 不算（公版也不會 build 它）"

# 不帶 --std、用相對路徑呼叫：腳本要靠自己的位置找到公版（舊版在 cd 之後才算位置，會找錯）
new_repo relative
TARGET_DIR="$PWD"
if ( cd "$STD" && ./scripts/adopt.sh --target "$TARGET_DIR" --dry-run >/dev/null 2>&1 ); then
  ok "相對路徑呼叫、不帶 --std 也找得到公版"
else
  bad "相對路徑呼叫、不帶 --std 時找不到公版"
fi

# 1.4.0 範本（已經是 edited + 新 if / concurrency）升級到 v2：觸發條件視為已完成、不再改動
new_repo v140-template
mkdir -p .github/workflows
cp "$STD/templates/consumer-repo/.github/workflows/ci.yml" "$CI"
sed -i.bak 's|ci-reusable.yml@v2|ci-reusable.yml@v1|' "$CI" && rm -f "$CI.bak"
grep -v -e 'ci-reusable.yml@' -e '^ *run-\|^ *python-version' "$CI" > "$WORK/v140-before"
"$ADOPT" --std "$STD" >/dev/null
grep -v -e 'ci-reusable.yml@' -e '^ *run-\|^ *python-version' "$CI" > "$WORK/v140-after"
if cmp -s "$WORK/v140-before" "$WORK/v140-after"; then ok "1.4.0 範本的觸發條件已是 v2 寫法，不再改動"; else bad "1.4.0 範本的觸發條件被改動了"; fi

# ═════════════════════════════════════════════════════════════
printf '\n▸ 情境 J：Dockerfile 不在根目錄（1.4.0 的 dockerfile: input）\n'
# ═════════════════════════════════════════════════════════════
# v2 的公版會自己找全 repo 的 Dockerfile，adopt 不必再寫 dockerfile:；
# 但 1.4.0 時代呼叫端已經寫好的 dockerfile: 是使用者的設定，升級時必須原封不動。
new_repo subdir-docker
mkdir -p src/Web.Api && printf 'FROM alpine\n' > src/Web.Api/Dockerfile
"$ADOPT" --std "$STD" >/dev/null
has   "$CI"  'run-docker-build: true'   "子資料夾的 Dockerfile 也會開 run-docker-build"
has   "$SEC" 'scan-docker-image: true'  "子資料夾的 Dockerfile 也會開 scan-docker-image"
hasnt "$CI"  'dockerfile:'              "v2 不必寫 dockerfile:（公版自己找全 repo）"
# awk 而不是 sed：BSD sed（macOS）的取代字串不認得 \n
awk '{ print } /^    with:$/ { print "      dockerfile: \"deploy/Custom.Dockerfile\"" }' "$CI" > "$CI.tmp" && mv "$CI.tmp" "$CI"
"$ADOPT" --std "$STD" >/dev/null
has   "$CI"  'dockerfile: "deploy/Custom.Dockerfile"' "升級時保留使用者自訂的 dockerfile:"
check "升級後仍只有一行 dockerfile:" "$(grep -c '^ *dockerfile:' "$CI")" "1"

new_repo multi-docker
mkdir -p svc/a svc/b && printf 'FROM alpine\n' > svc/a/Dockerfile && printf 'FROM alpine\n' > svc/b/Dockerfile
"$ADOPT" --std "$STD" >/dev/null
has "$CI" 'run-docker-build: true' "多個 Dockerfile 也開 Docker 檢查（v2 的公版會逐一 build）"

# ═════════════════════════════════════════════════════════════
printf '\n▸ 情境 K：1.x 留下的 Copilot 呼叫端要被明確點名（不刪，但警告不能漏）\n'
# ═════════════════════════════════════════════════════════════
new_repo copilot-leftovers
mkdir -p .github/workflows
for f in copilot-autofix-ci-security.yml copilot-autofix-review.yml copilot-autoreview-gate.yml copilot-setup-steps.yml; do
  printf 'jobs:\n  x:\n    uses: singi0771/ci-standards/.github/workflows/copilot-autofix-reusable.yml@v1\n' > ".github/workflows/$f"
done
OUT_DRY="$("$ADOPT" --std "$STD" --dry-run 2>&1)"
OUT="$("$ADOPT" --std "$STD" 2>&1)"
case "$OUT_DRY" in
  *"Copilot 呼叫端"*"copilot-autofix-ci-security.yml"*) ok "--dry-run 的計畫就會點名舊的 Copilot 呼叫端" ;;
  *) bad "--dry-run 沒有點名舊的 Copilot 呼叫端" ;;
esac
case "$OUT" in
  *"git rm"*"copilot-autofix-review.yml"*"copilot-autoreview-gate.yml"*"copilot-setup-steps.yml"*) ok "報告列出要 git rm 的四支 Copilot 檔案" ;;
  *) bad "報告沒有列出要 git rm 的 Copilot 檔案（實際輸出：${OUT}）" ;;
esac
if [ -f .github/workflows/copilot-autofix-review.yml ]; then ok "照原則不刪專案既有的檔案"; else bad "不該自動刪掉使用者的檔案"; fi
has ".github/workflows/copilot-autofix-review.yml" '@v1' "Copilot 呼叫端維持 @v1（不會被改成 v2 不存在的 reusable）"
new_repo no-copilot
OUT="$("$ADOPT" --std "$STD" 2>&1)"
case "$OUT" in
  *"Copilot 呼叫端"*) bad "沒有 Copilot 檔案時不該出現這段警告" ;;
  *) ok "沒有 Copilot 檔案時不出現警告" ;;
esac

# ═════════════════════════════════════════════════════════════
printf '\n▸ 情境 H：公版 reusable 讀不到 inputs 時要中止，不能把使用者的設定全刪掉\n'
# ═════════════════════════════════════════════════════════════
FAKE_STD="$WORK/fake-std"
mkdir -p "$FAKE_STD/.github/workflows"
cp -R "$STD/templates" "$FAKE_STD/"
cp "$STD/.github/workflows/security-reusable.yml" "$FAKE_STD/.github/workflows/"
# ci-reusable 的 inputs: 那一行格式變了 → 解析結果是空的
sed 's/^    inputs:$/    inputs:  # changed/' "$STD/.github/workflows/ci-reusable.yml" > "$FAKE_STD/.github/workflows/ci-reusable.yml"
new_repo guard
mkdir -p .github/workflows
printf 'jobs:\n  ci:\n    uses: singi0771/ci-standards/.github/workflows/ci-reusable.yml@v1\n    with:\n      run-python: true\n' > "$CI"
cp "$CI" "$WORK/guard-before"
if "$ADOPT" --std "$FAKE_STD" >/dev/null 2>&1; then bad "讀不到 inputs 時應該中止"; else ok "讀不到 inputs 時中止"; fi
if cmp -s "$CI" "$WORK/guard-before"; then ok "中止時呼叫端原封不動"; else bad "中止前已經改動了呼叫端"; fi

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
has "$CI" 'ACME/ci-standards/.github/workflows/ci-reusable.yml@v2' "uses: 的 owner/repo 已換成 ACME"
has ".github/zizmor.yml" '"ACME/ci-standards/*": ref-pin' "zizmor.yml 的放行規則也換成 ACME"
hasnt ".github/zizmor.yml" 'singi0771' "zizmor.yml 不再留著舊的 owner"

# 搬家時最常見的情況：專案早就導入過，zizmor.yml 已經在那裡、而且加過自己的規則。
# 那一條放行規則一樣要換 owner，使用者自己加的規則不能動（採納 PR #32 的 Copilot 審查意見）。
new_repo orgmove-existing
mkdir -p .github
cat > .github/zizmor.yml <<'OLD'
rules:
  unpinned-uses:
    config:
      policies:
        "singi0771/ci-standards/*": ref-pin
        "*": hash-pin
  template-injection:
    ignore:
      - my-own-workflow.yml     # 使用者自己加的
OLD
"$ADOPT" --std "$STD" --uses-repo "ACME/ci-standards" >/dev/null
has   ".github/zizmor.yml" '"ACME/ci-standards/*": ref-pin' "既有 zizmor.yml 的放行規則也換成 ACME"
has   ".github/zizmor.yml" 'my-own-workflow.yml'            "既有 zizmor.yml 裡使用者自己加的規則原樣保留"
hasnt ".github/zizmor.yml" 'singi0771'                      "既有 zizmor.yml 不再留著舊的 owner"
if [ -f ".github/zizmor.yml.new" ]; then
  has ".github/zizmor.yml.new" '"ACME/ci-standards/*": ref-pin' "另存的 zizmor.yml.new 也換了 owner"
else
  bad "使用者改過的 zizmor.yml 應另存一份 .new 供比對"
fi

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
  *) bad "外層目錄沒有提示子目錄（實際輸出：${OUT}）" ;;
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
  *) bad "沒有子 repo 時訊息不對（實際輸出：${OUT}）" ;;
esac

# ═════════════════════════════════════════════════════════════
printf '\n───────────────────────────────\n'
if [ "$SKIP" -gt 0 ]; then
  printf '通過 %d／失敗 %d／跳過 %d\n' "$PASS" "$FAIL" "$SKIP"
else
  printf '通過 %d／失敗 %d\n' "$PASS" "$FAIL"
fi
if [ "$FAIL" -gt 0 ]; then exit 1; fi

# 「跳過」不是回歸，但也**不是通過**。
# 被跳過的只有「產生的 workflow YAML 是否合法」那一項 —— 它正是唯一在驗
# adopt 產出正確性的檢查，缺了它還印「全部通過 ✅」就是假綠燈。
# CI 那邊有前置斷言擋住（見 adopt-tests.yml），本機這條路徑靠這裡擋。
if [ "$SKIP" -gt 0 ]; then
  printf '⚠️  有 %d 項被跳過 —— 這不是回歸，但「沒驗到」不等於「通過」。\n' "$SKIP"
  printf '   補齊之後再跑一次：python3 -m pip install pyyaml\n'
  exit 1
fi
printf '全部通過 ✅\n'
