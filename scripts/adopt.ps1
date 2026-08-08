#Requires -Version 5.1
<#
.SYNOPSIS
  一鍵把 ci-standards 公版導入一個專案（Windows PowerShell 5.1 / PowerShell 7）。

.DESCRIPTION
  與同目錄的 adopt.sh 功能相同，給不想開 Git Bash 的 Windows 使用者。

  相依：只需要 git 與 Windows 內建的 PowerShell 5.1。
  刻意不用 gh / jq / yq / python / curl —— 鎖死的公司環境上那些都不保證存在。
  導入這一步完全不碰網路（除非要自己 clone 公版）。

.PARAMETER Target
  要導入的專案目錄。預設為目前目錄。

.PARAMETER Std
  ci-standards 本機 clone 的路徑。不給的話會依序找 $env:CODE_WORK\ci-standards、
  腳本自己所在的 repo，最後才用 HTTPS 淺層 clone。

.PARAMETER Ref
  要指向的公版版本，預設 v1。

.PARAMETER DryRun
  只印偵測結果，不動任何檔案。

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\adopt.ps1

  公司電腦若因群組原則擋住 .ps1，用上面這種寫法就好，不需要改機器的執行原則。

.EXAMPLE
  .\adopt.ps1 -Target ..\MyProject -Std C:\code\ci-standards
#>
[CmdletBinding()]
param(
  [string]$Target = (Get-Location).Path,
  [string]$Std    = "",
  [string]$Ref    = "v1",
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$StdRepoUrl = 'https://github.com/singi0771/ci-standards.git'

function Die([string]$m) { Write-Host "[X] $m" -ForegroundColor Red; exit 1 }

# YAML 一律寫成「UTF-8 無 BOM + LF」。
# Set-Content -Encoding UTF8 在 PS 5.1 會寫入 BOM，有些 YAML 解析器會因此爆掉；
# 而 Windows 預設的 CRLF 會讓 actionlint / shellcheck 對 run: 區塊產生怪警告。
function Write-TextFile([string]$Path, [string]$Text) {
  $lf  = $Text -replace "`r`n", "`n"
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $lf, $enc)
}
function Read-TextFile([string]$Path) {
  return [System.IO.File]::ReadAllText($Path)
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  Die "找不到 git。這是唯一的必要相依。"
}

# -Std / -Target 都可能是相對路徑，而下面會 Set-Location 到目標 repo 根目錄。
# 先在「使用者當初所在的目錄」把 -Std 解成絕對路徑，否則
# `adopt.ps1 -Target ..\MyProject -Std .\ci-standards` 會找不到公版。
if ($Std) {
  if (-not (Test-Path -LiteralPath $Std)) { Die "-Std 指的路徑不存在：$Std" }
  $Std = (Resolve-Path -LiteralPath $Std).Path
}

# ── 1. 確認目標是 git repo ───────────────────────────────────
if (-not (Test-Path -LiteralPath $Target)) { Die "進不去 $Target" }
Set-Location -LiteralPath $Target
$TargetRoot = (& git rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or -not $TargetRoot) {
  Die "$Target 不是 git repo（請先 git init 或 clone）"
}
$TargetRoot = $TargetRoot.Trim()
Set-Location -LiteralPath $TargetRoot

# ── 2. 找到公版範本 ──────────────────────────────────────────
$TmpClone = ""
if (-not $Std) {
  $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
  $cands = @()
  if ($env:CODE_WORK) { $cands += (Join-Path $env:CODE_WORK 'ci-standards') }
  $cands += (Join-Path $scriptDir '..')
  foreach ($c in $cands) {
    if (Test-Path -LiteralPath (Join-Path $c 'templates\consumer-repo\.github')) {
      $Std = (Resolve-Path -LiteralPath $c).Path; break
    }
  }
}
if (-not $Std) {
  Write-Host "本機找不到公版，改用 HTTPS 淺層 clone（只需要 443 埠）..."
  $TmpClone = Join-Path ([System.IO.Path]::GetTempPath()) ("ci-std-" + [Guid]::NewGuid().ToString('N'))
  & git clone --depth 1 --branch $Ref $StdRepoUrl (Join-Path $TmpClone 'ci-standards') 2>$null | Out-Null
  if ($LASTEXITCODE -ne 0) {
    Die "clone 失敗。內網請確認 git 的 proxy 設定（git config --global http.proxy ...），或用 -Std 指向本機既有的 clone。"
  }
  $Std = Join-Path $TmpClone 'ci-standards'
}
$Tpl = Join-Path $Std 'templates\consumer-repo\.github'
if (-not (Test-Path -LiteralPath $Tpl)) { Die "$Std 底下找不到 templates\consumer-repo\.github" }

Write-Host "-- 目標: $TargetRoot"
Write-Host "-- 公版: $Std (ref: $Ref)"
Write-Host ""

# ── 3. 偵測技術棧 ────────────────────────────────────────────
function Test-AnyFile([string]$Filter, [int]$Depth) {
  $items = Get-ChildItem -Path . -Filter $Filter -Recurse -Depth $Depth -File -ErrorAction SilentlyContinue |
           Where-Object { $_.FullName -notmatch '\\\.git\\' } | Select-Object -First 1
  return [bool]$items
}

$HasDockerfile = Test-Path -LiteralPath 'Dockerfile'
$HasPy = (Test-Path 'requirements.txt') -or (Test-Path 'pyproject.toml') -or
         (Test-Path 'setup.py') -or (Test-AnyFile '*.py' 2)
$HasSh = Test-AnyFile '*.sh' 3

$PyVer = '3.12'
if (Test-Path -LiteralPath '.python-version') {
  $PyVer = (Read-TextFile '.python-version').Trim()
}

function B([bool]$v) { if ($v) { 'true' } else { 'false' } }

Write-Host "偵測結果:"
Write-Host ("  Dockerfile   : {0}   -> run-docker-build / scan-docker-image" -f (B $HasDockerfile))
Write-Host ("  Python       : {0} (版本 {1})   -> run-python" -f (B $HasPy), $PyVer)
Write-Host ("  shell script : {0}   -> run-shellcheck" -f (B $HasSh))
Write-Host ""

function Remove-TmpClone {
  if ($TmpClone -and (Test-Path -LiteralPath $TmpClone)) {
    Remove-Item -LiteralPath $TmpClone -Recurse -Force -ErrorAction SilentlyContinue
  }
}

if ($DryRun) {
  Write-Host "(-DryRun: 到此為止，沒有動任何檔案)"
  Remove-TmpClone
  exit 0
}

# ── 4. 備份既有 workflow ─────────────────────────────────────
$wf = '.github\workflows'
if ((Test-Path -LiteralPath $wf) -and (Get-ChildItem -LiteralPath $wf -Force | Measure-Object).Count -gt 0) {
  $n = 1
  while (Test-Path -LiteralPath ("$wf.backup-$n")) { $n++ }
  $bk = "$wf.backup-$n"
  Copy-Item -LiteralPath $wf -Destination $bk -Recurse
  Write-Host "[!] 已有 .github\workflows，先備份到 $bk" -ForegroundColor Yellow
  Get-ChildItem -LiteralPath $bk | ForEach-Object { Write-Host "     $($_.Name)" }
  Write-Host ""
}

# ── 5. 複製範本 ──────────────────────────────────────────────
New-Item -ItemType Directory -Force -Path '.github' | Out-Null
Copy-Item -Path (Join-Path $Tpl '*') -Destination '.github' -Recurse -Force
Write-Host "[OK] 已複製範本到 .github\"

# ── 6. 依偵測結果改參數 ──────────────────────────────────────
$ciPath = '.github\workflows\ci.yml'
$ci = Read-TextFile $ciPath
$ciWith = @"
    with:
      python-version: "$PyVer"
      run-python: $(B $HasPy)
      run-docker-build: $(B $HasDockerfile)
      run-actionlint: true
      run-shellcheck: $(B $HasSh)
"@
# 取代第一個 with: 區塊（含其下所有 6 空格縮排的行）
$ci = [regex]::Replace($ci, '(?m)^    with:\r?\n(?:      .*\r?\n)+', ($ciWith -replace "`r`n","`n") + "`n", 1)
Write-TextFile $ciPath $ci

$secPath = '.github\workflows\security.yml'
$sec = Read-TextFile $secPath
$sec = [regex]::Replace($sec, '(?m)^(\s*)scan-docker-image:.*$', ('${1}scan-docker-image: ' + (B $HasDockerfile)))
$sec = [regex]::Replace($sec, '(?m)^(\s*)python-version:.*$',   ('${1}python-version: "' + $PyVer + '"'))
Write-TextFile $secPath $sec
Write-Host "[OK] 已依偵測結果調整 ci.yml / security.yml"

# ── 7. 換掉 @v1 為指定的 ref ─────────────────────────────────
if ($Ref -ne 'v1') {
  Get-ChildItem -LiteralPath $wf -Filter '*.yml' | ForEach-Object {
    $t = Read-TextFile $_.FullName
    # 只換行尾的 @v1（uses: 那幾行）。註解裡的 @v1 不在行尾，不會被動到。
    $t = [regex]::Replace($t, '(?m)@v1$', "@$Ref")
    Write-TextFile $_.FullName $t
  }
  Write-Host "[OK] 已把 uses: 的 ref 換成 $Ref"
}

Remove-TmpClone

# ── 8. 後續步驟 ──────────────────────────────────────────────
@'

-----------------------------------------------------------
[OK] 檔案就位。接下來（依序）：

 1. [必改] .github\copilot-instructions.md
    把「專案概觀 / 開發與測試指令 / 程式碼慣例」換成本專案實況。
    沒改是導入後最常見的失敗原因 —— Copilot 會照著錯的指令跑。

 2. 檢查產生的內容
      git diff --stat
      type .github\workflows\ci.yml

 3. 若專案沒有 pip / docker 相依，把 .github\dependabot.yml 裡
    用不到的 package-ecosystem 區塊刪掉。

 4. 送出（不需要 gh，PR 可以用瀏覽器開）
      git checkout -b chore/adopt-ci-standards
      git add .github
      git commit -m "chore: 導入 ci-standards 公版"
      git push -u origin chore/adopt-ci-standards

 5. 等第一次 CI 跑完（check 名稱要先存在於 GitHub），再開分支保護。
    三選一：
      a) scripts/setup-branch-protection.sh <owner>/<repo>   （需要 gh + bash）
      b) repo -> Settings -> Rules -> Rulesets -> 手動建立
      c) 組織層級 ruleset 一次涵蓋所有 repo（推薦，搬到 org 之後）

 [i] 第一次一定會有東西紅 —— 那是掃描器真的找到問題。
     先判斷是誤判還是真弱點，不要為了讓它變綠就關掉檢查。

 [i] 三支 copilot-auto* 在「導入這件事」的 PR 上不會生效 ——
     workflow_run 觸發器只認 default branch 上的檔案，
     要合併進 main 之後的下一個 PR 才會動。不是壞掉。
-----------------------------------------------------------
'@ | Write-Host
