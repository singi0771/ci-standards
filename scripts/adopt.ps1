#Requires -Version 5.1
# ⚠️⚠️ 這個檔案必須存成「UTF-8 **有** BOM」。別把 BOM 拿掉。⚠️⚠️
#
# Windows PowerShell 5.1 讀 .ps1 時，**沒有 BOM 就用 ANSI codepage 解讀**
# （繁中機器是 cp950）。本檔的訊息全是中文，於是每個中文字都變成亂碼，
# 亂碼還會湊出讓字串提前結束的位元組 —— 結果不是「執行出錯」而是
# **連 parse 都過不了**（實測 19 個 parser error，腳本完全無法載入）。
#
# pwsh 7 預設用 UTF-8，所以在 7 上完全正常 —— 這就是它一直沒被發現的原因。
# 偏偏本檔宣告 `#Requires -Version 5.1`，主打的就是「受管制公司環境不必
# 另外裝 pwsh」，等於**唯一的目標環境正好是壞的那個**。
#
# 驗證方式（改完務必跑一次）：
#   powershell -NoProfile -Command "$e=$null; [System.Management.Automation.Language.Parser]::ParseFile('scripts\adopt.ps1',[ref]$null,[ref]$e) | Out-Null; $e.Count"
#   -> 必須輸出 0
#
#   `| Out-Null` 不能省 —— ParseFile() 會回傳 ScriptBlockAst，不導掉的話
#   會先吐一千多行的 AST，$e.Count 淹沒在裡面，根本看不出過了沒。
#   另外一定要用 `powershell`（5.1），用 `pwsh`（7）永遠是 0 —— 7 預設吃
#   UTF-8，根本不會重現這個問題，等於白驗。
#
# 注意：BOM 只加在**這支腳本自己**。腳本**產出**的 YAML 仍然是
# UTF-8 無 BOM（見底下 Write-TextFile）—— 那是對的，別一起改。
<#
.SYNOPSIS
  把 ci-standards 公版導入 / 升級一個專案（Windows PowerShell 5.1 原生，零安裝）。

.DESCRIPTION
  與同目錄的 adopt.sh 行為一致，兩者的測試情境也相同（見 scripts/test-adopt.sh）。

  兩種模式會自動判斷：
    install —— 目標沒有呼叫端，整份範本鋪上去並依偵測結果填參數
    upgrade —— 目標已有呼叫端，改用「就地合併」：
                保留使用者調過的參數與 on: 觸發設定、更新 uses:、
                移除公版已廢除的 input、補上公版新增的 input

  專案專屬的檔案（copilot-instructions.md、pull_request_template.md、
  dependabot.yml、copilot-setup-steps.yml）**絕不覆蓋** —— 已存在就只放一份
  .new 供比對。

  相依：只需要 git 與 Windows 內建的 PowerShell 5.1。
  不用 gh / jq / yq / python / curl —— 受管制的公司環境上那些都不保證存在。

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\adopt.ps1 -DryRun

  公司電腦若因群組原則擋住 .ps1，用上面這種寫法就好，不需要改機器的執行原則。
#>
[CmdletBinding()]
param(
  [string]$Target   = (Get-Location).Path,
  [string]$Std      = "",
  [string]$Ref      = "v1",
  [string]$UsesRepo = "singi0771/ci-standards",
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$StdRepoUrl = 'https://github.com/singi0771/ci-standards.git'

function Die([string]$m) { Write-Host "[X] $m" -ForegroundColor Red; exit 1 }
function Warn([string]$m) { Write-Host "[!] $m" -ForegroundColor Yellow }

# YAML 一律寫成「UTF-8 無 BOM + LF」。
# PS 5.1 的 Set-Content -Encoding UTF8 會寫 BOM，有些 YAML 解析器會因此爆掉；
# Windows 預設的 CRLF 則會讓 actionlint / shellcheck 對 run: 區塊產生怪警告。
function Write-TextFile([string]$Path, [string]$Text) {
  $lf  = $Text -replace "`r`n", "`n"
  [System.IO.File]::WriteAllText($Path, $lf, (New-Object System.Text.UTF8Encoding($false)))
}
function Read-Lines([string]$Path) {
  return ([System.IO.File]::ReadAllText($Path) -replace "`r`n", "`n") -split "`n"
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Die "找不到 git。這是唯一的必要相依。" }

# -Std / -Target 可能是相對路徑，而下面會 Set-Location 到目標 repo 根目錄。
if ($Std) {
  if (-not (Test-Path -LiteralPath $Std)) { Die "-Std 指的路徑不存在：$Std" }
  $Std = (Resolve-Path -LiteralPath $Std).Path
}

# ── 目標 repo ────────────────────────────────────────────────
if (-not (Test-Path -LiteralPath $Target)) { Die "進不去 $Target" }
Set-Location -LiteralPath $Target
$TargetRoot = (& git rev-parse --show-toplevel 2>$null)
if ($LASTEXITCODE -ne 0 -or -not $TargetRoot) {
  # 往下找一層再回報。OneDrive / 網路磁碟很常見「外層資料夾包著真正的 clone」
  # 這種結構，只回一句「不是 git repo」會讓人以為 clone 壞了。
  $suggest = Get-ChildItem -Directory -ErrorAction SilentlyContinue |
             Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName '.git') } |
             ForEach-Object { "      " + $_.FullName }
  if ($suggest) {
    Die ("$Target 不是 git repo，但它底下這些子目錄是 —— 你要的應該是其中之一：`n" +
         ($suggest -join "`n") +
         "`n`n    cd 進去之後再跑一次，或用 -Target 指過去。" +
         "`n    （OneDrive／網路磁碟常見：外層資料夾包著真正的 clone）")
  }
  Die "$Target 不是 git repo（請先 git init 或 clone）"
}
Set-Location -LiteralPath ($TargetRoot.Trim())
$TargetRoot = (Get-Location).Path
# Set-Location 只改 PowerShell 的位置，不改行程的工作目錄，而本腳本用
# [System.IO.File] 讀寫（要控制編碼與換行）—— 那是 .NET API，相對路徑會解到
# 「PowerShell 當初啟動的目錄」而不是這裡。兩邊一起設，.github\... 才會落在目標 repo。
[System.IO.Directory]::SetCurrentDirectory($TargetRoot)

# 安全閥：不准把公版導入公版自己。
# 公版的呼叫端刻意用 `uses: ./...` 做 dogfooding；改成 owner/repo@ref 之後，
# PR 上跑的就不再是「這個 PR 的版本」，綠燈會變成假的。
if (Test-Path -LiteralPath (Join-Path $TargetRoot 'templates\consumer-repo\.github')) {
  Die "目標看起來就是 ci-standards 公版本身（有 templates\consumer-repo\）。公版不需要導入自己。要測試這支腳本請用 scripts/test-adopt.sh。"
}

# ── 公版範本 ─────────────────────────────────────────────────
$TmpClone = ""
if (-not $Std) {
  $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
  $cands = @()
  # 只有 CODE_WORK 真的有值才加進候選，否則會組出 "\ci-standards" 這種
  # 落在磁碟根目錄的路徑，機器上剛好有同名目錄就會誤判成公版。
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

function Remove-TmpClone {
  if ($TmpClone -and (Test-Path -LiteralPath $TmpClone)) {
    Remove-Item -LiteralPath $TmpClone -Recurse -Force -ErrorAction SilentlyContinue
  }
}

Write-Host "-- 目標: $TargetRoot"
Write-Host "-- 公版: $Std (ref: $Ref, uses: $UsesRepo)"
Write-Host ""

# ── 偵測技術棧 ───────────────────────────────────────────────
# 註：Get-ChildItem 的 -Depth 自 PowerShell 5.0 起提供，本腳本要求 >= 5.1，可用。
function Test-AnyFile([string]$Filter, [int]$Depth) {
  $hit = Get-ChildItem -Path . -Filter $Filter -Recurse -Depth $Depth -File -ErrorAction SilentlyContinue |
         Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' } | Select-Object -First 1
  return [bool]$hit
}
function B([bool]$v) { if ($v) { 'true' } else { 'false' } }

$HasDockerfile = Test-Path -LiteralPath 'Dockerfile'
$HasPy = (Test-Path 'requirements.txt') -or (Test-Path 'pyproject.toml') -or
         (Test-Path 'setup.py') -or (Test-AnyFile '*.py' 1)
$HasSh = Test-AnyFile '*.sh' 2
$PyVer = '3.12'
if (Test-Path -LiteralPath '.python-version') {
  $PyVer = ([System.IO.File]::ReadAllText('.python-version')).Trim()
}

$Mode = 'install'
if ((Test-Path '.github\workflows\ci.yml') -or (Test-Path '.github\workflows\security.yml')) {
  $Mode = 'upgrade'
}

Write-Host "偵測結果:"
Write-Host ("  模式         : {0}" -f $Mode)
Write-Host ("  Dockerfile   : {0}" -f (B $HasDockerfile))
Write-Host ("  Python       : {0} (版本 {1})" -f (B $HasPy), $PyVer)
Write-Host ("  shell script : {0}" -f (B $HasSh))
Write-Host ""

# ── 公版宣告了哪些 input（事實來源是公版自己，不在腳本裡寫死清單）──
function Get-ReusableInputs([string]$Path) {
  $names = @()
  $inBlk = $false
  foreach ($line in (Read-Lines $Path)) {
    if ($line -match '^    inputs:\s*$') { $inBlk = $true; continue }
    if ($inBlk -and ($line -match '^\S' -or $line -match '^  [a-z]')) { $inBlk = $false }
    if ($inBlk -and $line -match '^      ([A-Za-z0-9_-]+):\s*$') { $names += $Matches[1] }
  }
  return $names
}

$ReusableFor = @{
  'ci.yml'                          = 'ci-reusable.yml'
  'security.yml'                    = 'security-reusable.yml'
  'copilot-autofix-ci-security.yml' = 'copilot-autofix-reusable.yml'
  'copilot-autofix-review.yml'      = 'copilot-autofix-review-reusable.yml'
  'copilot-autoreview-gate.yml'     = 'copilot-autoreview-reusable.yml'
}

# 就地更新 uses: 的 owner/repo 與 ref。
# 刻意跳過 `uses: ./...` —— 公版自己 dogfooding 用相對路徑呼叫自己的 reusable。
function Update-UsesLines([string[]]$Lines) {
  $out = @()
  foreach ($line in $Lines) {
    if ($line -match '^\s*uses:\s*\./') { $out += $line; continue }
    if ($line -match '^(\s*uses:\s*)\S+/\.github/workflows/([A-Za-z0-9._-]+\.yml)@\S+\s*$') {
      $out += ("{0}{1}/.github/workflows/{2}@{3}" -f $Matches[1], $UsesRepo, $Matches[2], $Ref)
      continue
    }
    $out += $line
  }
  return $out
}

# 過濾 with: 區塊：註解原樣保留、公版仍有的 key 保留使用者的值、
# 公版已廢除的 key 移除（留著會讓 workflow 直接 invalid input 起不來）、最後補上缺的 key。
function Merge-WithBlock([string[]]$Lines, [string[]]$Known, [string[]]$Additions, [ref]$Dropped) {
  $out = @(); $inBlk = $false; $seen = @{}
  function Append-Missing {
    param($seen, $Known, $Additions)
    $add = @()
    foreach ($a in $Additions) {
      if (-not $a) { continue }
      $ak = ($a -split ':')[0]
      if (-not $seen.ContainsKey($ak) -and ($Known -contains $ak)) { $add += ("      " + $a) }
    }
    return $add
  }
  foreach ($line in $Lines) {
    if (-not $inBlk -and $line -match '^    with:\s*$') { $out += $line; $inBlk = $true; continue }
    if ($inBlk) {
      if ($line -match '^      ') {
        if ($line -match '^      #') { $out += $line; continue }
        if ($line -match '^      ([A-Za-z0-9_-]+):') {
          $k = $Matches[1]; $seen[$k] = $true
          if ($Known -contains $k) { $out += $line } else { $Dropped.Value += $k }
          continue
        }
        $out += $line; continue
      }
      $out += (Append-Missing $seen $Known $Additions)
      $inBlk = $false
    }
    $out += $line
  }
  if ($inBlk) { $out += (Append-Missing $seen $Known $Additions) }
  return $out
}

# 讀一個檔案 with: 區塊裡「真的有設定」的 key（被註解掉的不算）
function Get-WithKeys([string[]]$Lines) {
  $keys = @(); $inBlk = $false
  foreach ($line in $Lines) {
    if (-not $inBlk) { if ($line -match '^    with:\s*$') { $inBlk = $true }; continue }
    if ($line -match '^      #') { continue }
    if ($line -match '^      ([A-Za-z0-9_-]+):') { $keys += $Matches[1]; continue }
    if ($line -match '^      ') { continue }
    if ($line -match '^\s*$') { continue }
    $inBlk = $false
  }
  return $keys
}

# 薄殼換新版時，把使用者「自己打開的旋鈕」從舊檔搬到新檔。
# 判準只有一條：舊檔有設、而新範本沒設。
#   - 新範本自己就有的 key（head-branch / review-id 這種接線）→ 範本版本才是對的
#   - 公版 reusable 已經不認得的 key → 不搬並回報（留著 workflow 直接起不來）
function Get-CarriedKnobs([string[]]$OldLines, [string[]]$NewLines, [string[]]$Known, [ref]$Dropped) {
  $tplKeys = Get-WithKeys $NewLines
  $carried = @(); $inBlk = $false
  foreach ($line in $OldLines) {
    if (-not $inBlk) { if ($line -match '^    with:\s*$') { $inBlk = $true }; continue }
    if ($line -match '^      #') { continue }
    if ($line -match '^      ([A-Za-z0-9_-]+):') {
      $k = $Matches[1]
      if ($tplKeys -notcontains $k) {
        if ($Known -contains $k) { $carried += $line } else { $Dropped.Value += $k }
      }
      continue
    }
    if ($line -match '^      ') { continue }
    if ($line -match '^\s*$') { continue }
    $inBlk = $false
  }
  return $carried
}

# 把搬出來的那幾行放回新薄殼：範本裡有對應的註解提示就取代那一行，
# 否則附在 with: 區塊尾巴。
function Add-Knobs([string[]]$Lines, [string[]]$Carried) {
  if (-not $Carried -or $Carried.Count -eq 0) { return $Lines }
  $map = @{}; $order = @()
  foreach ($c in $Carried) {
    if ($c -match '^\s*([A-Za-z0-9_-]+):') { $map[$Matches[1]] = $c; $order += $Matches[1] }
  }
  $doneK = @{}; $out = @(); $inBlk = $false
  foreach ($line in $Lines) {
    if (-not $inBlk -and $line -match '^    with:\s*$') { $out += $line; $inBlk = $true; continue }
    if ($inBlk) {
      if ($line -match '^      #\s*([A-Za-z0-9_-]+):') {
        $k = $Matches[1]
        if ($map.ContainsKey($k) -and -not $doneK.ContainsKey($k)) {
          $out += $map[$k]; $doneK[$k] = $true; continue
        }
        $out += $line; continue
      }
      if ($line -match '^      ' -or $line -match '^\s*$') { $out += $line; continue }
      foreach ($k in $order) { if (-not $doneK.ContainsKey($k)) { $out += $map[$k]; $doneK[$k] = $true } }
      $inBlk = $false
    }
    $out += $line
  }
  if ($inBlk) { foreach ($k in $order) { if (-not $doneK.ContainsKey($k)) { $out += $map[$k] } } }
  return $out
}

# 全新安裝：整個 with: 區塊直接換成偵測結果
function Set-WithBlock([string[]]$Lines, [string[]]$Additions) {
  $out = @(); $inBlk = $false; $done = $false
  foreach ($line in $Lines) {
    if (-not $done -and $line -match '^    with:\s*$') {
      $out += $line
      foreach ($a in $Additions) { if ($a) { $out += ("      " + $a) } }
      $inBlk = $true; $done = $true; continue
    }
    if ($inBlk -and $line -match '^      ') { continue }
    $inBlk = $false
    $out += $line
  }
  return $out
}

$CiAdditions = @(
  ('python-version: "{0}"' -f $PyVer),
  ('run-python: {0}'       -f (B $HasPy)),
  ('run-docker-build: {0}' -f (B $HasDockerfile)),
  'run-actionlint: true',
  ('run-shellcheck: {0}'   -f (B $HasSh))
)
$SecAdditions = @(
  ('python-version: "{0}"'    -f $PyVer),
  ('scan-docker-image: {0}'   -f (B $HasDockerfile))
)

# ── 三類檔案，三種策略（與 adopt.sh 一致）────────────────────
# Configured：真的帶專案設定（severity / python-version / 自訂 cron…）→ 就地合併。
$Configured = @('ci.yml','security.yml')
# ShellFiles：純薄殼。if: / with: 的接線與 secrets: 都屬於公版契約 →
#   整份換成新範本，再把使用者打開過的旋鈕搬回來。
#   1.2.0 改的是 if: 條件與 secrets: 區塊，就地合併只碰 with: —— 舊 consumer 升級後
#   會拿到新的 uses: 卻留著舊的 if:，變成「版本號變了、自動修迴圈還是壞的」。
$ShellFiles = @('copilot-autofix-ci-security.yml','copilot-autofix-review.yml',
                'copilot-autoreview-gate.yml')
$ProjectOwned = @('workflows\copilot-setup-steps.yml','copilot-instructions.md',
                  'pull_request_template.md','dependabot.yml')

Write-Host "計畫:"
foreach ($n in $Configured) {
  if (Test-Path ".github\workflows\$n") { Write-Host "  ~ 合併  .github\workflows\$n" }
  else { Write-Host "  + 新增  .github\workflows\$n" }
}
foreach ($n in $ShellFiles) {
  if (Test-Path ".github\workflows\$n") { Write-Host "  o 換新  .github\workflows\$n（薄殼以範本為準；只搬回你調過的旋鈕，舊檔留 .bak）" }
  else { Write-Host "  + 新增  .github\workflows\$n" }
}
foreach ($r in $ProjectOwned) {
  if (Test-Path ".github\$r") { Write-Host "  = 保留  .github\$r（只另存 .new）" }
  else { Write-Host "  + 新增  .github\$r" }
}
Write-Host ""

if ($DryRun) { Write-Host "(-DryRun: 到此為止，沒有動任何檔案)"; Remove-TmpClone; exit 0 }

New-Item -ItemType Directory -Force -Path '.github\workflows' | Out-Null
$Created = @(); $Merged = @(); $Kept = @(); $DroppedReport = @()
$Refreshed = @(); $ShellSame = @(); $CarriedReport = @()

# ── Configured：就地合併 ─────────────────────────────────────
foreach ($n in $Configured) {
  $dst = ".github\workflows\$n"
  $known = @()
  $reu = Join-Path $Std ("\.github\workflows\" + $ReusableFor[$n])
  if (Test-Path -LiteralPath $reu) { $known = Get-ReusableInputs $reu }

  if (-not (Test-Path -LiteralPath $dst)) {
    Copy-Item -LiteralPath (Join-Path $Tpl "workflows\$n") -Destination $dst -Force
    $lines = Read-Lines $dst
    if ($n -eq 'ci.yml')       { $lines = Set-WithBlock $lines $CiAdditions }
    if ($n -eq 'security.yml') { $lines = Set-WithBlock $lines $SecAdditions }
    $lines = Update-UsesLines $lines
    Write-TextFile $dst ($lines -join "`n")
    $Created += $n
  } else {
    $dropped = @()
    $adds = @()
    if ($n -eq 'ci.yml')       { $adds = $CiAdditions }
    if ($n -eq 'security.yml') { $adds = $SecAdditions }
    $lines = Merge-WithBlock (Read-Lines $dst) $known $adds ([ref]$dropped)
    $lines = Update-UsesLines $lines
    Write-TextFile $dst ($lines -join "`n")
    foreach ($k in $dropped) { $DroppedReport += ("    {0} -> 移除已廢除的 input: {1}" -f $n, $k) }
    $Merged += $n
  }
}

# ── ShellFiles：整份換新，只搬回使用者的旋鈕 ─────────────────
foreach ($n in $ShellFiles) {
  $dst = ".github\workflows\$n"
  $src = Join-Path $Tpl "workflows\$n"
  if (-not (Test-Path -LiteralPath $src)) { continue }
  $known = @()
  $reu = Join-Path $Std ("\.github\workflows\" + $ReusableFor[$n])
  if (Test-Path -LiteralPath $reu) { $known = Get-ReusableInputs $reu }

  if (-not (Test-Path -LiteralPath $dst)) {
    Write-TextFile $dst ((Update-UsesLines (Read-Lines $src)) -join "`n")
    $Created += $n
    continue
  }

  $oldRaw   = [System.IO.File]::ReadAllText($dst)
  $oldLines = Read-Lines $dst
  $dropped  = @()
  $carried  = Get-CarriedKnobs $oldLines (Read-Lines $src) $known ([ref]$dropped)
  $lines    = Add-Knobs (Read-Lines $src) $carried
  $newText  = ((Update-UsesLines $lines) -join "`n")

  foreach ($c in $carried) { $CarriedReport += ("    {0} -> 保留你調過的: {1}" -f $n, $c.Trim()) }
  foreach ($k in $dropped) { $DroppedReport += ("    {0} -> 移除已廢除的 input: {1}" -f $n, $k) }

  # 內容真的變了才留 .bak —— 否則每次重跑都會生一堆垃圾（冪等性）
  if ($newText -eq $oldRaw) {
    $ShellSame += $n
  } else {
    Copy-Item -LiteralPath $dst -Destination ($dst + '.bak') -Force
    Write-TextFile $dst $newText
    $Refreshed += $n
  }
}

foreach ($r in $ProjectOwned) {
  $src = Join-Path $Tpl $r
  $dst = ".github\$r"
  if (-not (Test-Path -LiteralPath $src)) { continue }
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
  if (Test-Path -LiteralPath $dst) {
    if ((Get-FileHash $src).Hash -eq (Get-FileHash $dst).Hash) { $Kept += ($r + "(相同)") }
    else { Copy-Item -LiteralPath $src -Destination ($dst + ".new") -Force; $Kept += $r }
  } else {
    Copy-Item -LiteralPath $src -Destination $dst -Force
    $Created += $r
  }
}

Remove-TmpClone

# 1.2.0 契約的收尾檢查。薄殼現在是整份換新的，正常情況不會叫；
# 會叫就代表 -Std 指到的公版比 1.2.0 舊（或範本被改壞）。
$PatWarn = @()
foreach ($name in @('copilot-autofix-review.yml','copilot-autofix-ci-security.yml')) {
  $dst = ".github/workflows/$name"
  if (-not (Test-Path $dst)) { continue }
  $missing = @()
  if (-not (Select-String -Path $dst -Pattern 'copilot-trigger-pat' -Quiet)) {
    $missing += 'secrets: copilot-trigger-pat'
  }
  # review 薄殼還要有 COMMENTED 觸發條件 —— 只補 secret、留舊 if: 的話，
  # Copilot 的意見一樣進不了迴圈（它永遠不送 changes_requested）
  if ($name -eq 'copilot-autofix-review.yml' -and
      -not (Select-String -Path $dst -Pattern "'commented'" -SimpleMatch -Quiet)) {
    $missing += 'COMMENTED 觸發條件'
  }
  if ($missing.Count) {
    $PatWarn += "    $name -> 缺 $($missing -join '、')"
  }
}

Write-Host "-----------------------------------------------------------"
if ($Created.Count)   { Write-Host ("+ 新增: " + ($Created -join ' ')) }
if ($Merged.Count)    { Write-Host ("~ 合併: " + ($Merged  -join ' ')) }
if ($Refreshed.Count) { Write-Host ("o 換新（薄殼，舊檔留在 .bak）: " + ($Refreshed -join ' ')) }
if ($ShellSame.Count) { Write-Host ("= 已是最新: " + ($ShellSame -join ' ')) }
if ($Kept.Count)      { Write-Host ("= 保留（未覆蓋，另存 .new）: " + ($Kept -join ' ')) }
if ($CarriedReport.Count) {
  Write-Host ""
  Write-Host "薄殼換新版時搬回來的設定:"
  $CarriedReport | ForEach-Object { Write-Host $_ }
}
if ($DroppedReport.Count) {
  Write-Host ""
  Warn "以下 input 在新版公版已不存在，已從呼叫端移除（留著會讓 workflow 直接 invalid input 起不來）:"
  $DroppedReport | ForEach-Object { Write-Host $_ }
}
if ($PatWarn.Count) {
  Write-Host ""
  Warn "薄殼缺 1.2.0 的契約內容 -- 代表 -Std 指到的公版比 1.2.0 舊，導進去自動修迴圈不會動工。請把公版更新到 v1.2.0 以上再跑一次:"
  $PatWarn | ForEach-Object { Write-Host $_ }
}
Write-Host "-----------------------------------------------------------"

@'

接下來:

 1. git diff  <- 先看清楚改了什麼，尤其是升級模式

 2. 若有 *.new 檔案: 那是新版範本，跟現有的比對後自行取捨，處理完把 .new 刪掉。
    (copilot-instructions.md 這類是專案專屬內容，腳本刻意不覆蓋。)

    若有 *.bak 檔案: 那是被換掉的舊薄殼。薄殼的 if:/with:/secrets: 屬於公版契約，
    升級時一律以範本為準，只把你調過的旋鈕搬回來。確認過沒有你自己加的東西
    （額外的 job、改過的 permissions）就把 .bak 刪掉。

 3. [必改] 全新導入務必改 .github\copilot-instructions.md ——
    把「專案概觀 / 開發與測試指令 / 程式碼慣例」換成本專案實況。

    另外設好 repo secret COPILOT_TRIGGER_PAT (Settings -> Secrets -> Actions) ——
    沒設的話 CI 會過，但 Copilot 自動修迴圈不會動工。設定方式見公版 README。

 4. 送出（不需要 gh，PR 可以用瀏覽器開）
      git checkout -b chore/adopt-ci-standards
      git add .github
      git commit -m "chore: 導入/升級 ci-standards 公版"
      git push -u origin chore/adopt-ci-standards

 5. 等第一次 CI 跑完，再開分支保護（見公版 README）。

 [i] job id (ci / security) 刻意不動 —— 分支保護的 check 名稱綁著它。
'@ | Write-Host
