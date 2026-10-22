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

  專案專屬的檔案（pull_request_template.md、dependabot.yml、zizmor.yml）
  **絕不覆蓋** —— 已存在就只放一份 .new 供比對。

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
  [string]$Ref      = "v2",
  [string]$UsesRepo = "singi0771/ci-standards",
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$StdRepoUrl = 'https://github.com/singi0771/ci-standards.git'

$TmpClone = ""
function Remove-TmpClone {
  if ($TmpClone -and (Test-Path -LiteralPath $TmpClone)) {
    Remove-Item -LiteralPath $TmpClone -Recurse -Force -ErrorAction SilentlyContinue
  }
}
# Die 一律先清暫存的 clone —— clone 失敗、或之後任何一步中止，都不該在 %TEMP% 留下 ci-std-* 目錄
function Die([string]$m) { Write-Host "[X] $m" -ForegroundColor Red; Remove-TmpClone; exit 1 }
function Warn([string]$m) { Write-Host "[!] $m" -ForegroundColor Yellow }

# YAML 一律寫成「UTF-8 無 BOM + LF」。
# PS 5.1 的 Set-Content -Encoding UTF8 會寫 BOM，有些 YAML 解析器會因此爆掉；
# Windows 預設的 CRLF 則會讓 actionlint / shellcheck 對 run: 區塊產生怪警告。
function Write-TextFile([string]$Path, [string]$Text) {
  $lf  = $Text -replace "`r`n", "`n"
  [System.IO.File]::WriteAllText($Path, $lf, (New-Object System.Text.UTF8Encoding($false)))
}
function Read-Lines([string]$Path) {
  # 跟 adopt.sh 的 tr -d '\r' 一致：所有 \r 都拿掉
  return ([System.IO.File]::ReadAllText($Path) -replace "`r", "") -split "`n"
}
# 行陣列 → 文字，保證以換行結尾（adopt.sh 的 awk 每一行都會補 \n，兩邊產出才會相同）
function Join-Lines([string[]]$Lines) {
  $t = $Lines -join "`n"
  if (-not $t.EndsWith("`n")) { $t += "`n" }
  return $t
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
# PS 5.1 在 $ErrorActionPreference='Stop' 底下，native 指令寫到 stderr 的東西（連 2>$null 也一樣）
# 會變成終止例外 —— git 的 "fatal: not a git repository"、"Cloning into ..." 都會讓腳本當場炸掉，
# 走不到後面的提示與清理。呼叫 git 的地方一律暫時改成 Continue，改看 $LASTEXITCODE。
$ErrorActionPreference = 'Continue'
$TargetRoot = (& git rev-parse --show-toplevel 2>$null)
$ErrorActionPreference = 'Stop'
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

# 保護措施：不准把公版導入公版自己。
# 公版的呼叫端刻意用 `uses: ./...` 呼叫自己，當自己的第一個使用者；改成 owner/repo@ref 之後，
# PR 上跑的就不再是「這個 PR 的版本」，綠燈會變成假的。
if (Test-Path -LiteralPath (Join-Path $TargetRoot 'templates\consumer-repo\.github')) {
  Die "目標看起來就是 ci-standards 公版本身（有 templates\consumer-repo\）。公版不需要導入自己。要測試這支腳本請用 scripts/test-adopt.sh。"
}

# ── 公版範本 ─────────────────────────────────────────────────
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
  $script:TmpClone = Join-Path ([System.IO.Path]::GetTempPath()) ("ci-std-" + [Guid]::NewGuid().ToString('N'))
  $ErrorActionPreference = 'Continue'   # 理由同上面的 git rev-parse
  & git clone --depth 1 --branch $Ref $StdRepoUrl (Join-Path $TmpClone 'ci-standards') 2>$null | Out-Null
  $ErrorActionPreference = 'Stop'
  if ($LASTEXITCODE -ne 0) {
    Die "clone 失敗。內網請確認 git 的 proxy 設定（git config --global http.proxy ...），或用 -Std 指向本機既有的 clone。"
  }
  $Std = Join-Path $TmpClone 'ci-standards'
}
$Tpl = Join-Path $Std 'templates\consumer-repo\.github'
if (-not (Test-Path -LiteralPath $Tpl)) { Die "$Std 底下找不到 templates\consumer-repo\.github" }

Write-Host "-- 目標: $TargetRoot"
Write-Host "-- 公版: $Std (ref: $Ref, uses: $UsesRepo)"
Write-Host ""

# ── 偵測用了哪些技術 ───────────────────────────────────────────────
# 偵測範圍與檔名規則跟 adopt.sh 一致，也跟公版 reusable「實際會檢查的範圍」一致：
#   - 全 repo（不限深度），略過 .git 與 node_modules（自己遞迴，才能整個跳過 node_modules，
#     不然 Get-ChildItem -Recurse 會先把幾萬個檔案全走一遍）
#   - 檔名分大小寫（-cmatch），跟 adopt.sh 的 find -name、reusable 的 find 一樣
# Python 例外：只看根目錄的相依清單與兩層內的 .py。
# 深度對照：adopt.sh 的 find -maxdepth N ＝ 這裡的 $Max N（根目錄的檔案算第 1 層）；-1 ＝不限。
function Get-RepoFiles([string]$Dir, [int]$Level, [int]$Max) {
  foreach ($i in (Get-ChildItem -LiteralPath $Dir -Force -ErrorAction SilentlyContinue)) {
    if ($i.PSIsContainer) {
      if ($i.Name -ceq '.git' -or $i.Name -ceq 'node_modules') { continue }
      if ($Max -lt 0 -or $Level -lt $Max) { Get-RepoFiles $i.FullName ($Level + 1) $Max }
    } else { $i }
  }
}
function Measure-Files([string]$NameRegex, [int]$Max) {
  return @(Get-RepoFiles '.' 1 $Max | Where-Object { $_.Name -cmatch $NameRegex }).Count
}
function Test-AnyFile([string]$NameRegex, [int]$Max) { return ((Measure-Files $NameRegex $Max) -gt 0) }
function B([bool]$v) { if ($v) { 'true' } else { 'false' } }

# Dockerfile：跟公版一樣找 Dockerfile / *.Dockerfile / Dockerfile.*（不含 *.dockerignore）
$HasDockerfile = [bool](Get-RepoFiles '.' 1 -1 | Where-Object {
  $_.Name -cmatch '^(Dockerfile|.*\.Dockerfile|Dockerfile\..*)$' -and $_.Name -cnotmatch '\.dockerignore$'
} | Select-Object -First 1)
$HasPy = (Test-Path 'requirements.txt') -or (Test-Path 'pyproject.toml') -or
         (Test-Path 'setup.py') -or (Test-AnyFile '\.py$' 2)
$HasSh = Test-AnyFile '\.sh$' -1
# .NET：方案檔（.sln / .slnx）或專案檔（.csproj / .fsproj / .vbproj）
$DotnetSln  = Measure-Files '\.(sln|slnx)$' -1
$DotnetProj = Measure-Files '\.(csproj|fsproj|vbproj)$' -1
$HasDotnet  = ($DotnetSln -gt 0) -or ($DotnetProj -gt 0)
$PyVer = '3.12'
if (Test-Path -LiteralPath '.python-version') {
  # ReadAllText 會自動去掉 UTF-8 BOM；Trim 去掉空白與換行（adopt.sh 用 tr 做同一件事）
  $PyVer = ([System.IO.File]::ReadAllText('.python-version')) -replace '[\s\uFEFF]', ''
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
Write-Host ("  .NET         : {0} (方案檔 {1}、專案檔 {2})" -f (B $HasDotnet), $DotnetSln, $DotnetProj)
if ($DotnetSln -gt 1 -or ($DotnetSln -eq 0 -and $DotnetProj -gt 1)) {
  Warn '找到不只一個 .NET 方案 / 專案檔，公版無法自動決定要建置哪一個 —— 導入後請在 ci.yml 的 with: 加上 dotnet-project: "<路徑>"'
}
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
  'ci.yml'       = 'ci-reusable.yml'
  'security.yml' = 'security-reusable.yml'
}

# 就地更新 uses: 的 owner/repo 與 ref。
# 刻意跳過 `uses: ./...` —— 公版自己用相對路徑呼叫自己的 reusable（公版拿自己當第一個使用者）。
# 只動指向公版那兩支 reusable 的 uses:，而且只換「owner/repo/.github/workflows/<檔名>@<ref>」那一段，
# 行尾空白與 `# 註解` 原樣保留（與 adopt.sh 的 patch_uses 一致）。
function Update-UsesLines([string[]]$Lines) {
  $out = @()
  $re = '^(\s*uses:.*?)[^ \t]+/\.github/workflows/((?:ci|security)-reusable\.ya?ml)@[^ \t#]+(.*)$'
  foreach ($line in $Lines) {
    if ($line -match '^\s*uses:\s*\./') { $out += $line; continue }
    if ($line -cmatch $re) {
      $out += ("{0}{1}/.github/workflows/{2}@{3}{4}" -f $Matches[1], $UsesRepo, $Matches[2], $Ref, $Matches[3])
      continue
    }
    $out += $line
  }
  return $out
}

# 過濾 with: 區塊：註解與空行原樣保留、公版仍有的 key 保留使用者的值、
# 公版已廢除的 key 移除（留著會讓 workflow 直接 invalid input 起不來）、最後補上缺的 key。
# 空行先暫存：下一行還是區塊內容就照原樣放回去；區塊結束了就先補 key 再放空行（與 adopt.sh 一致）。
function Merge-WithBlock([string[]]$Lines, [string[]]$Known, [string[]]$Additions, [ref]$Dropped, [ref]$Found) {
  $out = @(); $inBlk = $false; $done = $false; $seen = @{}; $pend = @()
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
    if (-not $done -and $line -match '^    with:\s*(#.*)?$') { $out += $line; $inBlk = $true; $done = $true; continue }
    if ($inBlk) {
      if ($line -match '^\s*$') { $pend += $line; continue }
      if ($line -match '^      ') {
        $out += $pend; $pend = @()
        if ($line -match '^      #') { $out += $line; continue }
        if ($line -match '^      ([A-Za-z0-9_-]+):') {
          $k = $Matches[1]; $seen[$k] = $true
          if ($Known -contains $k) { $out += $line } else { $Dropped.Value += $k }
          continue
        }
        $out += $line; continue
      }
      $out += (Append-Missing $seen $Known $Additions)
      $out += $pend; $pend = @()
      $inBlk = $false
    }
    $out += $line
  }
  if ($inBlk) { $out += (Append-Missing $seen $Known $Additions); $out += $pend }
  $Found.Value = $done
  return $out
}

# ── v1 → v2：呼叫端觸發條件的修補（與 adopt.sh 的 patch_v2_triggers 一致）──
# 2.0.0 修了「PR 改 base 就能繞過來源分支政策」：ci.yml 的 pull_request 要多聽 edited，
# job 的 if 與 concurrency 一起改。只認 v1 範本原封不動的寫法，三行要嘛一起換、要嘛都不動。
$V1Types   = '    types: [opened, synchronize, reopened, ready_for_review]'
$V2Types   = '    types: [opened, synchronize, reopened, ready_for_review, edited]'
$V1CiConc  = '  group: ci-${{ github.ref }}'
$V2CiConc  = '  group: ci-${{ github.ref }}-${{ github.event.action == ''edited'' && !github.event.changes.base && ''noop'' || ''run'' }}'
$V1If      = '    if: ${{ github.event_name != ''pull_request'' || !github.event.pull_request.draft }}'
$V2If      = '    if: ${{ github.event_name != ''pull_request'' || (!github.event.pull_request.draft && (github.event.action != ''edited'' || github.event.changes.base)) }}'
$V1SecConc = '  group: security-${{ github.ref }}'
$V2SecConc = '  group: security-${{ github.event_name }}-${{ github.ref }}'

function Update-V2Triggers([string[]]$Lines, [string]$Name, [ref]$Report) {
  $has = { param($l) $Lines -ccontains $l }
  # PowerShell 的 @{} 比對 key 不分大小寫；這裡要「整行完全相同」才換，跟 adopt.sh 一致
  $map = New-Object System.Collections.Hashtable ([System.StringComparer]::Ordinal)
  if ($Name -eq 'ci.yml') {
    # 三行各自要是「v1 原樣」或「已經是 v2」其中之一（與 adopt.sh 一致）：
    # 使用者只手動加了 edited、沒改 if 與 concurrency 的半套狀態也要補齊
    if ((& $has $V2Types) -and (& $has $V2CiConc) -and (& $has $V2If)) { return $Lines }
    if (((& $has $V1Types) -or (& $has $V2Types)) -and ((& $has $V1CiConc) -or (& $has $V2CiConc)) -and ((& $has $V1If) -or (& $has $V2If))) {
      $map[$V1Types] = $V2Types; $map[$V1CiConc] = $V2CiConc; $map[$V1If] = $V2If
      $Report.Value += '    ci.yml -> pull_request 加上 edited（改 base 時重跑來源分支政策），job if 與 concurrency 一併更新'
    } else {
      $Report.Value += '    ci.yml -> [!] 觸發條件不是範本原樣，沒有自動改。請照公版範本手動加上 edited 與對應的 if / concurrency'
      $Report.Value += '             （有設 restricted-base-branches 時一定要做，否則 PR 改 base 就能繞過來源分支政策）'
      return $Lines
    }
  } elseif ($Name -eq 'security.yml') {
    if (-not (& $has $V1SecConc)) { return $Lines }
    $map[$V1SecConc] = $V2SecConc
    $Report.Value += '    security.yml -> concurrency 依事件分組（排程重掃不再跟 push 互相取消）'
  }
  $out = @()
  foreach ($line in $Lines) {
    if ($map.ContainsKey($line)) { $out += $map[$line] } else { $out += $line }
  }
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
  ('run-python: {0}'       -f (B $HasPy)),
  ('python-version: "{0}"' -f $PyVer),
  ('run-dotnet: {0}'       -f (B $HasDotnet)),
  ('run-docker-build: {0}' -f (B $HasDockerfile)),
  ('run-hadolint: {0}'     -f (B $HasDockerfile)),
  'run-actionlint: true',
  ('run-shellcheck: {0}'   -f (B $HasSh))
)
# security-reusable 的 python-version 其實沒有任何步驟用到，新導入的專案不再傳它。
# run-zizmor 預設打開：workflow 的安全檢查很便宜，而且範本附的 zizmor.yml 已把公版的例外放行。
$SecAdditions = @(
  ('scan-docker-image: {0}'   -f (B $HasDockerfile)),
  'run-zizmor: true'
)

# ── 兩類檔案，兩種策略（與 adopt.sh 一致）────────────────────
# Configured：真的帶專案設定（severity / python-version / 自訂 cron…）→ 就地合併。
$Configured = @('ci.yml','security.yml')
# zizmor.yml 也算專案專屬：使用者會在裡面放自己的放行規則。
$ProjectOwned = @('pull_request_template.md','dependabot.yml','zizmor.yml')

# 公版 reusable 宣告的 input 清單。讀不到（reusable 不見了、或 inputs: 的縮排變了）時一定要停 ——
# 空清單會讓 Merge-WithBlock 把使用者 with: 裡的每一個 key 都當成「已廢除」刪掉。
$KnownFor = @{}
foreach ($n in $Configured) {
  $reu = Join-Path $Std (".github\workflows\" + $ReusableFor[$n])
  $k = @()
  if (Test-Path -LiteralPath $reu) { $k = @(Get-ReusableInputs $reu) }
  if ($k.Count -eq 0) {
    Die "讀不到 $reu 宣告的 inputs。公版 clone 不完整，或 reusable 的格式變了 —— 繼續的話會把呼叫端 with: 的設定全部當成已廢除刪掉，所以中止。"
  }
  $KnownFor[$n] = $k
}

Write-Host "計畫:"
foreach ($n in $Configured) {
  if (Test-Path ".github\workflows\$n") { Write-Host "  ~ 合併  .github\workflows\$n" }
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
$TriggerReport = @(); $NoWithReport = @(); $MissingTpl = @()

# ── Configured：就地合併 ─────────────────────────────────────
foreach ($n in $Configured) {
  $dst = ".github\workflows\$n"
  $known = $KnownFor[$n]

  if (-not (Test-Path -LiteralPath $dst)) {
    Copy-Item -LiteralPath (Join-Path $Tpl "workflows\$n") -Destination $dst -Force
    $lines = Read-Lines $dst
    if ($n -eq 'ci.yml')       { $lines = Set-WithBlock $lines $CiAdditions }
    if ($n -eq 'security.yml') { $lines = Set-WithBlock $lines $SecAdditions }
    $lines = Update-UsesLines $lines
    Write-TextFile $dst (Join-Lines $lines)
    $Created += $n
  } else {
    $dropped = @()
    $adds = @()
    if ($n -eq 'ci.yml')       { $adds = $CiAdditions }
    if ($n -eq 'security.yml') { $adds = $SecAdditions }
    $found = $false
    $lines = Merge-WithBlock (Read-Lines $dst) $known $adds ([ref]$dropped) ([ref]$found)
    $lines = Update-UsesLines $lines
    $lines = Update-V2Triggers $lines $n ([ref]$TriggerReport)
    Write-TextFile $dst (Join-Lines $lines)
    foreach ($k in $dropped) { $DroppedReport += ("    {0} -> 移除已廢除的 input: {1}" -f $n, $k) }
    if (-not $found) { $NoWithReport += $n }
    $Merged += $n
  }
}

# zizmor.yml 裡有一條「指向公版的 uses: 只要求釘 tag」的放行規則，寫死了公版的 owner/repo。
# 搬到組織（-UsesRepo）時要跟著換，否則那條規則對不到、zizmor 會開始抱怨 @v1 沒釘 SHA。
# 只換那一個字串，使用者自己加的規則原樣保留；既有的檔案、新建的檔案、另存的 .new 都要換。
# 行尾原樣保留（不經過 Write-TextFile 的 CRLF→LF）—— 這是使用者自己的檔案，
# adopt.sh 的 awk 也只換那個字串、其餘位元組不動，兩邊產出才會相同。
function Update-ZizmorOwner([string]$Path) {
  $txt = [System.IO.File]::ReadAllText($Path)
  $txt = $txt.Replace('"singi0771/ci-standards/*"', ('"{0}/*"' -f $UsesRepo))
  [System.IO.File]::WriteAllText($Path, $txt, (New-Object System.Text.UTF8Encoding($false)))
}

foreach ($r in $ProjectOwned) {
  $src = Join-Path $Tpl $r
  $dst = ".github\$r"
  # 範本不見了要講出來（多半是公版改了檔名），不能安靜跳過、還印「導入完成」
  if (-not (Test-Path -LiteralPath $src)) { $MissingTpl += $r; continue }
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dst) | Out-Null
  $migrateZizmor = ($r -eq 'zizmor.yml' -and $UsesRepo -ne 'singi0771/ci-standards')
  if (Test-Path -LiteralPath $dst) {
    if ($migrateZizmor) { Update-ZizmorOwner $dst }
    Copy-Item -LiteralPath $src -Destination ($dst + '.new') -Force
    if ($migrateZizmor) { Update-ZizmorOwner ($dst + '.new') }
    # 跟範本（換過 owner 之後）一模一樣就不留 .new —— 否則每次重跑都會生一份沒差異的檔案
    if ((Get-FileHash ($dst + '.new')).Hash -eq (Get-FileHash $dst).Hash) {
      Remove-Item -LiteralPath ($dst + '.new') -Force
      $Kept += ($r + "(相同)")
    } else {
      $Kept += $r
    }
  } else {
    Copy-Item -LiteralPath $src -Destination $dst -Force
    if ($migrateZizmor) { Update-ZizmorOwner $dst }
    $Created += $r
  }
}

Remove-TmpClone

Write-Host "-----------------------------------------------------------"
if ($Created.Count)   { Write-Host ("+ 新增: " + ($Created -join ' ')) }
if ($Merged.Count)    { Write-Host ("~ 合併: " + ($Merged  -join ' ')) }
if ($Kept.Count)      { Write-Host ("= 保留（未覆蓋，另存 .new）: " + ($Kept -join ' ')) }
if ($DroppedReport.Count) {
  Write-Host ""
  Warn "以下 input 在新版公版已不存在，已從呼叫端移除（留著會讓 workflow 直接 invalid input 起不來）:"
  $DroppedReport | ForEach-Object { Write-Host $_ }
}
if ($TriggerReport.Count) {
  Write-Host ""
  Write-Host "觸發條件（v2）:"
  $TriggerReport | ForEach-Object { Write-Host $_ }
}
if ($NoWithReport.Count) {
  Write-Host ""
  Warn ("這些檔案找不到「    with:」區塊，input 沒有合併（沒移除廢除的、也沒補新的），請手動對照範本: " + ($NoWithReport -join ' '))
}
if ($MissingTpl.Count) {
  Write-Host ""
  Warn ("公版裡找不到這些範本，沒有導入: " + ($MissingTpl -join ' ') + "（公版 clone 可能不完整）")
}
Write-Host "-----------------------------------------------------------"

@'

接下來:

 1. git diff  <- 先看清楚改了什麼，尤其是升級模式

 2. 若有 *.new 檔案: 那是新版範本，跟現有的比對後自行取捨，處理完把 .new 刪掉。
    (zizmor.yml、dependabot.yml 這類是專案專屬內容，腳本刻意不覆蓋。)

 3. 送出（不需要 gh，PR 可以用瀏覽器開）
      git checkout -b chore/adopt-ci-standards
      git add .github
      git commit -m "chore: 導入/升級 ci-standards 公版"
      git push -u origin chore/adopt-ci-standards

 4. 等第一次 CI 跑完，再開分支保護（見公版 README）。
    不是每個 repo 都設得了（例如 Free 方案的 private repo）—— 設不了時 Gate 照跑、
    紅燈只能提醒、擋不住 merge，補位做法見 README「沒辦法設分支保護時」。

 5. 第一次跑 Security Scan 時，zizmor（workflow 安全檢查）可能會挑你自己寫的
    workflow 的毛病（沒釘 SHA 的 action、權限太大…）。那是真的該修；
    確定是誤判才放進 .github\zizmor.yml，寫法見公版 README。

 [i] job id (ci / security) 刻意不動 —— 分支保護的 check 名稱綁著它。
'@ | Write-Host
