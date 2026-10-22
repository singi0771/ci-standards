# ci-standards — 團隊統一 CI / 安全掃描中央公版

這個 repo 是**中央公版**（所有專案共用的那一份 CI 設定）：安全掃描與 CI 的邏輯只寫在這裡一次，每個專案用**一行 `uses:`** 呼叫它。
公版更新 → 移動主版本 tag（目前是 `v2`）→ 各專案下次跑 CI 就自動吃到新版，不必一個一個 repo 去改。

> 適用環境：私有 repo、全部是免費的開源工具，**不需要 GitHub Advanced Security**。

**白話版三句話：**

1. 你開 PR → 公版自動跑一輪掃描（程式弱點、套件 CVE、密鑰外洩、Dockerfile 與 IaC 設定、workflow 本身的安全）。
2. 哪一項紅了，Actions 的 Summary 會印一張表告訴你。repo 有設分支保護的話，紅燈會直接擋住 merge；
   設不了分支保護的 repo（例如 Free 方案的 private repo）紅燈只能提醒，做法見[沒辦法設分支保護時](#沒辦法設分支保護時)。
3. 掃描規則、工具版本、要加什麼新檢查，全部改這個 repo 就好，專案那邊不用動。

---

## 目錄

0. **[已知限制（導入前先看）](docs/KNOWN-LIMITATIONS.md)** —— 哪些功能實測過但還不能用
0'. **[流程圖：這個 repo 到底在做什麼](docs/FLOW.md)** —— 讀 README 之前的地圖
1. [運作原理（先看這個）](#運作原理先看這個)
2. **[其他專案怎麼導入](#其他專案怎麼導入)** —— clone 公版 → 跑 `adopt` → 開 PR → 設分支保護
3. [導入後，日常怎麼用](#導入後日常怎麼用)
4. [可調參數（inputs）](#可調參數inputs)
5. [省 Actions 分鐘：這套怎麼省、你還能怎麼省](#省-actions-分鐘這套怎麼省你還能怎麼省)
6. [分支保護：讓流程「非過不可」](#分支保護讓流程非過不可)
7. [沒辦法設分支保護時](#沒辦法設分支保護時)
8. [分支模型：PR 要發到哪裡](#分支模型pr-要發到哪裡)
9. [常見情境客製](#常見情境客製)（Python 以外的專案：[.NET](#c--net-專案)、[前端](#前端react--vue--node)）
10. [疑難排解](#疑難排解)
11. [版本策略](#版本策略)（[從 v1 升級到 v2](#從-v1-升級到-v2)）
12. [檔案地圖](#檔案地圖)
13. [這套涵蓋什麼、不涵蓋什麼](#這套涵蓋什麼不涵蓋什麼)

---

## 運作原理（先看這個）

```
你的專案 repo                          ci-standards（本 repo）
─────────────────                      ────────────────────────
.github/workflows/security.yml  ──呼叫──▶ security-reusable.yml
   jobs.security:                          ├─ SAST (Semgrep)                 程式裡的弱點寫法
     uses: ...@v2                          ├─ Dependency vuln (OSV-Scanner)  套件有沒有已知 CVE
     with: { ... }                         ├─ FS / IaC / Docker (Trivy)      Dockerfile / K8s / Terraform 設定，可選 SBOM
                                           ├─ Secret scan (gitleaks)         密鑰有沒有 commit 進去（含歷史）
                                           ├─ Workflow security (zizmor)     workflow 本身安不安全   ←可選
                                           ├─ Docker image (Trivy)           build 出來的 image     ←可選
                                           └─ 🛡️ Security Gate ←總結，分支保護只認這個

.github/workflows/ci.yml        ──呼叫──▶ ci-reusable.yml
   jobs.ci:                                ├─ Python lint + test (ruff, pytest)               ←可選
     uses: ...@v2                          ├─ .NET build + test (dotnet format/build/test)    ←可選
     with: { ... }                         ├─ Docker build check（可加 hadolint 檢查 Dockerfile） ←可選
                                           ├─ Workflow + shell lint (actionlint, shellcheck)   ←可選
                                           ├─ PR source branch policy 誰可以 merge 進哪裡     ←可選
                                           └─ 🧪 CI Gate ←總結，分支保護只認這個
```

> CI 的每一項子檢查**都可以獨立開關**（見[可調參數](#ci-reusableyml)）。
> 全關掉也不會讓 Gate 變紅 —— Gate 的判定是「開了就一定要 success；沒開的才允許 skipped」。

**呼叫端只有二十幾行、沒有邏輯**。要改掃描規則、加工具、升版本 —— 全部改這個 repo，不動任何專案。

### 為什麼有 Security Gate / CI Gate

兩者都是 `needs` 全部子 job 的總結 job：任一子 job 失敗它就失敗。
所以**分支保護只要求這兩個 check**，日後你在公版增減工具，不必回頭改每個 repo 的 ruleset。

更重要的是：**不要把有 `if` 條件的 job 直接設成 required check**。
`docker-build`（`run-docker-build: false` 時）、`zizmor`、`trivy-image` 這些關掉時會變成 `skipped`，
而 skipped 的 required check，GitHub 要嘛把它當通過（等於沒檢查）、要嘛一直 pending，兩種都不是你要的。
Gate job 用 `if: always()` 執行、自己判斷「開了就得 success」，就沒有這個問題。

### 一個 PR 的完整流程

```
你開 PR ─▶ CI + Security 並行跑 ─▶ 兩個 Gate 都綠 ─▶ 你 review ─▶ merge
                │
                └─ 任一 Gate 紅 ─▶ 看 Summary 的表 ─▶ 自己修 ─▶ 再推一次
```

掃描器負責「找」，你負責「修」與「決定」。公版不會替你改任何程式碼 ——
它只在 PR 上把問題攤開；repo 有設分支保護的話，紅燈會擋住不該進 main 的東西。

> ℹ️ 2.0.0 把「掃到問題自動請 Copilot 修、全過自動請 Copilot 審」那套整組拿掉了。
> 原因：它要 Copilot Business 授權與一支真人 PAT，而且 Copilot 每推一次 commit，
> 觸發的 CI/Security run 都會卡在 `action_required`、要人手動按一次
> 「Approve and run workflows」（GitHub 硬性規定，沒有開關可調）。
> 維護成本大於效益。已導入的專案要怎麼收尾見[從 v1 升級到 v2](#從-v1-升級到-v2)。

---

## 其他專案怎麼導入

**導入＝在你的專案放兩支「呼叫端」workflow（外加三個設定檔），用 `uses: ...@v2` 呼叫本 repo。**
公版本身不用複製、也不用 fork；你的專案只留二十幾行的呼叫端，邏輯全在這裡。

先分清楚你是哪一種：

| 你的專案 | 照哪一節做 |
|---|---|
| 從沒導入過 | 下面的「新專案導入（6 步）」 |
| 已經導入、還指向 `@v1` | [從 v1 升級到 v2](#從-v1-升級到-v2)（有破壞性變更，要先刪 Copilot 呼叫端） |
| 已經導入、指向 `@v2` | 什麼都不用做，公版移動 `v2` tag 後下次跑 CI 自動吃到新版；想用新參數就重跑一次步驟 2 |

### 前置檢查

| 項目 | 要求 |
|---|---|
| 語言 | 安全掃描不分語言。CI 內建 Python（ruff + pytest）與 .NET（dotnet format / build / test），**都是預設關、用到才開**（導入腳本會依偵測結果填好）。其他語言見[常見情境](#專案不是-python) |
| 本 repo 可見性 | 目前是 **public**，任何 repo 都能 `uses:` 呼叫，不必另外授權。若哪天改回 private，要到本 repo 的 Settings → Actions → General → Access 選 **Accessible from repositories in the organization** |
| 你的電腦 | 只要 `git`。`gh` 是選配（只有設分支保護那一步方便一點），見 [`docs/ADOPT.md`](docs/ADOPT.md) |
| 目標 repo 權限 | 能推分支、開 PR 就能導入；設分支保護（步驟 6）要 admin，沒有的話請 owner 做 |
| 分支保護 | **不是必要條件**。Free 方案的 private repo、或公司統一管制的 repo 設不了也照樣能導入，只是紅燈擋不住 merge，見[沒辦法設分支保護時](#沒辦法設分支保護時) |

### 新專案導入（6 步）

#### 步驟 1 — 把公版 clone 到本機（只做一次，之後每個專案共用）

```bash
git clone https://github.com/singi0771/ci-standards.git ~/ci-standards
```

已經 clone 過的話 `git -C ~/ci-standards pull` 更新到最新，導入腳本與範本才會是 v2 的版本。
（clone 只是為了拿腳本與範本；你的專案在 CI 上呼叫的是 GitHub 上的 `@v2`，跟本機這份無關。）

#### 步驟 2 — 在你的專案開分支，跑導入腳本

```bash
cd /path/to/your-project
git checkout -b chore/adopt-ci-standards

~/ci-standards/scripts/adopt.sh --dry-run     # 先看偵測結果與要動哪些檔案，不寫入
~/ci-standards/scripts/adopt.sh               # 確認無誤再真的跑
```
```powershell
# Windows PowerShell（內建，不必裝東西）
powershell -ExecutionPolicy Bypass -File C:\path\to\ci-standards\scripts\adopt.ps1 -DryRun
powershell -ExecutionPolicy Bypass -File C:\path\to\ci-standards\scripts\adopt.ps1
```

腳本做的事：

- 偵測專案用了什麼（Python、.NET、Dockerfile、shell script…），把對應的 `run-*` 參數寫成 `true` / `false`
- 放入 `.github/workflows/ci.yml`、`.github/workflows/security.yml`（已存在就**升級**：`uses:` 改成 `@v2`、補新參數、你調過的值原樣保留）
- 放入 `zizmor.yml`、`dependabot.yml`、`pull_request_template.md` —— 這三個是專案專屬的，**已存在就不覆蓋**，只另存一份 `.new` 讓你比對
- 不刪任何既有檔案、不碰網路、不 commit

常用參數：`--target <路徑>`（不在專案目錄裡執行時）、`--ref v2.0.0`（釘死某一版，預設 `v2`）。
PowerShell 版寫成 `-Target`、`-Ref`、`-DryRun`。內網、離線、Proxy 的做法見 [`docs/ADOPT.md`](docs/ADOPT.md)。

<details>
<summary>不想跑腳本：手動複製</summary>

```bash
cp -R ~/ci-standards/templates/consumer-repo/.github .
```

然後打開 `.github/workflows/ci.yml` 與 `security.yml`，照步驟 3 把 `with:` 改成符合你的專案。
範本的 `uses:` 已經指向 `singi0771/ci-standards/...@v2`，不用改。

</details>

#### 步驟 3 — 檢查參數

用腳本的話多半不用改，`git diff` 看一眼就好。要確認的只有這幾個：

```yaml
# .github/workflows/ci.yml
jobs:
  ci:                                         # ← job id 不要改，會影響 check 名稱
    uses: singi0771/ci-standards/.github/workflows/ci-reusable.yml@v2
    with:
      run-python: true           # 2.0.0 起預設是 false，Python 專案要明確打開
      python-version: "3.12"
      # run-dotnet: true         # C# / .NET 專案打開，見「C# / .NET 專案」
      run-docker-build: true     # 沒 Dockerfile 設 false
      run-hadolint: true         # 有 Dockerfile 時，build 前先檢查 Dockerfile 寫法
```

```yaml
# .github/workflows/security.yml
jobs:
  security:                                   # ← job id 不要改
    uses: singi0771/ci-standards/.github/workflows/security-reusable.yml@v2
    with:
      severity: "CRITICAL,HIGH"
      fail-on-findings: true
      scan-docker-image: false   # 有 Dockerfile 才改 true（每個 image 多吃 2–3 分鐘）
      run-zizmor: true           # workflow 本身的安全檢查，放行規則在 .github/zizmor.yml
```

另外兩件看專案而定的事：

- **走 develop 流程**（功能分支 → develop → main）：兩支呼叫端的 `on.push.branches` 改成 `[main, develop]`；
  要限制「只有 develop 能 merge 進 main」再加 `restricted-base-branches` / `allowed-head-branches`，見[分支模型](#分支模型pr-要發到哪裡)。
- **專案原本就有 `.github/dependabot.yml` 等檔案**：比對腳本產生的 `.new`，要的段落手動併進去，處理完把 `.new` 刪掉。

> ⚠️ **job id（`security` / `ci`）不要改**。分支保護的 check 名稱是 `<job id> / <公版 job 名>`，改了 ruleset 就對不上。
> 所有參數的完整說明見[可調參數](#可調參數inputs)。

導入後 `.github/` 會多這些東西：

| 檔案 | 作用 | 要不要改 |
|---|---|---|
| `workflows/ci.yml` | 呼叫 CI 公版 | 只改 `with:` 的開關 |
| `workflows/security.yml` | 呼叫安全公版 | 只改 `with:` 的開關 |
| `zizmor.yml` | workflow 安全檢查的放行規則（公版的 `@v2` 這類版本 tag 已放行） | 有誤判才加規則 |
| `dependabot.yml` | pip 每週、docker / actions 每月自動開更新 PR | 用不到的段落刪掉；.NET / 前端照檔尾的註解補 `nuget` / `npm` 區塊 |
| `pull_request_template.md` | PR 檢查清單（含安全項） | 通常不用改 |

#### 步驟 4 — commit、推上去、開 PR

```bash
git add .github
git commit -m "chore: 導入 ci-standards 公版 CI 與安全掃描"
git push -u origin chore/adopt-ci-standards
gh pr create          # 沒有 gh 就到 GitHub 網頁開 PR
```

開 PR 那一刻 CI 與 Security 就會跑（草稿 PR 不跑，按 Ready for review 才跑）。

#### 步驟 5 — 處理第一次的紅燈

第一次幾乎一定有東西紅 —— 那是掃描器真的找到問題（多半是套件 CVE、你自己寫的 workflow 沒釘版本，或是誤判）。
點進 Actions → 該 run → Summary 看是哪一項，處理方式見[掃到弱點怎麼處理](#掃到弱點怎麼處理)與[疑難排解](#疑難排解)。
問題太多一次清不完，先設 `fail-on-findings: false` 過渡，見[導入初期紅到不想活](#導入初期紅到不想活)。
**不要為了讓它變綠就關掉檢查。** 兩個 Gate 都綠再 merge。

#### 步驟 6 — 開分支保護（能設的話）

PR 上的 workflow 至少要跑完一次（GitHub 上要先有 `ci / CI Gate`、`security / Security Gate` 這兩個 check 名稱），再執行：

```bash
~/ci-standards/scripts/setup-branch-protection.sh <owner>/<repo>               # 只保護 default branch
~/ci-standards/scripts/setup-branch-protection.sh <owner>/<repo> main develop  # 走 develop 流程
```

這會建立 ruleset：必須開 PR + 對話解決 + 通過 `Security Gate` 與 `CI Gate` + 禁止 force push / 刪分支。
⚠️ 有方案限制、以及 required approvals 預設為何是 0，見[分支保護](#分支保護讓流程非過不可)。
設不了（403、或公司統一管制）也沒關係，前五步做完公版就已經在跑了，補位做法見[沒辦法設分支保護時](#沒辦法設分支保護時)。

### 導入完成的檢查清單

- [ ] `.github/workflows/ci.yml`、`security.yml` 的 `uses:` 都是 `singi0771/ci-standards/...@v2`
- [ ] `run-python` / `run-dotnet` / `run-docker-build` / `scan-docker-image` 跟專案實際用到的技術一致
- [ ] 兩支呼叫端的 `pull_request` **沒有** `paths-ignore`（否則純文件 PR 的 required check 永遠 pending）
- [ ] 沒有殘留的 `.new` 檔
- [ ] PR 上 `ci / CI Gate`、`security / Security Gate` 都綠
- [ ] 分支保護已設；或確認設不了，並在 `CONTRIBUTING.md` / PR 範本寫上「兩個 Gate 都綠才 merge」

---

## 導入後，日常怎麼用

### 一般開發

```bash
git checkout -b feat/xxx        # 不要直接改 main
# ...寫程式...
git push -u origin feat/xxx
gh pr create
```

開 PR 後自動發生：CI（你打開的那幾項：ruff + pytest、dotnet build + test、docker build、lint）→ 四到六項安全掃描 → 兩個 Gate 總結。
有分支保護的 repo 要全綠才能 merge；沒有的話請照團隊約定，兩個 Gate 都綠才按 merge。
Gate 紅的話點進 Actions 看是哪一項掛掉。

> 還在寫、不想每推一次就跑一輪？**開成草稿 PR（Draft）**。範本的呼叫端遇到草稿會整個跳過，
> 按下「Ready for review」那一刻才跑。草稿本來就不能 merge，沒有安全上的損失。

### 掃描結果去哪看

- **Actions → 該 run → Summary**：Security Gate / CI Gate 會各印一張表，一眼看出哪項掛掉
- **Artifact `semgrep-sarif`**：Semgrep 完整結果，下載後用 VS Code 的 SARIF Viewer 看（公版不上傳 Security 分頁，原因見 [CHANGELOG 2.0.0](CHANGELOG.md)）
- **Artifact `sbom-cyclonedx`**：`generate-sbom: true` 時會多一份「這個 commit 用了哪些套件」的清單

### 掃到弱點怎麼處理

1. 先看 Gate 的 Summary 表，確定是哪一項掛掉
2. 點進該 job 的 log 拿檔案、行號與掃描器訊息
3. 判斷是真弱點還是誤判 —— 誤判的處理方式（各掃描器的忽略寫法）見[疑難排解](#疑難排解)
4. 修好再推一次，Gate 會重跑

**不要為了讓它變綠就關掉檢查。** 真的要放行就放在該掃描器的忽略設定裡，
留下一行註解寫清楚為什麼 —— 下一個人才知道那不是隨手關掉的。

### 定期會自動發生

- **週一 03:00 UTC**：完整重掃（`schedule` 觸發），抓「程式碼沒動但新公布的 CVE」
- **Dependabot**：pip 每週（小版本併成一個 PR）、docker 與 github-actions 每月

### 公版更新了怎麼辦

同一個主版本內什麼都不用做。`uses: ...@v2` 且 `v2` tag 已移動 → 你下次跑 CI 就吃到新版。
新增的參數都有預設值，舊的呼叫端不會壞；想用新功能先 `git pull` 本機的公版 clone，再跑一次 `adopt.sh`，它會把新參數補上、舊的保留。

換主版本（例如 `@v1` → `@v2`）才需要動專案，因為那代表有破壞性變更。步驟見[從 v1 升級到 v2](#從-v1-升級到-v2)。

---

## 可調參數（inputs）

### `security-reusable.yml`

| 參數 | 型別 | 預設 | 說明 |
|---|---|---|---|
| `severity` | string | `CRITICAL,HIGH` | Trivy 要擋下的嚴重度。可加 `MEDIUM` 收更嚴 |
| `fail-on-findings` | boolean | `true` | `true`=掃到問題 Gate 就紅；`false`=有找到問題也先不紅（**導入初期過渡用**）。⚠️ 2.0.0 起 `false` 只放行「有找到問題」：規則下載失敗、弱點資料庫下載失敗、工具當掉這類**掃描本身出錯**照樣紅 —— 沒掃成不能當成掃過。OSV-Scanner 異常結束不論這個值都是紅的 |
| `scan-docker-image` | boolean | `false` | build 出 image 再掃 CVE。**有 Dockerfile 才開**，每個 image 多吃 2–3 分鐘 |
| `dockerfile` | string | `""` | 要 build 來掃的 Dockerfile。寫法同 `ci-reusable` 的同名參數：留空＝自動找全 repo；可列多個、每一項 `路徑` 或 `路徑:build context` |
| `docker-context` | string | `"."` | `dockerfile` 那一項沒寫 `:context` 時用的 build context（預設 repo 根目錄） |
| `run-zizmor` | boolean | `false` | 用 [zizmor](https://docs.zizmor.sh/) 檢查 `.github/workflows` 本身：把 PR 標題塞進 `run:` 的腳本注入、`pull_request_target` / `workflow_run` 這類危險觸發器、沒釘 SHA 的 action、權限給太大…。放行規則放專案的 `.github/zizmor.yml`（範本已附） |
| `zizmor-min-severity` | string | `low` | zizmor 只回報這個等級以上：`low` / `medium` / `high` |
| `semgrep-rules` | string | `p/owasp-top-ten p/security-audit p/secrets auto` | Semgrep 規則包，空白隔開。`auto` 會依語言自動挑（要連 Semgrep 規則庫、會回傳匿名使用統計；不想要就拿掉）。想加 `p/python`、`p/dockerfile` 就寫在這 |
| `trivy-scanners` | string | `vuln,misconfig` | Trivy 檔案系統掃描要開哪些：`vuln` / `misconfig` / `secret` / `license`。預設不含 `secret`，因為 gitleaks 已連 git 歷史一起掃了；要查授權條款加 `license` |
| `generate-sbom` | boolean | `false` | 用 Trivy 產出 SBOM（CycloneDX JSON）存成 artifact `sbom-cyclonedx`。出事時（又一個 log4j）拿它秒查有沒有中 |

> **2.0.0 移除了 `upload-sarif` 與 `python-version`**。呼叫端還在傳的話 workflow 會直接 `invalid input` 起不來；
> 重跑一次 `adopt.sh` / `adopt.ps1` 會自動拿掉。`upload-sarif` 從沒真正能用過：被呼叫的 reusable 只能縮減、不能擴張權限，
> 要它能動，每一個呼叫端都得授予 `security-events: write`。Semgrep 結果一律存成 artifact `semgrep-sarif`。

### `ci-reusable.yml`

| 參數 | 型別 | 預設 | 說明 |
|---|---|---|---|
| `run-python` | boolean | `false` | 是否跑 ruff + pytest。⚠️ **2.0.0 起預設關**，Python 專案要明確設 `true`（`adopt.sh` 會依偵測結果寫明）。有 `pyproject.toml` 且含 `[project]` 或 `[build-system]` 時才會 `pip install -e .`，裝不起來會紅 |
| `python-version` | string | `3.12` | CI 的 Python 版本 |
| `run-dotnet` | boolean | `false` | 是否跑 .NET（C# / F# / VB）：restore → `dotnet format` → build（Release）→ test。見 [C# / .NET 專案](#c--net-專案) |
| `dotnet-version` | string | `""` | .NET SDK 版本（例如 `8.0.x`），多個用換行隔開。留空＝有 `global.json` 就照它；沒有就依專案檔（`*.csproj` / `*.fsproj` / `*.vbproj` / `Directory.Build.props`）的 `TargetFramework(s)` 把用到的版本都裝起來（`net8.0` → `8.0.x`，測試才跑得起 8.0 runtime；`net48` 這類 .NET Framework 不算）；連那個都找不到才用 `10.0.x` |
| `dotnet-project` | string | `""` | 要建置的 `.sln` / `.slnx` / `.csproj` 路徑。留空＝自動找：repo 裡只有一個方案檔就用它，沒有方案檔時只有一個專案檔就用它；**找到兩個以上會直接紅**，請明確指定 |
| `run-dotnet-format` | boolean | `true` | 用 `dotnet format --verify-no-changes` 檢查格式與 analyzer 規則（讀專案的 `.editorconfig`，等同 Python 那邊的 ruff）。舊專案第一次導入整片紅時先設 `false` 過渡，本機跑一次 `dotnet format` 整理完再打開 |
| `dotnet-runner` | string | `ubuntu-latest` | .NET job 跑在哪種 runner。WPF / WinForms（`net*-windows`）、.NET Framework 這類只能在 Windows 建置的專案設 `windows-latest`（Windows runner 分鐘數算 2 倍） |
| `run-docker-build` | boolean | `true` | 驗證 image 能 build（不推送）。沒 Dockerfile 就設 `false` |
| `dockerfile` | string | `""` | 要檢查的 Dockerfile（相對 repo 根目錄）。⚠️ **2.0.0 起預設留空＝自動找全 repo** 的 `Dockerfile`、`*.Dockerfile`、`Dockerfile.*`（略過 `node_modules`；1.4.0 的預設是 `"Dockerfile"`、只看根目錄）。可列多個、空白隔開，每一項寫 `路徑` 或 `路徑:build context`。1.4.0 的單一路徑寫法（`src/Web.Api/Dockerfile`）照樣能用。明確列出的路徑不存在會紅。hadolint 與 build 都吃這份清單，見 [Dockerfile 不在根目錄、或不只一個](#dockerfile-不在根目錄或不只一個) |
| `docker-context` | string | `"."` | `dockerfile` 那一項沒寫 `:context` 時用的 build context。預設 repo 根目錄（Visual Studio / docker-compose 的 .NET 慣例，通常不用改） |
| `run-hadolint` | boolean | `false` | build 之前先用 [hadolint](https://github.com/hadolint/hadolint) 檢查 Dockerfile 寫法（沒釘版本的 apt 套件、`latest` tag、`RUN` 裡的 shell 問題…）。warning 以上才算失敗；要忽略某條規則放 `.hadolint.yaml`。放在 Docker build 那個 job 裡，不多花一個 job |
| `run-actionlint` | boolean | `false` | 檢查 GitHub Actions workflow 語法，會連 `run:` 區塊的 bash 一起用 shellcheck 檢查 |
| `actionlint-paths` | string | `""` | 額外要檢查的 workflow 檔 glob。空字串＝只檢查 `.github/workflows`。⚠️ actionlint 一旦收到檔案參數就「只」檢查那些檔案，所以公版是**分兩次**跑（預設路徑一次、額外路徑一次） |
| `run-shellcheck` | boolean | `false` | 用 shellcheck 檢查 shell script（runner 內建，不必安裝）。跟 actionlint 合在同一個 job 跑 |
| `shellcheck-paths` | string | `""` | 要檢查的 `.sh` glob。空字串＝自動找全 repo（找不到就略過） |
| `restricted-base-branches` | string | `""` | 要管制「誰可以 merge 進來」的 base 分支，空白隔開、支援 glob。留空＝不檢查。見[分支模型](#分支模型pr-要發到哪裡) |
| `allowed-head-branches` | string | `""` | 承上，允許合併進那些 base 的來源分支。`restricted-base-branches` 有值時必填。樣式的 `*` 也會比對 `/`，`hotfix/*` 包含 `hotfix/a/b`。呼叫端的 `pull_request.types` 要含 `edited`（範本已含），PR 改目標分支時才會重跑 |
| `ruff-version` | string | `0.16.0` | **釘死**的 ruff 版本。不釘的話新版 ruff 會憑空多出規則、讓沒改程式的 repo 突然變紅；要升級 lint 規則在此改一版、統一生效 |

> **`run-*` 全部關掉也不會卡住**：子 job 都可能因 input 而 `skipped`，Gate 只在「開了卻不是 success」才擋。
>
> **lint 穩定性**：consumer 的 ruff 規則由**自己的 `pyproject.toml`**（`[tool.ruff.lint] select/ignore`）決定，公版只負責釘死 ruff 執行檔版本。兩者搭配才能讓 `ruff check` 結果可重現、不隨上游漂移。
> 想順便做 Python 的安全 lint，在 `select` 加 `"S"`（ruff 內建的 bandit 規則），不必另外裝 bandit。

**「這個 repo 沒有 Python，主要內容是 workflow 與 script」的設定範例**（本 repo 自己就是這樣跑的，見 `.github/workflows/ci.yml`）：

```yaml
jobs:
  ci:
    uses: singi0771/ci-standards/.github/workflows/ci-reusable.yml@v2
    with:
      run-python: false
      run-docker-build: false
      run-actionlint: true
      run-shellcheck: true
```

> `run-python` 2.0.0 起預設就是 `false`，這裡照樣寫出來 —— 明寫比靠預設值好懂，日後預設再變也不受影響。

---

## 省 Actions 分鐘：這套怎麼省、你還能怎麼省

GitHub 的計費規則只有一條要記：**每個 job 不滿一分鐘也算一分鐘**（private repo 才計費；public repo 免費）。
所以「一個 6 秒的 job」跟「一個 59 秒的 job」一樣貴，而 macOS runner 算 10 倍、Windows 算 2 倍。

**公版已經幫你做的：**

| 做法 | 省在哪 |
|---|---|
| actionlint 與 shellcheck 合成一個 job | 兩個加起來不到 30 秒，拆兩個 job 多付一分鐘 |
| hadolint 放在 Docker build job 裡當一個步驟 | 不另開 job |
| actionlint 改抓 2 MB 執行檔，不再拉 docker image | 每次省 20–40 秒 |
| Python job 不再 `pip install --upgrade pip` | runner 的 pip 已經夠新，省 5–10 秒 |
| 草稿 PR 整個跳過（範本呼叫端） | 還在寫的 PR 每推一次省一整輪 |
| Trivy 預設不再掃 secret（gitleaks 已掃過含歷史） | 大 repo 省數十秒 |
| Dependabot：docker / actions 改每月 | 每個 Dependabot PR 都會跑整套，少開 PR 就少跑 |
| 本 repo 的三平台 adopt 測試改成「只動文件就跳過」 | macOS 10 倍計費，純文件 PR 不必花 |

**你還能調的：**

- `scan-docker-image: false`（沒 Dockerfile 一定關；有的話它每次多 2–3 分鐘）
- 每週排程改每月：`security.yml` 的 `cron` 改成 `"0 3 1 * *"`
- 呼叫端 `push: main` 的 `paths-ignore` 已排除文件；**`pull_request` 不可以加 `paths-ignore`**（會讓純文件 PR 的 required check 永遠 pending）
- 連續 push 會自動取消舊 run（範本已設 `concurrency` + `cancel-in-progress`）
- Settings → Billing → Spending limit 設 **$0**，額度用完就停，不會爆帳單（代價：那天 CI 直接不跑，見 [`docs/HANDOFF.md`](docs/HANDOFF.md) 記的症狀）

一個 Python + Docker 的 private 專案，每次 push 到 PR 大約是 **CI 4–5 分鐘 + Security 5–6 分鐘**（含 zizmor），合併進 main 再一輪。
.NET 專案用 `dotnet-runner: windows-latest` 的話，那個 job 的分鐘數算 2 倍 —— 只有 WPF / WinForms / .NET Framework 這類非 Windows 不可的才這樣設。

---

## 分支保護：讓流程「非過不可」

### ⚠️ 方案限制（一定先確認）

**private repo 的 ruleset / branch protection 需要 GitHub Pro 以上方案。**
免費個人帳號的 private repo 呼叫 API 會直接被擋：

```
403 Upgrade to GitHub Pro or make this repository public to enable this feature.
```

三個解法：把 repo 轉到有 Team 方案的 org（推薦，順便統一管組織層級的 ruleset）／帳號升 Pro／repo 轉 public（多數情況不適合）。
三個都做不到的話，公版還是照用，見[沒辦法設分支保護時](#沒辦法設分支保護時)。`setup-branch-protection.sh` 遇到這種 repo 會直接說明原因後結束，不會只丟一個 403。

### ⚠️ required approvals 為什麼預設是 0

腳本預設 `required_approving_review_count: 0`，這是刻意的。設 1 而團隊只有你一個人時，**PR 會永遠 merge 不了**，兩件事疊在一起：

1. GitHub 不允許 PR 作者 approve 自己的 PR
2. ruleset 預設沒有 `bypass_actors`，連 org admin 都繞不過（跟舊版 classic branch protection 不同）

設 0 **不代表沒有守門**——「必須開 PR」和「必須通過 Security Gate / CI Gate」照樣強制，只是不強制人工按 Approve。等有第二位固定 reviewer 再改：

```bash
REQUIRED_APPROVALS=1 ./scripts/setup-branch-protection.sh <owner>/<repo>
```

### 一鍵設定

```bash
gh auth login                                        # 需有目標 repo 的 admin
./scripts/setup-branch-protection.sh <owner>/<repo>
```

不給分支＝只保護 default branch；要保護別的分支就接在後面列出來（`main develop`、`'release/*'` 這類樣式也行），
用法見[分支模型](#一個-develop-流程完整長什麼樣)。

腳本可重複執行：偵測到同名 ruleset 會改用 `PUT` 更新，不會建出第二份（ruleset 超過 30 份也找得到；只比對這個 repo 自己的，不含組織層的）。
ruleset 名稱：不給分支時是 `CI Standard - main protection`；有給分支時是 `CI Standard (branches: <排序後的分支清單>)`，
不同的分支清單各自一份、不會互相覆蓋。repo 上同時有好幾份 CI Standard ruleset 時腳本會列出來提醒你 —— 它們的規則是疊加生效的。

**required check 會綁定來源是 GitHub Actions**（`integration_id: 15368`）。不綁的話，任何有寫入權限的人
（或外流的 token）都能用 commit status API 對同一個 SHA 貼一個叫 `ci / CI Gate` 的綠燈，騙過分支保護。
要改綁別的 app 設 `CHECKS_INTEGRATION_ID=<id>`，設成空字串＝不綁（不建議）。
`REQUIRED_APPROVALS` 必須是非負整數、`STRICT_CHECKS` 只能是 `true` / `false`，打錯會直接中止，不會送出一份壞掉的 ruleset。

### 手動設定

目標 repo → Settings → Rules → Rulesets → New branch ruleset → 針對 `main`：

- ✅ **Enforcement status** 設為 **Active**（預設是 Disabled，很容易漏）
- ✅ **Require a pull request before merging**（approvals 先填 0、勾要求對話解決）
- ✅ **Require status checks to pass**，加入（來源選 **GitHub Actions**，不要選 any source）：
  - `security / Security Gate`
  - `ci / CI Gate`
- ✅ **Block force pushes** / **Restrict deletions**

> check 名稱格式是 `<呼叫端 job id> / <公版 job 名>`。若你改過 job id，這裡要跟著改。
> 名稱必須跟 Checks 分頁上實際出現的字串**完全一致**，所以務必等第一次 run 跑完再設。

> **只設這兩個 Gate，不要把個別 job 加進去。** `docker-build`、`zizmor`、`trivy-image` 有 `if` 條件，
> 關掉時會變 `skipped`，GitHub 對 skipped 的 required check 要嘛當通過、要嘛一直 pending，都不是你要的。

### ⚠️ 開之前先確認呼叫端沒有 paths-ignore

`ci.yml` / `security.yml` 的 **`pull_request` 區塊不可以有 `paths-ignore`**。
被 path filter 擋掉的 PR 根本不會啟動 workflow，required check 就永遠是 pending —— 一個只改 README 的 PR
會直接卡死，而且沒有例外可以繞。範本已經拿掉了，但如果你手上是舊版複製過去的，導入前務必檢查。

（`push: main` 那邊保留 `paths-ignore` 沒問題，那不影響 required check。）

### 另外要做的一件事

- **防止爆帳單**：Settings → Billing → Spending limit，Actions 設 **$0**

這是組織層級的一次性設定，細節見 [`docs/SETUP.md`](docs/SETUP.md)。

> 本 repo 目前在個人帳號底下。**private repo 的 ruleset 需要 Pro 以上方案**，
> 而組織可以用「一條 org ruleset 管所有 repo」，不必逐個跑腳本。
> 建議在導入第 3 個專案之前搬到組織，見 [`docs/MIGRATION-TO-ORG.md`](docs/MIGRATION-TO-ORG.md)。

---

## 沒辦法設分支保護時

**不是每個專案都設得了分支保護 / ruleset。** 常見的兩種：

- GitHub **Free 方案的 private repo**：ruleset API 直接回 `403 Upgrade to GitHub Pro…`
- **公司統一管理的 repo**：設定由管理者管，專案成員沒有 admin，或公司政策不讓各專案自己改

這種 repo **照樣可以導入公版**。差別只有一個：

> **Gate 照跑、照樣變紅，但紅燈擋不住 merge。** 有寫入權限的人看到紅燈還是按得下 merge，GitHub 不會攔。

### 還是有用的部分

| 機制 | 沒有分支保護時 |
|---|---|
| PR 上的 CI / Security | ✅ 照跑，PR 頁面看得到兩個 Gate 的紅綠燈與 Summary 表 |
| push 到 main（或 develop）後再跑一輪 | ✅ 照跑 —— 就算有人直接 push、或硬 merge 了紅燈的 PR，main 上的那一輪也會紅，事後查得到 |
| PR 來源分支政策（`restricted-base-branches`） | ✅ 照樣判定，發錯分支的 PR 會紅、Summary 會寫出該發到哪裡 —— 看得出誤操作，只是擋不住 |
| 每週一排程重掃 | ✅ 照跑，新公布的 CVE 一樣抓得到 |

### 補位做法

1. **團隊約定：兩個 Gate 都綠才按 merge。** 寫進專案的 PR 範本（`pull_request_template.md`）與 `CONTRIBUTING.md`，
   讓每個人開 PR 時都看得到。這是唯一真正會被每天看到的那道防線。
2. **merge 之後看一眼 main 上那一輪**（Actions 篩 `branch:main`）。紅了就 `git revert` 那個 merge commit，
   修好再重新發 PR —— 不要在 main 上直接補。
3. **限縮誰能寫入、誰能 merge**：Settings → Collaborators 只給需要的人 Write，其他人給 Read / Triage。
   能按 merge 的人越少，約定越容易守。
4. **真的需要「非過不可」**：考慮 GitHub Team / Pro 方案、搬到有方案的組織，或（適合的話）把 repo 改成 public。
   設好之後照[分支保護](#分支保護讓流程非過不可)跑一次腳本就好，呼叫端不必改。

> 公版沒有、也做不到「替你擋 merge」的功能 —— 擋 merge 只能靠 GitHub 的分支保護。
> 上面這些都是**讓問題看得見、有人負責收拾**，不是取代分支保護。

---

## 分支模型：PR 要發到哪裡

**公版不預設任何分支模型。** 你要只有 `main`、`main` + `develop`、還是完整 GitFlow，
都是專案自己的決定 —— 公版只提供兩件事：**PR 上跑檢查**，以及**選配的來源分支限制**。

### 哪些 PR 會跑檢查

由呼叫端的 `on.pull_request` 決定，跟分支名稱無關：

```yaml
# 範本預設（ci.yml）：發到「任何分支」的 PR 都跑
# edited：PR 改目標分支（base）時 GitHub 只送 edited，少了它來源分支政策不會重跑（見下一節）
pull_request:
  types: [opened, synchronize, reopened, ready_for_review, edited]

# 只想對特定分支的 PR 跑，自己加 branches:
pull_request:
  branches: [main, develop]
  types: [opened, synchronize, reopened, ready_for_review, edited]
```

> `edited` 是 1.4.0 加的（只有 `ci.yml` 需要）：PR **改了 base 分支**時要重跑來源分支政策，
> 否則先發到 `develop` 拿到綠燈、再到網頁上把 base 改成 `main`，綠燈會原封不動沿用。
> 只改標題或內文也算 `edited`，那種不會重跑、也不會把正在跑的那一輪取消掉 ——
> 靠的是 job 的 `if` 與 `concurrency`，範本都寫好了，寫法見下一節。

> ⚠️ 加了 `branches:` 篩選之後，**沒被列到的分支其 PR 不會有 `ci / CI Gate`**。
> 那些分支就不能設成 required check，否則會永遠 pending。
> 不確定就別加 —— 「全部都跑」永遠是安全的預設。

`push:` 那邊同理，但 GitHub 的 `on:` **不吃 `${{ }}` 運算式**，分支名只能寫死。
走 develop 流程就把它列進去：`branches: [main, develop]`。

### 限制「誰可以 merge 進哪裡」

`ci-reusable` 有兩個選配 input，不填就不檢查：

```yaml
jobs:
  ci:
    uses: singi0771/ci-standards/.github/workflows/ci-reusable.yml@v2
    with:
      restricted-base-branches: "main"              # 要管的 base，空白隔開，支援 glob
      allowed-head-branches: "develop hotfix/*"     # 允許的來源分支
```

意思是「`main` 只接受從 `develop` 或 `hotfix/*` 發來的 PR」，其他分支發到 `main` 會被擋下，
Summary 會印出目標／來源／允許清單，並提示把 base 改成整合分支。

**要搭配呼叫端的三處設定**（範本 `templates/consumer-repo/.github/workflows/ci.yml` 已全部寫好）：

```yaml
on:
  pull_request:
    types: [opened, synchronize, reopened, ready_for_review, edited]   # 1. 改 base 時重跑

concurrency:
  # 2. 只改標題／內文的 edited 用獨立 group，不會把正在跑的 CI 取消掉
  group: ${{ github.event.action == 'edited' && github.event.changes.base == null && format('ci-edit-{0}', github.run_id) || format('ci-{0}', github.ref) }}
  cancel-in-progress: true

jobs:
  ci:
    # 3. 草稿不跑；edited 只有改 base 才跑
    if: ${{ github.event_name != 'pull_request' || (!github.event.pull_request.draft && (github.event.action != 'edited' || github.event.changes.base != null)) }}
```

> ⚠️ 少了 `edited`，PR 從 `develop` 改發到 `main` 時會沿用舊的綠燈。已導入的專案升到 v2 時重跑 `adopt`：
> - `ci.yml` 還是 **v1 範本原樣**（1.3.x 以前導入的）→ 三處一起自動換成上面的寫法
> - 用 **1.4.0 範本**導入的 → 本來就是這個寫法，不會再動
> - **改過**觸發條件的 → 不動、只印 ⚠️ 提醒，請手動照上面改（有設 `restricted-base-branches` 時一定要改）
>
> 樣式的 `*` 也會比對 `/`：`hotfix/*` 包含 `hotfix/a/b`。

判定順序：

1. base 不在 `restricted-base-branches` 內 → 直接通過（不管制）
2. `restricted-base-branches` 有值但 `allowed-head-branches` 空白 → **失敗**（這幾乎一定是漏填，不是本意）
3. PR 來自 fork → **失敗**（fork 的分支名可以隨便取，叫 `develop` 不代表是你的 `develop`；外部貢獻請發到整合分支）
4. head 符合 `allowed-head-branches` 的任一樣式 → 通過，否則失敗

檢查結果收進 `ci / CI Gate`，所以**分支保護的 ruleset 不必加新的 required check**。

> ⚠️ **這擋的是誤操作，不是惡意。** 它是一個 status check，沒有 ruleset 的話，
> 有權限的人照樣可以直接 push 或用 admin 權限硬 merge。
> 真正不讓人繞過的是下面這組設定 —— 兩者要一起用。設不了分支保護的 repo 見[沒辦法設分支保護時](#沒辦法設分支保護時)。

### 一個 develop 流程完整長什麼樣

```
功能分支 ──PR──▶ develop ──PR──▶ main
   ↑                 ↑              ↑
   隨便取名        整合分支        正式版
```

| 要達成的事 | 靠什麼 |
|---|---|
| 功能分支不能直接推 develop | develop 的 ruleset：`pull_request` 規則（必須開 PR） |
| 檢查沒過不能按 merge | develop 的 ruleset：required status checks = 兩個 Gate |
| 不能 force push / 刪掉 develop | develop 的 ruleset：`non_fast_forward` + `deletion` |
| 連 admin 都不能繞過 | ruleset 不設 `bypass_actors`（腳本預設就沒有） |
| 只有 develop 能 merge 進 main | `restricted-base-branches` + `allowed-head-branches` |
| 不能直接推 main | main 的 ruleset，同上 |

設定指令：

```bash
# 兩條長壽分支一起保護（腳本可重複執行，同名 ruleset 會更新而不是新增一份）
./scripts/setup-branch-protection.sh <owner>/<repo> main develop

# 先看要送出什麼、不打 API（沒有 admin 權限時也能用，把 payload 交給有權限的人）
./scripts/setup-branch-protection.sh <owner>/<repo> main develop --dry-run
```

再到 repo → Settings → General → Default branch 把預設分支改成 `develop`，
新開的 PR base 就會預設是它，不會有人不小心發到 `main`。

> 💡 分支名稱不必是 `develop`。腳本吃的是你給的名字，`restricted-base-branches` /
> `allowed-head-branches` 吃的也是你寫的 glob —— 叫 `integration`、`staging` 都行。

---

## 常見情境客製

### C# / .NET 專案

2.0.0 起 `ci-reusable.yml` 內建 .NET（C# / F# / VB）。打開 `run-dotnet` 就好：

```yaml
with:
  run-python: false
  run-dotnet: true
  # dotnet-project: "src/App.sln"      # repo 裡有兩個以上方案檔 / 專案檔時必填
  # dotnet-version: "8.0.x"            # 留空：global.json → 專案檔的 TargetFramework → 10.0.x
  # run-dotnet-format: false           # 舊專案導入初期格式整片紅時先關，整理完再開
  # dotnet-runner: windows-latest      # WPF / WinForms（net*-windows）/ .NET Framework 才需要
```

跑的順序是 `dotnet restore` → `dotnet format --verify-no-changes`（讀 `.editorconfig`）→ `dotnet build -c Release` → `dotnet test`。
方案裡沒有測試專案時 `dotnet test` 什麼都不做、不會紅（跟 Python 沒測試時一樣不擋）。

- **SDK 版本**：留空時，有 `global.json` 就照它；沒有就讀 `*.csproj` / `*.fsproj` / `*.vbproj` / `Directory.Build.props` 的
  `TargetFramework(s)`，把用到的版本全部裝起來（`net8.0` → `8.0.x`，測試才跑得起 8.0 的 runtime；`net48` 這類 .NET Framework 不算）；
  都找不到才用 `10.0.x`。要自己指定就填 `dotnet-version`，多個版本用換行隔開。
- **建置哪一個**：留空時自動找，只有一個方案檔（`.sln` / `.slnx`）就用它；沒有方案檔時只有一個專案檔就用它。
  **找到兩個以上不會亂猜**，直接紅並列出候選，請填 `dotnet-project`。
- **Windows 限定的專案**：目標是 `net*-windows`（WPF / WinForms）或 .NET Framework 的，在 Linux 上建不起來，
  設 `dotnet-runner: windows-latest`（分鐘數算 2 倍）。
- **快取**：專案有 `packages.lock.json` 才會開 NuGet 快取。

`adopt.sh` / `adopt.ps1` 偵測到 `.sln` / `.slnx` / `.csproj` / `.fsproj` / `.vbproj`（往下找四層）就會寫 `run-dotnet: true`；
方案檔不只一個時會提醒你補 `dotnet-project`。
安全掃描那邊不必改：Semgrep 有 C# 規則、OSV-Scanner 與 Trivy 讀 `packages.lock.json` 等 NuGet 相依檔。
Dependabot 要更新 NuGet 套件的話，照範本 `dependabot.yml` 檔尾的註解補一段 `nuget`。

### 專案不是 Python

`security-reusable.yml` 是語言無關的（Semgrep / Trivy / gitleaks / OSV / zizmor 都自己認語言），**照用即可**。

`ci-reusable.yml` 也**照用**。語言相關的 job（`run-python`、`run-dotnet`）2.0.0 起都是預設關，
用到哪個開哪個；剩下的都是語言無關的檢查：

```yaml
with:
  run-python: false        # 預設就是 false，寫出來比較清楚
  run-docker-build: true   # 有 Dockerfile 就留著
  run-hadolint: true       # Dockerfile 寫法
  run-actionlint: true     # workflow 語法 + run: 區塊的 bash
  run-shellcheck: true     # shell script
```

這樣仍然會產出 `ci / CI Gate` 這個 check，分支保護的 ruleset 不必為了語言不同而各寫一套。

**還需要公版沒內建的語言原生 lint / test（Node 的 eslint + vitest、Go 的 go vet + go test…）時**，兩條路：

1. 在該專案自己加一支 workflow（或在 `ci.yml` 裡加一個 job），**用不同的 job id**（例如 `node`），
   能設分支保護的話再把 `node / <job 名>` 一起加進 ruleset 的 required checks。
2. 到本 repo 開 Issue 提需求（見 [CONTRIBUTING](CONTRIBUTING.md)）。

> 走第 1 條時**不要**把 `ci.yml` 的 job id 也改掉 —— `ci / CI Gate` 是所有專案共用的 check 名稱，改了 ruleset 就要逐一客製，公版的意義就沒了。

### 前端（React / Vue / Node）

老實說，目前**安全掃描有涵蓋、CI 沒有**：

| | 前端專案現在的狀況 |
|---|---|
| Semgrep | ✅ `auto` 規則包會依語言挑 JS / TS 規則。⚠️ Semgrep 對 `.vue` 單檔元件的支援有限，`<script>` 裡的程式可能只掃到一部分 |
| OSV-Scanner | ✅ 讀 `package-lock.json` / `yarn.lock` / `pnpm-lock.yaml` |
| Trivy（檔案系統） | ✅ 掃同樣那幾個 lock 檔 |
| gitleaks | ✅ 不分語言 |
| CI 的 lint / 型別檢查 / 測試 / build | ❌ **公版還沒有 Node 的 job**：不會跑 eslint、`tsc`、vitest / jest、`npm run build` |

在公版補上之前，CI 那一半請在專案自己的呼叫端 workflow 寫一個 job（用不同的 job id，見上一節第 1 條），例如：

```yaml
  node:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@<釘 commit SHA>
        with:
          persist-credentials: false
      - uses: actions/setup-node@<釘 commit SHA>
        with:
          node-version: "22"
          cache: npm
      - run: npm ci
      - run: npm run lint --if-present
      - run: npm test --if-present
      - run: npm run build --if-present
```

> action 一樣要釘 commit SHA，不然 zizmor 會紅。公版下一個要補的就是 `ci-node` 這個 job（見 [已知限制](docs/KNOWN-LIMITATIONS.md)）。
> Dependabot 要更新 npm 套件的話，照範本 `dependabot.yml` 檔尾的註解補一段 `npm`。

### 沒有 Dockerfile

`security.yml` 設 `scan-docker-image: false`、`ci.yml` 設 `run-docker-build: false`。
（公版找不到任何 Dockerfile 時會自己略過，不設也不會爆，但會白開一個 job、白花 runner 時間。）

### Dockerfile 不在根目錄、或不只一個

2.0.0 起不用特別設：`dockerfile` 留空時，Docker build、hadolint、image 掃描都會自動找全 repo 的
`Dockerfile`、`*.Dockerfile`、`Dockerfile.*`（略過 `node_modules`），有幾個就 build 幾個。
build context 預設是 repo 根目錄（`docker-context: "."`，跟 Visual Studio / docker-compose 產生的 .NET Dockerfile 慣例一致）。

只想檢查其中幾個、或某個 Dockerfile 的 build context 不一樣時，用 `dockerfile` 明確列（`ci.yml` 與 `security.yml` 各自設）：

```yaml
with:
  dockerfile: "src/Web.Api/Dockerfile"                      # 1.4.0 的單一路徑寫法照樣能用
  # dockerfile: "src/Web.Api/Dockerfile web/Dockerfile:web"  # 多個用空白隔開；:web ＝這一個用 web/ 當 build context
  # docker-context: "."                                     # 沒寫 :context 的那幾個用它，預設 repo 根目錄
```

明確列出的路徑不存在會直接紅（打錯字不會讓檢查安靜地被略過）。
`adopt.sh` / `adopt.ps1` 2.0.0 起不再寫 `dockerfile:`（公版自己會找）；你原本寫好的 `dockerfile:` 升級時會原樣保留。

### 導入初期紅到不想活

先設 `fail-on-findings: false` 讓它只回報不擋 → 分批清乾淨 → 再改回 `true`（能設分支保護的話，這時候再開）。
注意 `false` 只放行「有找到問題」，掃描工具本身出錯（規則或弱點資料庫下載失敗、當掉）照樣紅 ——
那種紅要看 log 處理，不是改參數能解決的。
**不要**直接刪掉 workflow。

### 抑制誤判

在專案根目錄放對應的 ignore 檔（公版會自動吃到）：

| 掃描器 | 檔案 | 寫法 |
|---|---|---|
| Semgrep | `.semgrepignore` | 一行一個路徑 glob |
| gitleaks | `.gitleaksignore` | 一行一個 `commit:path:rule:line` fingerprint（失敗訊息裡會印） |
| Trivy | `.trivyignore` | 一行一個 CVE / GHSA ID |
| zizmor | `.github/zizmor.yml` | `rules.<規則名>.ignore` 列檔名（範本已放行指向公版的 `@v2` 這類版本 tag），寫法見 [zizmor 文件](https://docs.zizmor.sh/configuration/) |
| hadolint | `.hadolint.yaml` | `ignored: [DL3008]` 這種列規則代碼 |

> 每一條 ignore 都應該在 PR 說明「為什麼這是誤判」。要抑制的是誤判，不是真弱點。

---

## 疑難排解

| 症狀 | 原因 | 解法 |
|---|---|---|
| `workflow was not found` / `not allowed` | 本 repo 是 private 且沒開組織存取 | Settings → Actions → General → Access → Accessible from repositories in the organization |
| PR 上找不到 `security / Security Gate` 這個 check | 還沒跑過第一次，或 job id 被改過 | 先讓 workflow 跑完一次，再回 ruleset 設定 |
| `pytest` 失敗但專案根本沒測試 | pytest 沒收到測試會回 exit code 5 | 公版已把 exit 5 當通過並提醒；仍紅的話看 log 是不是別的錯 |
| OSV-Scanner 紅、其他都綠 | 相依套件有已知 CVE | 看 log 的套件名 → 升版（Dependabot PR 通常已經開好了） |
| OSV-Scanner 紅、log 顯示 `rpc error: Internal` 且弱點數 0 | Google deps.dev 解析服務故障（上游問題，1.2.0 起會自動退回 `--no-resolve` 重掃並發 warning） | 免處理；若持續紅代表退回沒觸發，檢查 log 的 `failed resolution` 字樣 |
| gitleaks 抓到已經撤銷的舊 token | 密鑰留在 git 歷史裡 | **先去平台撤銷金鑰**，再把 fingerprint 加進 `.gitleaksignore` |
| Trivy 一堆 MEDIUM 把 PR 擋下 | `severity` 設太寬 | 縮回 `CRITICAL,HIGH` |
| zizmor 紅：`unpinned-uses` | 你自己寫的 workflow 用了 `actions/xxx@v4` 這種 tag | 改釘 commit SHA（tag 可以被移動，SHA 不行）；真的要放行寫進 `.github/zizmor.yml` |
| zizmor 紅：`template-injection` | `run:` 裡直接用了 `${{ github.event.xxx }}` | 先放進 `env:` 再用 `"$VAR"` 引用 |
| zizmor 紅：`dangerous-triggers` | 你自己的 workflow 用了 `pull_request_target` / `workflow_run` | 確定它不會執行 PR 的程式碼才放行；否則改用 `pull_request` |
| zizmor 紅：`excessive-permissions` | workflow 沒宣告 `permissions:` | 加 `permissions: contents: read`，需要什麼再加什麼 |
| 執行檔下載那一步紅：`sha256sum: WARNING: 1 computed checksum did NOT match` | 上游 release 檔案被換掉，或公版升版時校驗碼沒跟著改 | 到工具的 release 頁面重新對校驗碼；對不上就先別升、開 Issue |
| 改成 `@v2` 後整支 workflow 起不來：`Invalid input, upload-sarif is not defined`（或 `python-version`） | 2.0.0 移除了 `security-reusable` 的這兩個 input | 從 `security.yml` 的 `with:` 刪掉，或重跑一次 `adopt.sh` / `adopt.ps1`（會自動拿掉） |
| 升到 `@v2` 後 Python 的 lint / test 不見了 | 2.0.0 起 `run-python` 預設是 `false` | `ci.yml` 的 `with:` 加 `run-python: true` |
| `.NET build + test` 紅：「找到 N 個方案 / 專案檔，無法自動決定」 | repo 裡有兩個以上方案檔（或沒有方案檔、但有多個專案檔） | 在 `ci.yml` 設 `dotnet-project: "<路徑>"` |
| `.NET build + test` 的 format 步驟紅 | 程式碼不符合 `.editorconfig` 的格式或 analyzer 規則 | 本機跑 `dotnet format` 再 commit；舊專案過渡期可先 `run-dotnet-format: false` |
| `.NET build + test` 在 ubuntu 上建不起來（找不到 WindowsDesktop SDK 之類） | 專案目標是 `net*-windows`（WPF / WinForms）或 .NET Framework | 設 `dotnet-runner: windows-latest` |
| `fail-on-findings: false` 了卻還是紅 | 掃描工具本身出錯（規則／弱點資料庫下載失敗、當掉），或 OSV-Scanner 異常結束 —— 2.0.0 起這些不再被吞成綠燈 | 看該 job 的 log；多半是暫時性的網路問題，重跑一次 |
| `setup-branch-protection.sh` 回 403、提到 Upgrade to GitHub Pro | Free 方案的 private repo 不能用 ruleset | 見[沒辦法設分支保護時](#沒辦法設分支保護時) |
| Actions 分鐘燒很快 | image 掃描、每週排程、Dependabot PR 多 | 見[省 Actions 分鐘](#省-actions-分鐘這套怎麼省你還能怎麼省) |

---

## 版本策略

每次發佈都要打**兩個** tag：一個不可變的版本號、一個會移動的主版本別名。**目前的主版本是 `v2`**。

```bash
git tag -a v2.0.1 -m "..." && git push origin v2.0.1   # 不可變：出事時的還原點
git tag -f v2 && git push -f origin v2                 # 會移動的別名：所有指向 @v2 的專案自動跟進
```

| 情況 | 做法 |
|---|---|
| 修 bug、加掃描規則、升 action 版本、**新增有預設值的 input** | 打 `v2.x.y` + 移動 `v2` |
| 改 input 名稱 / 移除 input / 改 input 預設值造成行為改變 / 改 job 名稱 / 移除 workflow | 打 `v3.0.0` + 開 `v3`（`git tag -a v3.0.0 -m ...` 加 `git tag v3`），公告後各專案自行改 `@v2` → `@v3` |
| 想吃最新未打 tag 的版本 | 呼叫端寫 `@main`（不建議用在正式專案） |

| 主版本 | 狀態 |
|---|---|
| `v2` | **目前版本**（2.0.0 起）。新導入一律用 `@v2`，`adopt.sh` / `adopt.ps1` 預設就是它 |
| `v1` | **功能更新到 1.4.x 為止**。1.4.0（來源分支政策、`dockerfile` / `docker-context`）是 `v1` 最後一個功能版，之後只修 bug、不再加功能。還指向 `@v1` 的專案照常能跑，新功能請照下一節升到 `v2`（`v2` 包含 1.4.0 的全部內容） |

> ⚠️ **改完公版一定要移動目前的主版本 tag（`v2`）**，否則指向 `@v2` 的專案完全不會有感覺 —— main 領先 `v2` 好幾個 commit 卻沒人發現，是這套機制最容易出的事故。
>
> ⚠️ **只有會移動的 `v2` 是不夠的**。`v2` 移壞了就沒有「昨天的 v2」可退，所以每次都要留一個不可變的 `v2.x.y`。退回＝把 `v2` 指回上一個版本號。
>
> ⚠️ **`v1` 只能移到 1.4.x 的 bug 修正版**，絕不能指到 2.x 的 commit。它是還沒升級的專案唯一的依靠，移錯了等於把破壞性變更硬塞給它們。

### 從 v1 升級到 v2

2.0.0 有幾個**破壞性變更**（完整清單見 [CHANGELOG 2.0.0](CHANGELOG.md)）：

- `ci-reusable` 的 `run-python` 預設改成 `false`
- `security-reusable` 移除了 `python-version` 與 `upload-sarif`（還在傳的話整支 workflow `invalid input`）
- `fail-on-findings: false` 不再吞掉「掃描工具本身出錯」，那種情況會紅
- `dockerfile` 預設從 `"Dockerfile"` 改成留空＝自動找全 repo，以前沒被檢查到的子目錄 Dockerfile 也會 build / 掃描
  （1.4.0 明寫的 `dockerfile:` 照樣有效、升級時保留）
- Copilot 自動修 / 自動審整組移除，留在專案裡的那幾支呼叫端每次 PR 都會 `startup_failure`

升級步驟（每個已導入的專案各做一次）：

1. **刪掉 Copilot 呼叫端**（導入腳本不會幫你刪 —— 它從不刪專案裡既有的檔案）：

   ```bash
   git rm .github/workflows/copilot-autofix-ci-security.yml \
          .github/workflows/copilot-autofix-review.yml \
          .github/workflows/copilot-autoreview-gate.yml \
          .github/workflows/copilot-setup-steps.yml
   ```

   `.github/copilot-instructions.md` 可以留著（Copilot 在 IDE 裡仍會讀它），
   repo secret `COPILOT_TRIGGER_PAT` 已無人使用，可以一併刪掉。
   `.github/zizmor.yml` 裡若還有指向那幾支 copilot workflow 的放行（例如 `dangerous-triggers`），一起拿掉。

2. **用預設的 ref 重跑一次導入腳本**（預設就是 `v2`，不必加 `--ref`）：

   ```bash
   /path/to/ci-standards/scripts/adopt.sh            # 或 adopt.ps1
   ```

   它會把 `uses:` 改成 `@v2`、拿掉 `python-version` / `upload-sarif`、補上新 input（含依偵測結果寫明的 `run-python` / `run-dotnet`），
   你調過的參數原樣保留。

3. **看腳本最後印的「觸發條件（v2）」那一行**：
   - 你的 `ci.yml` 還是 v1 範本原樣 → 腳本已經自動把 `pull_request` 加上 `edited`、並更新 job 的 `if` 與 `concurrency`（修「改 base 繞過分支政策」的洞）
   - 印出 ⚠️「沒有自動改」→ 你改過觸發條件，請照公版範本 `templates/consumer-repo/.github/workflows/ci.yml` 手動補那三行
     （有設 `restricted-base-branches` 時一定要補）
   - `security.yml` 的 `concurrency` 還是 v1 範本原樣的話，也會一併改成依事件分組（排程重掃不再跟 push 互相取消）

4. **確認 `run-python`**：Python 專案要是 `true`。腳本會依偵測結果寫，但偵測不到（例如 Python 檔藏得很深）時請自己改。

5. `git diff` 看過、開 PR，等兩個 Gate 都綠再 merge。

**分支保護不必改**：job 名稱沒變，`ci / CI Gate`、`security / Security Gate` 照舊。
想順便補上 2.0.0 的「required check 只認 GitHub Actions 發的」（`integration_id`），重跑一次 `setup-branch-protection.sh` 即可（同名 ruleset 會更新，不會多一份）。

發佈過哪些版本、每版改了什麼，記在 [CHANGELOG.md](CHANGELOG.md)。

發佈的實際操作（tag 釘完整 SHA 而不是 HEAD、用 `git ls-remote` 驗收、tag 只能在本機推）
寫在 [`docs/HANDOFF.md`](docs/HANDOFF.md) §3「發佈流程」。
想知道 `v2` 現在落後 `main` 什麼，跑這行就夠：

```bash
git log --oneline v2..main -- .github/workflows templates scripts
```

有輸出＝有還沒發佈的實質變更；只有 `docs/` 在動的話可以不發版。

---

## 檔案地圖

```
ci-standards/
├── README.md                          ← 本文件
├── CHANGELOG.md                       ← 發佈過哪些版本、每版改了什麼
├── CONTRIBUTING.md                    ← 要改公版 / 要提需求的人看這裡
├── SECURITY.md                        ← 弱點回報管道、這個 repo 自己的供應鏈防護
├── LICENSE
│
├── .github/                           ← ⚠️ 這裡有兩種東西，別搞混
│   ├── workflows/
│   │   │  ── ① 公版本體（給別人 uses: 呼叫的）──
│   │   ├── security-reusable.yml          ← 安全公版（Semgrep+OSV+Trivy+gitleaks+zizmor+Security Gate）
│   │   ├── ci-reusable.yml                ← CI 公版（Python + .NET + Docker/hadolint + actionlint/shellcheck + 分支政策）
│   │   │
│   │   │  ── ② 本 repo 自己的呼叫端（公版拿自己當第一個使用者，用 ./ 呼叫上面那些）──
│   │   ├── ci.yml                         ← 自己跑 actionlint（含範本）+ shellcheck + 分支政策
│   │   ├── security.yml                   ← 自己跑全部安全掃描（含 zizmor）
│   │   │
│   │   │  ── ③ 本 repo 自己的工具測試（不是公版，consumer 不會有這支）──
│   │   └── adopt-tests.yml                ← 跑 scripts/test-adopt.sh，ubuntu / macOS / Windows 三平台；只動文件時整個跳過
│   ├── zizmor.yml                     ← 本 repo 的 zizmor 放行規則（連 templates/ 一起管）
│   ├── ISSUE_TEMPLATE/                ← bug / feature 兩種 Issue 表單
│   ├── copilot-instructions.md        ← 給 AI 助理看的「改這個 repo 的鐵則」
│   ├── pull_request_template.md       ← 本 repo 自己的 PR 檢查清單
│   ├── CODEOWNERS
│   └── dependabot.yml                 ← 本 repo 只有 github-actions 相依，每月
│
├── .gitattributes                     ← 強制 LF 簽出；沒有它 Windows 會踩到 CRLF 的雷
├── scripts/
│   ├── adopt.sh                       ← 一鍵導入（macOS / Linux / Git Bash）
│   ├── adopt.ps1                      ← 一鍵導入（Windows PowerShell 5.1，零安裝；必須存 UTF-8 有 BOM）
│   ├── setup-branch-protection.sh     ← 一鍵建立分支保護 ruleset（需要 gh）
│   └── test-adopt.sh                  ← adopt.sh 的回歸測試（在暫存目錄裡建測試 repo，不會動到本 repo）
├── docs/
│   ├── FLOW.md                        ← 流程圖：一個 PR 從打開到能 merge 發生什麼、由哪支檔案負責
│   ├── HANDOFF.md                     ← 現況與待辦（換人／換機器接手時先讀這份）
│   ├── ADOPT.md                       ← 一鍵導入的跨平台說明、內網/離線做法、要不要 gh
│   ├── SETUP.md                       ← 管理者用：公版發佈、方案/額度
│   ├── KNOWN-LIMITATIONS.md           ← ⚠️ 實測過但「還不能用」的東西，導入前必看
│   ├── MIGRATION-TO-ORG.md            ← 把本 repo 搬到組織底下的 checklist
│   ├── DEVSECOPS-NOTES.md             ← 工具怎麼選：為什麼是這幾套、哪些評估過但沒放進來
│   └── openspec-dev-standards-report-2026-08-29.md
│                                      ← 跨專案開發規範盤點與下一階段（OpenSpec／多 Agent）規劃，不是公版本體
└── templates/consumer-repo/.github/   ← 各專案要複製過去的「呼叫端」範本
    ├── zizmor.yml                     ← zizmor 放行規則（公版 @v2 只要求釘 tag）
    ├── dependabot.yml                 ← pip / docker / actions；nuget / npm 寫在檔尾註解，要用再打開
    ├── pull_request_template.md
    └── workflows/
        ├── security.yml               ← 呼叫安全公版
        └── ci.yml                     ← 呼叫 CI 公版
```

> **`ci.yml` 與 `ci-reusable.yml` 不是兩份要同步的副本**（`security.yml` / `security-reusable.yml` 同理）。
> `*-reusable.yml` 是公版本體；`ci.yml` / `security.yml` 是本 repo 自己的呼叫端，用 `./` 呼叫「同一個 commit 的」reusable，
> 所以改公版的 PR 當場就用改過的版本跑，不必、也不能手動同步。
> 要保持一致的是另一組：**本 repo 的呼叫端 ↔ `templates/consumer-repo/` 的範本** ——
> 觸發條件、`permissions`、`concurrency`、job 的 `if` 必須一樣；只有 `uses:`（`./` vs `@v2`）、`push.branches`、`with:` 的開關可以不同。
> 改其中一邊時另一邊要一起改。

---

## 這套涵蓋什麼、不涵蓋什麼

**涵蓋**（開發階段就先擋）

| 面向 | 工具 | 抓什麼 | 抓不到什麼 |
|---|---|---|---|
| 程式碼弱點 SAST | Semgrep（OWASP Top 10 + security-audit + secrets + auto） | SQL injection、eval、不安全的反序列化這類「寫法」問題 | 要跑起來才會發生的邏輯漏洞 |
| 相依套件 CVE | OSV-Scanner + Dependabot | lockfile / manifest 裡的套件有沒有已知 CVE | 沒有 lockfile 的專案只能掃直接相依 |
| 檔案系統 / IaC / Dockerfile 設定 | Trivy（vuln + misconfig，可選 license / SBOM） | Dockerfile 用 root、K8s privileged、Terraform 對外全開、授權條款 | 執行期的設定漂移 |
| 密鑰外洩 | gitleaks（含 git 歷史） | token / 密碼 / 私鑰 commit 進 repo | 沒有固定格式的密鑰（自訂規則可補） |
| workflow 本身的安全 | zizmor（可選，建議開） | 腳本注入、危險觸發器、沒釘 SHA 的 action、權限過大、checkout 留下 token | workflow 呼叫的外部工具本身的漏洞 |
| Container image CVE | Trivy image（可選） | build 出來的 image 裡 OS 套件與語言套件的 CVE | 上游還沒修的 CVE（預設 ignore-unfixed） |
| Dockerfile 寫法 | hadolint（可選） | 沒釘版本的 apt、`latest`、`RUN` 裡的 shell 問題 | 不是安全問題的效能寫法 |
| 程式碼品質 | ruff + pytest（Python）；dotnet format + build + test（.NET）；actionlint + shellcheck | lint、建置、測試、workflow 語法、shell 語法 | 測試本身寫得好不好；**前端（Node）的 lint / 測試 / build 公版還沒有**，見[前端](#前端react--vue--node) |

**不涵蓋**：WAF、EDR、SIEM、CSPM、runtime 偵測、滲透測試、DAST（ZAP）、SBOM 簽章（cosign）。
把它當「把明顯的炸彈擋在 main 之外」的第一道防線，很稱職；但它不是完整資安防護。

**評估過但沒放進來的工具**（Bandit、pip-audit、Checkov、TruffleHog、CodeQL、SonarQube、ZAP、Scorecard…）
與理由，見 [`docs/DEVSECOPS-NOTES.md`](docs/DEVSECOPS-NOTES.md)。一句話版：多半跟現有工具重疊，多開一個 job 就多付一分鐘。

### 為什麼私有 repo 也能免費跑

- 不上傳到需付費的 Security 分頁（code scanning），改用「**job 成敗當關卡 + artifact**」
- gitleaks 用 **docker 執行檔**跑，避開 `gitleaks-action` 對組織帳號的授權要求
- 用 **OSV-Scanner** 取代需要 GHAS 的 dependency-review-action
- 全部工具皆開源免費，只消耗 GitHub Actions 分鐘

### 這個 repo 自己的供應鏈防護

公版一改就影響所有專案，所以它抓下來的東西全部釘死：action 釘 commit SHA、container image 釘 tag + digest、
直接下載的執行檔（OSV-Scanner、actionlint、zizmor、hadolint）釘版本 + sha256，
下載用 `curl --fail`、對完校驗碼才執行。細節見 [SECURITY.md](SECURITY.md)。

---

## 延伸閱讀

| 文件 | 給誰看 |
|---|---|
| [`docs/FLOW.md`](docs/FLOW.md) | 讀 README 之前的地圖 —— 一個 PR 從打開到能 merge，中間發生什麼、由哪支檔案負責 |
| [`docs/HANDOFF.md`](docs/HANDOFF.md) | **接手的人（含 AI）先讀這份** —— 現況快照、下一步做什麼、踩過哪些雷 |
| [`docs/ADOPT.md`](docs/ADOPT.md) | 一鍵導入 —— Windows / macOS、內網與離線做法、`gh` 是不是必要 |
| [`docs/KNOWN-LIMITATIONS.md`](docs/KNOWN-LIMITATIONS.md) | **導入前必看** —— 實測過但還不能用的功能，含查問題的步驟 |
| [`docs/SETUP.md`](docs/SETUP.md) | 管理者 —— 公版發佈、方案與額度 |
| [`docs/MIGRATION-TO-ORG.md`](docs/MIGRATION-TO-ORG.md) | 管理者 —— 搬到組織底下的 checklist |
| [`docs/DEVSECOPS-NOTES.md`](docs/DEVSECOPS-NOTES.md) | 想知道工具怎麼選、哪些評估過但沒放進來的人 |
| [`docs/openspec-dev-standards-report-2026-08-29.md`](docs/openspec-dev-standards-report-2026-08-29.md) | 想知道「下一階段」怎麼規劃的人 —— 跨專案開發規範盤點、CLAUDE.md／rules／hooks 分層、OpenSpec 與多 Agent 工作流評估 |
| [`CONTRIBUTING.md`](CONTRIBUTING.md) | 要改公版、要提需求的人 |
| [`CHANGELOG.md`](CHANGELOG.md) | 想知道 `v2` 現在是什麼、從 `v1` 升上來改了什麼的人 |
| [`SECURITY.md`](SECURITY.md) | 要回報弱點的人 |
