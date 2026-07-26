#!/usr/bin/env bash
# 自動化迴圈驗證用的 canary script（故意寫壞，用來測 CI 會不會擋、Copilot 會不會修）
set -euo pipefail

TARGET=$1

# 故意的錯誤 1：未引用的變數（shellcheck SC2086）
# 若 TARGET 含空白或萬用字元，會刪到非預期的檔案
rm -rf $TARGET

# 故意的錯誤 2：用 ls 的輸出當迴圈來源（shellcheck SC2045）
for f in $(ls *.log); do
  echo $f
done
