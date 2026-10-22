#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# 把 ci-standards 公版導入 / 升級一個專案（macOS / Linux / Windows Git Bash）
#
#   ./adopt.sh                       # 導入或升級目前目錄
#   ./adopt.sh --dry-run             # 只印計畫，不動任何檔案
#   ./adopt.sh --target ../MyProj    # 指定目標
#   ./adopt.sh --std ~/ci-standards  # 指定公版 clone 位置
#   ./adopt.sh --ref v2.0.0          # 釘死特定版本（預設 v2）
#   ./adopt.sh --uses-repo ORG/ci-standards   # 搬到組織後換掉 uses: 的 owner/repo
#
# 相依：只需要 git 與內建 shell（awk / find / cp）。
#   刻意不用 gh / jq / yq / python / curl —— 受管制的公司 Windows 上
#   那些都不保證存在。導入本身是純檔案操作，不碰網路。
#
# Windows：用 Git Bash 執行，或改用同目錄的 adopt.ps1（PowerShell 5.1 原生）。
# ─────────────────────────────────────────────────────────────
set -euo pipefail

STD_REPO_URL="https://github.com/singi0771/ci-standards.git"
DEFAULT_USES_REPO="singi0771/ci-standards"

TARGET="$PWD"
STD=""
REF="v2"
USES_REPO="$DEFAULT_USES_REPO"
DRY_RUN=false

die()  { printf '❌ %s\n' "$1" >&2; exit 1; }
info() { printf '%s\n' "$1"; }
warn() { printf '⚠️  %s\n' "$1"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --target)    TARGET="${2:?--target 需要一個路徑}";     shift 2 ;;
    --std)       STD="${2:?--std 需要一個路徑}";           shift 2 ;;
    --ref)       REF="${2:?--ref 需要一個 tag/branch}";    shift 2 ;;
    --uses-repo) USES_REPO="${2:?--uses-repo 需要 owner/repo}"; shift 2 ;;
    --dry-run)   DRY_RUN=true; shift ;;
    -h|--help)   sed -n '2,20p' "$0"; exit 0 ;;
    *) die "不認得的參數：$1（用 --help 看用法）" ;;
  esac
done

command -v git >/dev/null 2>&1 || die "找不到 git。這是唯一的必要相依。"

# 腳本自己的位置要在任何 cd 之前算好 —— $0 可能是相對路徑（./scripts/adopt.sh），
# cd 到目標 repo 之後再 dirname 就會解到錯的地方（或根本進不去）。
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --std / --target 可能是相對路徑，而下面會 cd 到目標 repo 根目錄。
# 先在使用者當初所在的目錄把 --std 解成絕對路徑。
if [ -n "$STD" ]; then
  STD="$(cd "$STD" 2>/dev/null && pwd)" || die "--std 指的路徑不存在"
fi

# ── 目標 repo ────────────────────────────────────────────────
cd "$TARGET" || die "進不去 $TARGET"
# 不是 git repo 時，往下找一層再回報。
# OneDrive / 網路磁碟很常見「外層資料夾包著真正的 clone」這種結構
# （例如 CodingProject/AdminAutoTools/AdminAutoTools/），
# 只回一句「不是 git repo」會讓人以為 clone 壞了。
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  SUGGEST=""
  for d in ./*/; do
    [ -d "$d" ] || continue
    if [ -d "$d.git" ]; then
      SUGGEST="$SUGGEST
      $(cd "$d" && pwd)"
    fi
  done
  if [ -n "$SUGGEST" ]; then
    die "$TARGET 不是 git repo，但它底下這些子目錄是 —— 你要的應該是其中之一：
$SUGGEST

    cd 進去之後再跑一次，或用 --target 指過去。
    （OneDrive／網路磁碟常見：外層資料夾包著真正的 clone）"
  fi
  die "$TARGET 不是 git repo（請先 git init 或 clone）"
fi
TARGET_ROOT="$(git rev-parse --show-toplevel)"
cd "$TARGET_ROOT"

# 保護措施：不准把公版導入公版自己。
# 公版的呼叫端刻意用 `uses: ./...` 呼叫自己，當自己的第一個使用者；被這支腳本改成
# `owner/repo@ref` 之後，PR 上跑的就不再是「這個 PR 的版本」，
# 綠燈會變成假的。（這正是 2026-08-08 真的發生過的事故。）
if [ -d "$TARGET_ROOT/templates/consumer-repo/.github" ]; then
  die "目標看起來就是 ci-standards 公版本身（有 templates/consumer-repo/）。
    公版不需要導入自己 —— 它已經用 uses: ./ 呼叫自己的 reusable。
    要測試這支腳本請用 scripts/test-adopt.sh。"
fi

# ── 公版範本 ─────────────────────────────────────────────────
TMP_CLONE=""
# trap 要在 clone 之前裝好：clone 失敗會走 die → exit，EXIT trap 才清得到暫存目錄
cleanup_tmp() { if [ -n "$TMP_CLONE" ]; then rm -rf "$TMP_CLONE"; fi; }
trap cleanup_tmp EXIT
if [ -z "$STD" ]; then
  CANDS="$SCRIPT_DIR/.."
  # 只有 CODE_WORK 真的有值才加進候選 —— 否則 "${CODE_WORK:-}/ci-standards"
  # 會變成絕對路徑 /ci-standards，機器上剛好有同名目錄就會誤判成公版。
  if [ -n "${CODE_WORK:-}" ]; then CANDS="$CODE_WORK/ci-standards
$CANDS"; fi
  while IFS= read -r cand; do
    [ -n "$cand" ] || continue
    if [ -d "$cand/templates/consumer-repo/.github" ]; then STD="$(cd "$cand" && pwd)"; break; fi
  done <<EOF
$CANDS
EOF
fi
if [ -z "$STD" ]; then
  info "本機找不到公版，改用 HTTPS 淺層 clone（只需要 443 埠）…"
  TMP_CLONE="$(mktemp -d)"
  git clone --depth 1 --branch "$REF" "$STD_REPO_URL" "$TMP_CLONE/ci-standards" >/dev/null 2>&1 \
    || die "clone 失敗。內網請確認 git 的 proxy 設定，或用 --std 指向本機既有的 clone。"
  STD="$TMP_CLONE/ci-standards"
fi
TPL="$STD/templates/consumer-repo/.github"
[ -d "$TPL" ] || die "$STD 底下找不到 templates/consumer-repo/.github"

info "── 目標：$TARGET_ROOT"
info "── 公版：${STD}（ref: ${REF}，uses: ${USES_REPO}）"
info ""

# ── 偵測用了哪些技術 ───────────────────────────────────────────────
# 偵測範圍與檔名規則要跟公版 reusable「實際會檢查的範圍」一致：
#   - 全 repo（不限深度），略過 .git 與 node_modules —— 跟 reusable 的 find 一樣。
#     限深度的話，深層的 Dockerfile / .sh / .csproj 會被判成「沒有」，
#     adopt 把開關明寫成 false，公版那邊的檢查就安靜地關掉了。
#   - 檔名分大小寫（-name）—— reusable 的 find 也分。`api.dockerfile` 不分大小寫會被當成有，
#     但 reusable 根本不會去 build 它。adopt.ps1 用 -cmatch，行為相同。
# Python 例外：只看根目錄的相依清單與兩層內的 .py（沿用舊行為，避免把 vendored 的工具腳本當成 Python 專案）。
#   count_files <maxdepth|""> <樣式>...   → 印出符合任一樣式的檔案數（maxdepth 空字串＝不限）
count_files() {
  _depth="$1"; shift
  _first=true
  for _pat in "$@"; do
    if [ "$_first" = true ]; then set -- -name "$_pat"; _first=false
    else set -- "$@" -o -name "$_pat"; fi
  done
  if [ -n "$_depth" ]; then set -- -maxdepth "$_depth" \( "$@" \); else set -- \( "$@" \); fi
  # -maxdepth 要寫在最前面（GNU find 放在後面會警告），所以重組參數順序
  find . \( -path ./.git -o -name node_modules \) -prune -o -type f "$@" -print 2>/dev/null | wc -l | tr -d ' '
}
found_any() { [ "$(count_files "$@")" -gt 0 ]; }

# Dockerfile：跟公版一樣找 Dockerfile / *.Dockerfile / Dockerfile.*（不含 *.dockerignore）
HAS_DOCKERFILE=false
if [ -n "$(find . \( -path ./.git -o -name node_modules \) -prune -o -type f \( -name Dockerfile -o -name '*.Dockerfile' -o -name 'Dockerfile.*' \) ! -name '*.dockerignore' -print 2>/dev/null | head -1)" ]; then
  HAS_DOCKERFILE=true
fi
HAS_PY=false
if [ -f requirements.txt ] || [ -f pyproject.toml ] || [ -f setup.py ] || found_any 2 '*.py'; then
  HAS_PY=true
fi
HAS_SH=false
if found_any "" '*.sh'; then HAS_SH=true; fi
# .NET：方案檔（.sln / .slnx）或專案檔（.csproj / .fsproj / .vbproj）
DOTNET_SLN="$(count_files "" '*.sln' '*.slnx')"
DOTNET_PROJ="$(count_files "" '*.csproj' '*.fsproj' '*.vbproj')"
HAS_DOTNET=false
if [ "$DOTNET_SLN" -gt 0 ] || [ "$DOTNET_PROJ" -gt 0 ]; then HAS_DOTNET=true; fi
PYVER="3.12"
# 連 UTF-8 BOM（EF BB BF）一起去掉：PowerShell 5.1 的 Set-Content -Encoding UTF8 會寫 BOM，
# 留著的話 python-version 會變成「BOM + 3.11」，setup-python 直接失敗（adopt.ps1 讀檔時會自動去掉）
if [ -f .python-version ]; then PYVER="$(tr -d '\357\273\277 \r\n\t' < .python-version)"; fi

# ── 判斷模式：全新安裝 vs 升級 ───────────────────────────────
MODE="install"
if [ -f .github/workflows/ci.yml ] || [ -f .github/workflows/security.yml ]; then
  MODE="upgrade"
fi

info "偵測結果："
info "  模式         : $MODE $( [ "$MODE" = upgrade ] && echo '（已有呼叫端，改用合併模式）' || echo '（全新導入）')"
info "  Dockerfile   : $HAS_DOCKERFILE"
info "  Python       : ${HAS_PY}（版本 ${PYVER}）"
info "  shell script : $HAS_SH"
info "  .NET         : ${HAS_DOTNET}（方案檔 ${DOTNET_SLN}、專案檔 ${DOTNET_PROJ}）"
if [ "$DOTNET_SLN" -gt 1 ] || { [ "$DOTNET_SLN" -eq 0 ] && [ "$DOTNET_PROJ" -gt 1 ]; }; then
  warn "找到不只一個 .NET 方案 / 專案檔，公版無法自動決定要建置哪一個 —— 導入後請在 ci.yml 的 with: 加上 dotnet-project: \"<路徑>\""
fi
info ""

# ─────────────────────────────────────────────────────────────
# 讀公版 reusable 宣告了哪些 input。
# 用「公版自己的宣告」當事實來源，而不是在腳本裡寫死一份清單 ——
# 公版加減 input 時這裡自動跟上，不會漂移。
# ─────────────────────────────────────────────────────────────
reusable_inputs() {
  awk '
    /^    inputs:$/ { inblk=1; next }
    inblk && /^[^ ]/ { inblk=0 }
    inblk && /^  [a-z]/ { inblk=0 }
    inblk && match($0, /^      [A-Za-z0-9_-]+:[[:space:]]*$/) {
      line=$0; sub(/^ +/, "", line); sub(/:[[:space:]]*$/, "", line); print line
    }
  ' "$1"
}

# caller 檔名 → 對應的公版 reusable
reusable_for() {
  case "$1" in
    ci.yml)                        echo "$STD/.github/workflows/ci-reusable.yml" ;;
    security.yml)                  echo "$STD/.github/workflows/security-reusable.yml" ;;
    *) echo "" ;;
  esac
}

# 就地更新 uses: 那一行的 owner/repo 與 ref（不動檔案其他部分）。
# 刻意跳過 `uses: ./...` —— 公版自己用相對路徑呼叫自己的 reusable（公版拿自己當第一個使用者），
# 把它改成 owner/repo@ref 會讓 PR 上跑的不再是「這個 PR 的版本」。
#
# 只動指向公版那兩支 reusable 的 uses:（同一個檔案裡呼叫別的 reusable 不關我們的事），
# 而且只換「owner/repo/.github/workflows/<檔名>@<ref>」那一段 ——
# 行尾的空白與 `# 註解` 原樣保留。舊版用「最後一個非空白字串」去換，
# 有行尾空白時什麼都沒換卻回報成功、有註解時還會把註解最後一個字蓋掉。
patch_uses() {
  awk -v repo="$USES_REPO" -v ref="$REF" '
    /^[[:space:]]*uses:[[:space:]]*\.\// { print; next }
    /^[[:space:]]*uses:/ && match($0, /[^ \t]+\/\.github\/workflows\/(ci|security)-reusable\.ya?ml@[^ \t#]+/) {
      s=substr($0, RSTART, RLENGTH)
      file=s; sub(/^.*\/\.github\/workflows\//, "", file); sub(/@.*$/, "", file)
      $0 = substr($0, 1, RSTART-1) repo "/.github/workflows/" file "@" ref substr($0, RSTART+RLENGTH)
    }
    { print }
  ' "$1" > "$1.tmp"
  mv "$1.tmp" "$1"
}

# 過濾 with: 區塊：
#   - 註解與空行原樣保留（不會弄丟 # max-attempts: "3" 這種提示）
#   - key 仍存在於公版 → 保留使用者現有的值（絕不覆寫他調過的設定）
#   - key 已被公版移除 → 刪掉並回報（留著會讓 workflow 直接 invalid input 起不來）
#   - 最後補上「公版有、但這個檔案沒有」的 key（只補偵測得出來的那幾個）
#
# 空行不代表區塊結束：先暫存起來，下一行還是區塊內容就照原樣吐回去；
# 區塊真的結束了，就先補 key、再吐空行（空行留在區塊「後面」，不會把補上的 key 隔開）。
# 舊版一碰到空行就當成區塊結束，空行後面的 key 既沒被過濾、還會被重複補一次。
# 找不到 with: 區塊時寫一個 $f.nowith 旗標，讓外面回報「沒合併到」而不是安靜地說完成。
filter_with_block() {
  f="$1"; known="$2"; additions="$3"
  # 多行的值走 ENVIRON，不能用 -v：BSD/macOS 內建的 awk 不接受 -v 的值裡有換行
  # （會噴 "awk: newline in string"），GNU awk 才容忍。
  ADOPT_KNOWN="$known" ADOPT_ADDITIONS="$additions" \
  awk -v dropfile="$f.dropped" -v nowithfile="$f.nowith" '
    function add_missing(   i, n, ak) {
      n=split(additions, A, "\n")
      for (i=1; i<=n; i++) {
        if (A[i] == "") continue
        ak=A[i]; sub(/:.*$/, "", ak)
        if (!(ak in seen) && (ak in kn)) print "      " A[i]
      }
    }
    BEGIN {
      known=ENVIRON["ADOPT_KNOWN"]; additions=ENVIRON["ADOPT_ADDITIONS"]
      split(known, K, "\n"); for (i in K) if (K[i] != "") kn[K[i]]=1
      pend=""
    }
    !done && /^    with:[[:space:]]*(#.*)?$/ { print; inblk=1; done=1; next }
    inblk && /^[[:space:]]*$/ { pend = pend $0 "\n"; next }
    inblk && /^      / {
      if (pend != "") { printf "%s", pend; pend="" }
      line=$0
      if (line ~ /^      #/) { print; next }
      if (match(line, /^      [A-Za-z0-9_-]+:/)) {
        k=line; sub(/^ +/, "", k); sub(/:.*$/, "", k)
        seen[k]=1
        if (k in kn) { print } else { print k >> dropfile }
        next
      }
      print; next
    }
    inblk {
      # with: 區塊結束 —— 把缺的 key 補上，再把暫存的空行吐回去
      add_missing()
      if (pend != "") { printf "%s", pend; pend="" }
      inblk=0
    }
    { print }
    END {
      if (inblk) { add_missing(); if (pend != "") printf "%s", pend }
      if (!done) print "no with: block" > nowithfile
    }
  ' "$f" > "$f.tmp"
  mv "$f.tmp" "$f"
}

# 全新安裝時，直接把整個 with: 區塊換成偵測結果
replace_with_block() {
  f="$1"; blk="$2"
  # 同上：$blk 是多行區塊，必須走 ENVIRON
  # $blk 來自命令替換，尾端換行已被吃掉，這裡要自己補 —— 否則 with: 區塊後面若還有內容，
  # 會直接黏在最後一個 key 的同一行。
  ADOPT_BLK="$blk" awk '
    BEGIN { blk=ENVIRON["ADOPT_BLK"] }
    /^    with:$/ && !seen { print; printf "%s\n", blk; inblk=1; seen=1; next }
    inblk && /^      / { next }
    { inblk=0; print }
  ' "$f" > "$f.tmp"
  mv "$f.tmp" "$f"
}

CREATED=""; MERGED=""; KEPT=""; DROPPED_REPORT=""; NOWITH_REPORT=""; MISSING_TPL=""

# 公版 reusable 宣告的 input 清單。讀不到（reusable 不見了、或 inputs: 的縮排變了）時一定要停 ——
# 空清單會讓 filter_with_block 把使用者 with: 裡的每一個 key 都當成「已廢除」刪掉。
known_for() {
  _reu="$(reusable_for "$1")"
  if [ -n "$_reu" ] && [ -f "$_reu" ]; then reusable_inputs "$_reu"; fi
}
for name in ci.yml security.yml; do
  if [ -z "$(known_for "$name")" ]; then
    die "讀不到 $(reusable_for "$name") 宣告的 inputs。
    公版 clone 不完整，或 reusable 的格式變了 —— 繼續的話會把呼叫端 with: 的設定全部當成已廢除刪掉，所以中止。"
  fi
done

# ── 兩類檔案，兩種策略 ───────────────────────────────────────
# CONFIGURED：真的帶專案設定（severity / python-version / 自訂 cron…）
#   → 就地合併，保留使用者的值與 on: 區塊。
CONFIGURED="ci.yml security.yml"
# PROJECT_OWNED：內容是專案專屬的，**絕不覆蓋**。已存在就只放一份 .new 供比對。
#   zizmor.yml 也算：使用者會在裡面放自己的放行規則。
PROJECT_OWNED="pull_request_template.md dependabot.yml zizmor.yml"

CI_ADDITIONS="run-python: $HAS_PY
python-version: \"$PYVER\"
run-dotnet: $HAS_DOTNET
run-docker-build: $HAS_DOCKERFILE
run-hadolint: $HAS_DOCKERFILE
run-actionlint: true
run-shellcheck: $HAS_SH"

# security-reusable 的 python-version 其實沒有任何步驟用到，新導入的專案不再傳它。
# run-zizmor 預設打開：workflow 的安全檢查很便宜，而且範本附的 zizmor.yml 已把公版的例外放行。
SEC_ADDITIONS="scan-docker-image: $HAS_DOCKERFILE
run-zizmor: true"

plan_line() { info "  $1"; }

info "計畫："
for name in $CONFIGURED; do
  if [ -f ".github/workflows/$name" ]; then plan_line "↻ 合併  .github/workflows/${name}（保留既有參數、更新 uses:、移除已廢除的 input）"
  else plan_line "＋ 新增  .github/workflows/$name"; fi
done
for rel in $PROJECT_OWNED; do
  if [ -f ".github/$rel" ]; then plan_line "＝ 保留  .github/${rel}（已存在，只另存 .new 供比對）"
  else plan_line "＋ 新增  .github/$rel"; fi
done
info ""

if [ "$DRY_RUN" = true ]; then
  info "（--dry-run：到此為止，沒有動任何檔案）"
  exit 0
fi

mkdir -p .github/workflows

# ── v1 → v2：呼叫端觸發條件的修補 ────────────────────────────
# 2.0.0 修了「PR 改 base 就能繞過來源分支政策」：ci.yml 的 pull_request 要多聽 edited，
# 而且 job 的 if 與 concurrency 要一起改（否則改個 PR 標題就重跑整套、還會把正在跑的那輪取消掉）。
# 三行要嘛一起換、要嘛都不動：只認 v1 範本原封不動的寫法，使用者改過的就回報請他手動處理。
V1_TYPES='    types: [opened, synchronize, reopened, ready_for_review]'
V2_TYPES='    types: [opened, synchronize, reopened, ready_for_review, edited]'
V1_CI_CONC='  group: ci-${{ github.ref }}'
V2_CI_CONC="  group: ci-\${{ github.ref }}-\${{ github.event.action == 'edited' && !github.event.changes.base && 'noop' || 'run' }}"
V1_IF="    if: \${{ github.event_name != 'pull_request' || !github.event.pull_request.draft }}"
V2_IF="    if: \${{ github.event_name != 'pull_request' || (!github.event.pull_request.draft && (github.event.action != 'edited' || github.event.changes.base)) }}"
# security.yml：排程重掃與 push 分開一組，免得同一分支上互相取消
V1_SEC_CONC='  group: security-${{ github.ref }}'
V2_SEC_CONC='  group: security-${{ github.event_name }}-${{ github.ref }}'

# replace_lines <檔案> <舊行> <新行> [<舊行> <新行>]... → 整行完全相同才換
replace_lines() {
  _f="$1"; shift
  ADOPT_PAIRS="$(printf '%s\n' "$@")" awk '
    BEGIN { n=split(ENVIRON["ADOPT_PAIRS"], P, "\n"); for (i=1; i<n; i+=2) map[P[i]]=P[i+1] }
    ($0 in map) { print map[$0]; next }
    { print }
  ' "$_f" > "$_f.tmp"
  mv "$_f.tmp" "$_f"
}
has_line() { grep -qxF -- "$2" "$1"; }

TRIGGER_REPORT=""
patch_v2_triggers() {
  f="$1"; name="$2"
  case "$name" in
    ci.yml)
      # 三行各自要是「v1 原樣」或「已經是 v2」其中之一；全是 v2 就沒事可做。
      # 不能只看 types 有沒有 edited 就收工 —— 使用者手動加了 edited、卻沒改 if 與 concurrency，
      # 改個 PR 標題就會重跑整套、還把正在跑的那輪取消掉，這種半套的也要補齊。
      if has_line "$f" "$V2_TYPES" && has_line "$f" "$V2_CI_CONC" && has_line "$f" "$V2_IF"; then return 0; fi
      if { has_line "$f" "$V1_TYPES"   || has_line "$f" "$V2_TYPES"; } \
         && { has_line "$f" "$V1_CI_CONC" || has_line "$f" "$V2_CI_CONC"; } \
         && { has_line "$f" "$V1_IF"      || has_line "$f" "$V2_IF"; }; then
        replace_lines "$f" "$V1_TYPES" "$V2_TYPES" "$V1_CI_CONC" "$V2_CI_CONC" "$V1_IF" "$V2_IF"
        TRIGGER_REPORT="$TRIGGER_REPORT
    ci.yml → pull_request 加上 edited（改 base 時重跑來源分支政策），job if 與 concurrency 一併更新"
      else
        TRIGGER_REPORT="$TRIGGER_REPORT
    ci.yml → ⚠️ 觸發條件不是範本原樣，沒有自動改。請照公版範本手動加上 edited 與對應的 if / concurrency
             （有設 restricted-base-branches 時一定要做，否則 PR 改 base 就能繞過來源分支政策）"
      fi ;;
    security.yml)
      if has_line "$f" "$V1_SEC_CONC"; then
        replace_lines "$f" "$V1_SEC_CONC" "$V2_SEC_CONC"
        TRIGGER_REPORT="$TRIGGER_REPORT
    security.yml → concurrency 依事件分組（排程重掃不再跟 push 互相取消）"
      fi ;;
  esac
}

# ── CONFIGURED：就地合併 ─────────────────────────────────────
for name in $CONFIGURED; do
  dst=".github/workflows/$name"
  known="$(known_for "$name")"

  if [ ! -f "$dst" ]; then
    cp "$TPL/workflows/$name" "$dst"
    case "$name" in
      ci.yml)       replace_with_block "$dst" "$(printf '%s\n' "$CI_ADDITIONS"  | sed 's/^/      /')" ;;
      security.yml) replace_with_block "$dst" "$(printf '%s\n' "$SEC_ADDITIONS" | sed 's/^/      /')" ;;
    esac
    patch_uses "$dst"
    CREATED="$CREATED $name"
  else
    rm -f "$dst.dropped" "$dst.nowith"
    # CRLF → LF：adopt.ps1 讀檔時就把 CRLF 換掉、寫回 LF，這裡要一樣，兩支的產出才會相同；
    # 留著 \r 的話，awk 會把它當成 ref 的一部分，換完的那一行就少了 \r、整份檔案行尾混雜。
    tr -d '\r' < "$dst" > "$dst.tmp" && mv "$dst.tmp" "$dst"
    case "$name" in
      ci.yml)       filter_with_block "$dst" "$known" "$CI_ADDITIONS" ;;
      security.yml) filter_with_block "$dst" "$known" "$SEC_ADDITIONS" ;;
    esac
    patch_uses "$dst"
    patch_v2_triggers "$dst" "$name"
    if [ -s "$dst.dropped" ]; then
      while IFS= read -r k; do
        DROPPED_REPORT="$DROPPED_REPORT
    $name → 移除已廢除的 input：$k"
      done < "$dst.dropped"
    fi
    if [ -f "$dst.nowith" ]; then
      NOWITH_REPORT="$NOWITH_REPORT $name"
    fi
    rm -f "$dst.dropped" "$dst.nowith"
    MERGED="$MERGED $name"
  fi
done

# ── PROJECT_OWNED ────────────────────────────────────────────
# zizmor.yml 裡有一條「指向公版的 uses: 只要求釘 tag」的放行規則，寫死了公版的 owner/repo。
# 搬到組織（--uses-repo）時要跟著換，否則那條規則對不到、zizmor 會開始抱怨 @v1 沒釘 SHA。
# 只換那一個字串，使用者自己加的規則原樣保留；既有的檔案、新建的檔案、另存的 .new 都要換 ——
# 搬家時最常見的情況正是「專案早就導入過、zizmor.yml 已經在那裡」。
patch_zizmor_owner() {
  # 同一行出現好幾次就全部換（跟 adopt.ps1 的 .Replace() 一致）；行尾、編碼原樣保留。
  # BINMODE=3：Git Bash 的 gawk 預設用文字模式讀寫，會把使用者檔案的 CRLF 悄悄變成 LF
  # （adopt.ps1 不會），兩支產出就不一樣了。其他 awk 不認得這個變數，設了也無害。
  ADOPT_OLD="\"$DEFAULT_USES_REPO/*\"" ADOPT_NEW="\"$USES_REPO/*\"" awk -v BINMODE=3 '
    BEGIN { old=ENVIRON["ADOPT_OLD"]; new=ENVIRON["ADOPT_NEW"] }
    {
      out=""; rest=$0
      while ((i=index(rest, old)) > 0) { out = out substr(rest, 1, i-1) new; rest = substr(rest, i+length(old)) }
      print out rest
    }
  ' "$1" > "$1.tmp"
  mv "$1.tmp" "$1"
}
for rel in $PROJECT_OWNED; do
  src="$TPL/$rel"; dst=".github/$rel"
  # 範本不見了要講出來（多半是公版改了檔名），不能安靜跳過、還印「導入完成」
  if [ ! -f "$src" ]; then MISSING_TPL="$MISSING_TPL $rel"; continue; fi
  mkdir -p "$(dirname "$dst")"
  migrate_zizmor=false
  if [ "$rel" = "zizmor.yml" ] && [ "$USES_REPO" != "$DEFAULT_USES_REPO" ]; then migrate_zizmor=true; fi
  if [ -f "$dst" ]; then
    if [ "$migrate_zizmor" = true ]; then patch_zizmor_owner "$dst"; fi
    cp "$src" "$dst.new"
    if [ "$migrate_zizmor" = true ]; then patch_zizmor_owner "$dst.new"; fi
    # 跟範本（換過 owner 之後）一模一樣就不留 .new —— 否則每次重跑都會生一份沒差異的檔案
    if cmp -s "$dst.new" "$dst"; then
      rm -f "$dst.new"
      KEPT="$KEPT $rel(相同)"
    else
      KEPT="$KEPT $rel"
    fi
  else
    cp "$src" "$dst"
    if [ "$migrate_zizmor" = true ]; then patch_zizmor_owner "$dst"; fi
    CREATED="$CREATED $rel"
  fi
done

# ── 報告 ─────────────────────────────────────────────────────
info "───────────────────────────────────────────────────────────"
if [ -n "$CREATED" ];    then info "＋ 新增：$CREATED"; fi
if [ -n "$MERGED" ];     then info "↻ 合併：$MERGED"; fi
if [ -n "$KEPT" ];       then info "＝ 保留（未覆蓋，另存 .new）：$KEPT"; fi
if [ -n "$DROPPED_REPORT" ]; then
  info ""
  warn "以下 input 在新版公版已不存在，已從呼叫端移除（留著會讓 workflow 直接 invalid input 起不來）：$DROPPED_REPORT"
fi
if [ -n "$TRIGGER_REPORT" ]; then
  info ""
  info "觸發條件（v2）：$TRIGGER_REPORT"
fi
if [ -n "$NOWITH_REPORT" ]; then
  info ""
  warn "這些檔案找不到「    with:」區塊，input 沒有合併（沒移除廢除的、也沒補新的），請手動對照範本：$NOWITH_REPORT"
fi
if [ -n "$MISSING_TPL" ]; then
  info ""
  warn "公版裡找不到這些範本，沒有導入：$MISSING_TPL（公版 clone 可能不完整）"
fi
info "───────────────────────────────────────────────────────────"

cat <<'NEXT'

接下來：

 1. git diff  ← 先看清楚改了什麼，尤其是升級模式

 2. 若有 *.new 檔案：那是新版範本，跟你現有的比對後自行取捨，
    處理完把 .new 刪掉。（zizmor.yml、dependabot.yml 這類是專案專屬內容，
    腳本刻意不覆蓋。）

 3. 送出（不需要 gh，PR 可以用瀏覽器開）
      git checkout -b chore/adopt-ci-standards
      git add .github && git commit -m "chore: 導入/升級 ci-standards 公版"
      git push -u origin chore/adopt-ci-standards

 4. 等第一次 CI 跑完，再開分支保護（見公版 README）。
    不是每個 repo 都設得了（例如 Free 方案的 private repo）—— 設不了時 Gate 照跑、
    紅燈只能提醒、擋不住 merge，補位做法見 README「沒辦法設分支保護時」。

 5. 第一次跑 Security Scan 時，zizmor（workflow 安全檢查）可能會挑你自己寫的
    workflow 的毛病（沒釘 SHA 的 action、權限太大…）。那是真的該修；
    確定是誤判才放進 .github/zizmor.yml，寫法見公版 README。

 ⓘ job id（ci / security）刻意不動 —— 分支保護的 check 名稱綁著它，
   改了既有 ruleset 就會對不上。
NEXT
