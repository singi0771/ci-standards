#!/usr/bin/env bash
# 自動化迴圈驗證用的 canary script（錯誤已依 CI 與 Copilot review 意見修正）
set -euo pipefail

TARGET=$1

# 修正 SC2086：引用變數，並用 -- 終止選項解析，避免 TARGET 以 - 開頭被當成參數
rm -rf -- "$TARGET"

# 修正 SC2045/SC2035：改用 glob，nullglob 避免沒有檔案時跑到字面值 *.log
shopt -s nullglob
for f in ./*.log; do
  echo "$f"
done
