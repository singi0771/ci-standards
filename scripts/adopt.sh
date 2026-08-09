#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# 把 ci-standards 公版導入 / 升級一個專案（macOS / Linux / Windows Git Bash）
#
#   ./adopt.sh                       # 導入或升級目前目錄
#   ./adopt.sh --dry-run             # 只印計畫，不動任何檔案
#   ./adopt.sh --target ../MyProj    # 指定目標
#   ./adopt.sh --std ~/ci-standards  # 指定公版 clone 位置
#   ./adopt.sh --ref v1.1.0          # 釘死特定版本（預設 v1）
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
REF="v1"
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

# 安全閥：不准把公版導入公版自己。
# 公版的呼叫端刻意用 `uses: ./...` 做 dogfooding；被這支腳本改成
# `owner/repo@ref` 之後，PR 上跑的就不再是「這個 PR 的版本」，
# 綠燈會變成假的。（這正是 2026-08-08 真的發生過的事故。）
if [ -d "$TARGET_ROOT/templates/consumer-repo/.github" ]; then
  die "目標看起來就是 ci-standards 公版本身（有 templates/consumer-repo/）。
    公版不需要導入自己 —— 它已經用 uses: ./ 呼叫自己的 reusable。
    要測試這支腳本請用 scripts/test-adopt.sh。"
fi

# ── 公版範本 ─────────────────────────────────────────────────
TMP_CLONE=""
if [ -z "$STD" ]; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
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

cleanup_tmp() { if [ -n "$TMP_CLONE" ]; then rm -rf "$TMP_CLONE"; fi; }
trap cleanup_tmp EXIT

info "── 目標：$TARGET_ROOT"
info "── 公版：$STD（ref: $REF，uses: $USES_REPO）"
info ""

# ── 偵測技術棧 ───────────────────────────────────────────────
found_any() {
  [ -n "$(find . -maxdepth "$1" -name "$2" -not -path './.git/*' -print -quit 2>/dev/null)" ]
}

HAS_DOCKERFILE=false
if [ -f Dockerfile ]; then HAS_DOCKERFILE=true; fi
HAS_PY=false
if [ -f requirements.txt ] || [ -f pyproject.toml ] || [ -f setup.py ] || found_any 2 '*.py'; then
  HAS_PY=true
fi
HAS_SH=false
if found_any 3 '*.sh'; then HAS_SH=true; fi
PYVER="3.12"
if [ -f .python-version ]; then PYVER="$(tr -d ' \r\n' < .python-version)"; fi

# ── 判斷模式：全新安裝 vs 升級 ───────────────────────────────
MODE="install"
if [ -f .github/workflows/ci.yml ] || [ -f .github/workflows/security.yml ]; then
  MODE="upgrade"
fi

info "偵測結果："
info "  模式         : $MODE $( [ "$MODE" = upgrade ] && echo '（已有呼叫端，改用合併模式）' || echo '（全新導入）')"
info "  Dockerfile   : $HAS_DOCKERFILE"
info "  Python       : $HAS_PY（版本 $PYVER）"
info "  shell script : $HAS_SH"
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
    copilot-autofix-ci-security.yml) echo "$STD/.github/workflows/copilot-autofix-reusable.yml" ;;
    copilot-autofix-review.yml)    echo "$STD/.github/workflows/copilot-autofix-review-reusable.yml" ;;
    copilot-autoreview-gate.yml)   echo "$STD/.github/workflows/copilot-autoreview-reusable.yml" ;;
    *) echo "" ;;
  esac
}

# 就地更新 uses: 那一行的 owner/repo 與 ref（不動檔案其他部分）。
# 刻意跳過 `uses: ./...` —— 公版自己 dogfooding 時用相對路徑呼叫自己的 reusable，
# 把它改成 owner/repo@ref 會讓 PR 上跑的不再是「這個 PR 的版本」。
patch_uses() {
  awk -v repo="$USES_REPO" -v ref="$REF" '
    /^[[:space:]]*uses:[[:space:]]*\.\// { print; next }
    /^[[:space:]]*uses:[[:space:]]*[^ ]+\/\.github\/workflows\// {
      n=split($0, a, "/.github/workflows/")
      if (n==2) {
        split(a[2], b, "@")
        sub(/[^ ]+$/, repo "/.github/workflows/" b[1] "@" ref, $0)
      }
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
filter_with_block() {
  f="$1"; known="$2"; additions="$3"
  awk -v known="$known" -v additions="$additions" -v dropfile="$f.dropped" '
    BEGIN { split(known, K, "\n"); for (i in K) if (K[i] != "") kn[K[i]]=1 }
    /^    with:[[:space:]]*$/ { print; inblk=1; next }
    inblk && /^      / {
      line=$0
      if (line ~ /^      #/ || line ~ /^[[:space:]]*$/) { print; next }
      if (match(line, /^      [A-Za-z0-9_-]+:/)) {
        k=line; sub(/^ +/, "", k); sub(/:.*$/, "", k)
        seen[k]=1
        if (k in kn) { print } else { print k >> dropfile }
        next
      }
      print; next
    }
    inblk {
      # with: 區塊結束 —— 把缺的 key 補上
      split(additions, A, "\n")
      for (i=1; i<=length(A); i++) {
        if (A[i] == "") continue
        ak=A[i]; sub(/:.*$/, "", ak)
        if (!(ak in seen) && (ak in kn)) print "      " A[i]
      }
      inblk=0
    }
    { print }
    END {
      if (inblk) {
        split(additions, A, "\n")
        for (i=1; i<=length(A); i++) {
          if (A[i] == "") continue
          ak=A[i]; sub(/:.*$/, "", ak)
          if (!(ak in seen) && (ak in kn)) print "      " A[i]
        }
      }
    }
  ' "$f" > "$f.tmp"
  mv "$f.tmp" "$f"
}

# 全新安裝時，直接把整個 with: 區塊換成偵測結果
replace_with_block() {
  f="$1"; blk="$2"
  awk -v blk="$blk" '
    /^    with:$/ && !seen { print; printf "%s", blk; inblk=1; seen=1; next }
    inblk && /^      / { next }
    { inblk=0; print }
  ' "$f" > "$f.tmp"
  mv "$f.tmp" "$f"
}

CREATED=""; MERGED=""; KEPT=""; DROPPED_REPORT=""

# ── 兩類檔案，兩種策略 ───────────────────────────────────────
# PLUMBING：純管線，可以就地升級（保留使用者的參數與 on: 觸發設定）
PLUMBING="ci.yml security.yml copilot-autofix-ci-security.yml copilot-autofix-review.yml copilot-autoreview-gate.yml"
# PROJECT_OWNED：內容是專案專屬的，**絕不覆蓋**。已存在就只放一份 .new 供比對。
PROJECT_OWNED="workflows/copilot-setup-steps.yml copilot-instructions.md pull_request_template.md dependabot.yml"

CI_ADDITIONS="python-version: \"$PYVER\"
run-python: $HAS_PY
run-docker-build: $HAS_DOCKERFILE
run-actionlint: true
run-shellcheck: $HAS_SH"

SEC_ADDITIONS="python-version: \"$PYVER\"
scan-docker-image: $HAS_DOCKERFILE"

plan_line() { info "  $1"; }

info "計畫："
for name in $PLUMBING; do
  if [ -f ".github/workflows/$name" ]; then plan_line "↻ 合併  .github/workflows/$name（保留既有參數、更新 uses:、移除已廢除的 input）"
  else plan_line "＋ 新增  .github/workflows/$name"; fi
done
for rel in $PROJECT_OWNED; do
  if [ -f ".github/$rel" ]; then plan_line "＝ 保留  .github/$rel（已存在，只另存 .new 供比對）"
  else plan_line "＋ 新增  .github/$rel"; fi
done
info ""

if [ "$DRY_RUN" = true ]; then
  info "（--dry-run：到此為止，沒有動任何檔案）"
  exit 0
fi

mkdir -p .github/workflows

# ── PLUMBING ─────────────────────────────────────────────────
for name in $PLUMBING; do
  dst=".github/workflows/$name"
  reu="$(reusable_for "$name")"
  known=""
  if [ -n "$reu" ] && [ -f "$reu" ]; then known="$(reusable_inputs "$reu")"; fi

  if [ ! -f "$dst" ]; then
    cp "$TPL/workflows/$name" "$dst"
    case "$name" in
      ci.yml)       replace_with_block "$dst" "$(printf '%s\n' "$CI_ADDITIONS"  | sed 's/^/      /')" ;;
      security.yml) replace_with_block "$dst" "$(printf '%s\n' "$SEC_ADDITIONS" | sed 's/^/      /')" ;;
    esac
    patch_uses "$dst"
    CREATED="$CREATED $name"
  else
    rm -f "$dst.dropped"
    case "$name" in
      ci.yml)       filter_with_block "$dst" "$known" "$CI_ADDITIONS" ;;
      security.yml) filter_with_block "$dst" "$known" "$SEC_ADDITIONS" ;;
      *)            filter_with_block "$dst" "$known" "" ;;
    esac
    patch_uses "$dst"
    if [ -s "$dst.dropped" ]; then
      while IFS= read -r k; do
        DROPPED_REPORT="$DROPPED_REPORT
    $name → 移除已廢除的 input：$k"
      done < "$dst.dropped"
    fi
    rm -f "$dst.dropped"
    MERGED="$MERGED $name"
  fi
done

# ── PROJECT_OWNED ────────────────────────────────────────────
for rel in $PROJECT_OWNED; do
  src="$TPL/$rel"; dst=".github/$rel"
  [ -f "$src" ] || continue
  mkdir -p "$(dirname "$dst")"
  if [ -f "$dst" ]; then
    if cmp -s "$src" "$dst"; then
      KEPT="$KEPT $rel(相同)"
    else
      cp "$src" "$dst.new"
      KEPT="$KEPT $rel"
    fi
  else
    cp "$src" "$dst"
    CREATED="$CREATED $rel"
  fi
done

# ── 1.2.0 契約檢查：升級模式不會補 if:/secrets:，缺了要提醒重新複製 ──
# @copilot mention 必須由真人 PAT 發出（bot 發的會被 coding agent 忽略），
# 所以這兩支薄殼需要 secrets: 區塊把 COPILOT_TRIGGER_PAT 傳進公版。
PAT_WARN=""
for name in copilot-autofix-review.yml copilot-autofix-ci-security.yml; do
  dst=".github/workflows/$name"
  if [ -f "$dst" ] && ! grep -q "copilot-trigger-pat" "$dst"; then
    PAT_WARN="$PAT_WARN
    $name → 缺 secrets: copilot-trigger-pat（1.2.0 契約變更）"
  fi
done

# ── 報告 ─────────────────────────────────────────────────────
info "───────────────────────────────────────────────────────────"
if [ -n "$CREATED" ]; then info "＋ 新增：$CREATED"; fi
if [ -n "$MERGED" ];  then info "↻ 合併：$MERGED"; fi
if [ -n "$KEPT" ];    then info "＝ 保留（未覆蓋，另存 .new）：$KEPT"; fi
if [ -n "$DROPPED_REPORT" ]; then
  info ""
  warn "以下 input 在新版公版已不存在，已從呼叫端移除（留著會讓 workflow 直接 invalid input 起不來）：$DROPPED_REPORT"
fi
if [ -n "$PAT_WARN" ]; then
  info ""
  warn "以下薄殼是舊契約，升級模式不會自動改 if:/secrets: —— 請從 templates/ 重新複製，並在 repo secrets 設定 COPILOT_TRIGGER_PAT（見公版 README「自動修復閉環」）：$PAT_WARN"
fi
info "───────────────────────────────────────────────────────────"

cat <<'NEXT'

接下來：

 1. git diff  ← 先看清楚改了什麼，尤其是升級模式

 2. 若有 *.new 檔案：那是新版範本，跟你現有的比對後自行取捨，
    處理完把 .new 刪掉。（copilot-instructions.md 這類是專案專屬內容，
    腳本刻意不覆蓋。）

 3. ⚠️ 全新導入務必改 .github/copilot-instructions.md ——
    把「專案概觀 / 開發與測試指令 / 程式碼慣例」換成本專案實況。
    沒改是導入後最常見的失敗原因。

 4. 送出（不需要 gh，PR 可以用瀏覽器開）
      git checkout -b chore/adopt-ci-standards
      git add .github && git commit -m "chore: 導入/升級 ci-standards 公版"
      git push -u origin chore/adopt-ci-standards

 5. 等第一次 CI 跑完，再開分支保護（見公版 README）。

 ⓘ job id（ci / security）刻意不動 —— 分支保護的 check 名稱綁著它，
   改了既有 ruleset 就會對不上。
NEXT
