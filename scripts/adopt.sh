#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
# 一鍵把 ci-standards 公版導入一個專案（macOS / Linux / Windows Git Bash）
#
# 用法：
#   ./adopt.sh                          # 導入目前目錄
#   ./adopt.sh --target ../MyProject    # 導入指定目錄
#   ./adopt.sh --std ~/code/ci-standards   # 指定公版 clone 的位置
#   ./adopt.sh --ref v1.1.0             # 釘死特定版本（預設 v1）
#   ./adopt.sh --dry-run                # 只印要做什麼，不動檔案
#
# 相依：只需要 git 與內建 shell（POSIX 工具：awk / find / cp）。
#   刻意不用 gh / jq / yq / python / curl —— 鎖死的公司 Windows 上
#   那些都不保證存在。導入這一步完全不碰網路（除非要自己 clone 公版）。
#
# Windows：用 Git Bash 執行（Git for Windows 內建）。
#   PowerShell 使用者請改用同目錄的 adopt.ps1。
# ─────────────────────────────────────────────────────────────
set -euo pipefail

STD_REPO_URL="https://github.com/singi0771/ci-standards.git"

TARGET="$PWD"
STD=""
REF="v1"
DRY_RUN=false

die() { printf '❌ %s\n' "$1" >&2; exit 1; }
info() { printf '%s\n' "$1"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --target)  TARGET="${2:?--target 需要一個路徑}"; shift 2 ;;
    --std)     STD="${2:?--std 需要一個路徑}";       shift 2 ;;
    --ref)     REF="${2:?--ref 需要一個 tag/branch}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) die "不認得的參數：$1（用 --help 看用法）" ;;
  esac
done

command -v git >/dev/null 2>&1 || die "找不到 git。這是唯一的必要相依。"

# --std / --target 都可能是相對路徑，而下面會 cd 到目標 repo 根目錄。
# 先在「使用者當初所在的目錄」把 --std 解成絕對路徑，否則
# `adopt.sh --target ../MyProject --std ./ci-standards` 會找不到公版。
if [ -n "$STD" ]; then
  STD="$(cd "$STD" 2>/dev/null && pwd)" || die "--std 指的路徑不存在"
fi

# ── 1. 確認目標是 git repo ───────────────────────────────────
cd "$TARGET" || die "進不去 $TARGET"
git rev-parse --git-dir >/dev/null 2>&1 || die "$TARGET 不是 git repo（請先 git init 或 clone）"
TARGET_ROOT="$(git rev-parse --show-toplevel)"
cd "$TARGET_ROOT"

# ── 2. 找到公版範本 ──────────────────────────────────────────
# 順序：--std 參數 → $CODE_WORK/ci-standards → 腳本自己所在的 repo → 淺層 clone
TMP_CLONE=""
if [ -z "$STD" ]; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  for cand in "${CODE_WORK:-}/ci-standards" "$SCRIPT_DIR/.."; do
    if [ -d "$cand/templates/consumer-repo/.github" ]; then STD="$(cd "$cand" && pwd)"; break; fi
  done
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
info "── 公版：$STD（ref: $REF）"
info ""

# ── 3. 偵測技術棧 ────────────────────────────────────────────
# 一律用 if，不用 `cmd && VAR=true` —— 那種寫法在 set -e 下的行為很容易誤判，
# 而這個 repo 自己的規範就是「不要讓判斷失敗被吃掉」。
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
if [ -f .python-version ]; then
  PYVER="$(tr -d ' \r\n' < .python-version)"
fi

info "偵測結果："
info "  Dockerfile   : $HAS_DOCKERFILE   → run-docker-build / scan-docker-image"
info "  Python       : $HAS_PY (版本 $PYVER)   → run-python"
info "  shell script : $HAS_SH   → run-shellcheck"
info ""

cleanup_tmp() {
  if [ -n "$TMP_CLONE" ]; then rm -rf "$TMP_CLONE"; fi
}

if [ "$DRY_RUN" = true ]; then
  info "（--dry-run：到此為止，沒有動任何檔案）"
  cleanup_tmp
  exit 0
fi

# ── 4. 備份既有 workflow ─────────────────────────────────────
if [ -d .github/workflows ] && [ -n "$(ls -A .github/workflows 2>/dev/null)" ]; then
  BK=".github/workflows.backup"
  n=1; while [ -e "$BK-$n" ]; do n=$((n+1)); done
  BK="$BK-$n"
  cp -R .github/workflows "$BK"
  info "⚠️  已有 .github/workflows，先備份到 $BK"
  ls -1 "$BK" | sed 's/^/     /'
  info ""
fi

# ── 5. 複製範本 ──────────────────────────────────────────────
mkdir -p .github
cp -R "$TPL/." .github/
info "✅ 已複製範本到 .github/"

# ── 6. 依偵測結果改參數 ──────────────────────────────────────
# 用 awk 而不是 sed -i：BSD sed（macOS）與 GNU sed（Linux/Git Bash）的
# -i 參數不相容，寫成兩套很容易在其中一個平台上默默失效。
patch_with_block() {
  local f="$1" blk="$2"
  awk -v blk="$blk" '
    /^    with:$/ && !seen { print; printf "%s", blk; inblk=1; seen=1; next }
    inblk && /^      / { next }
    { inblk=0; print }
  ' "$f" > "$f.tmp"
  mv "$f.tmp" "$f"
}

patch_key() {
  local f="$1" key="$2" val="$3"
  awk -v k="$key" -v v="$val" '
    $0 ~ "^[[:space:]]*" k ":" { sub(/:.*/, ": " v) } { print }
  ' "$f" > "$f.tmp"
  mv "$f.tmp" "$f"
}

CI_WITH="      python-version: \"$PYVER\"
      run-python: $HAS_PY
      run-docker-build: $HAS_DOCKERFILE
      run-actionlint: true
      run-shellcheck: $HAS_SH
"
patch_with_block .github/workflows/ci.yml "$CI_WITH"
patch_key .github/workflows/security.yml "scan-docker-image" "$HAS_DOCKERFILE"
patch_key .github/workflows/security.yml "python-version" "\"$PYVER\""
info "✅ 已依偵測結果調整 ci.yml / security.yml"

# ── 7. 換掉 @v1 為指定的 ref ─────────────────────────────────
if [ "$REF" != "v1" ]; then
  # 只換行尾的 @v1（也就是 uses: 那幾行）。註解裡提到的 @v1 不在行尾，不會被動到。
  for f in .github/workflows/*.yml; do
    awk -v r="$REF" '{ gsub(/@v1$/, "@" r); print }' "$f" > "$f.tmp"
    mv "$f.tmp" "$f"
  done
  info "✅ 已把 uses: 的 ref 換成 $REF"
fi

cleanup_tmp

# ── 8. 後續步驟 ──────────────────────────────────────────────
cat <<'NEXT'

───────────────────────────────────────────────────────────
✅ 檔案就位。接下來（依序）：

 1. ⚠️ 必改：.github/copilot-instructions.md
    把「專案概觀 / 開發與測試指令 / 程式碼慣例」換成本專案實況。
    沒改是導入後最常見的失敗原因 —— Copilot 會照著錯的指令跑。

 2. 檢查產生的內容
      git diff --stat
      cat .github/workflows/ci.yml

 3. 若專案沒有 pip / docker 相依，把 .github/dependabot.yml 裡
    用不到的 package-ecosystem 區塊刪掉。

 4. 送出（不需要 gh，PR 可以用瀏覽器開）
      git checkout -b chore/adopt-ci-standards
      git add .github
      git commit -m "chore: 導入 ci-standards 公版"
      git push -u origin chore/adopt-ci-standards

 5. 等第一次 CI 跑完（check 名稱要先存在於 GitHub），再開分支保護。
    三選一：
      a) scripts/setup-branch-protection.sh <owner>/<repo>   （需要 gh）
      b) repo → Settings → Rules → Rulesets → 手動建立
      c) 組織層級 ruleset 一次涵蓋所有 repo（推薦，搬到 org 之後）
    詳見公版 README 的「分支保護」一節。

 ⓘ 第一次一定會有東西紅 —— 那是掃描器真的找到問題。
   先判斷是誤判還是真弱點，不要為了讓它變綠就關掉檢查。

 ⓘ 三支 copilot-auto* 在「導入這件事」的 PR 上不會生效 ——
   workflow_run 觸發器只認 default branch 上的檔案，
   要合併進 main 之後的下一個 PR 才會動。不是壞掉。
───────────────────────────────────────────────────────────
NEXT
