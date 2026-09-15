# 參與這個 repo

這裡是**中央公版**。改動一次會同時影響所有指向 `@v1` 的專案，
所以流程比一般 repo 嚴格一點 —— 不是官僚，是因為改壞了會讓所有人的 PR 一起卡住。

---

## 我想…

| 我想做的事 | 去哪裡 |
|---|---|
| 把公版導入我的專案 | [README — 5 分鐘導入](README.md#5-分鐘導入一個新專案)，不用來這裡 |
| 我的 CI 紅了 | [README — 疑難排解](README.md#疑難排解) |
| 某個功能好像壞了 | 先看 [已知限制](docs/KNOWN-LIMITATIONS.md)，不在上面再開 Issue |
| 要求支援新語言 / 新掃描工具 | 開 Issue（見下方「提需求」） |
| 直接改公版 | 往下看 |
| 回報安全弱點 | **不要開 Issue**，見 [SECURITY.md](SECURITY.md) |

---

## 提需求

開 Issue 時請寫清楚三件事，否則很難判斷該不該進公版：

1. **哪個專案、什麼情境需要**（例如「我們有 3 個 Node 專案，現在只能自己寫 CI」）
2. **希望公版提供什麼**（新的 reusable？既有 reusable 的新 input？）
3. **不做的話你現在怎麼繞過**（有時繞過方式就夠了，不必進公版）

> 判斷原則：**只有「多個專案都會用到」的東西才進公版**。
> 單一專案的特殊需求，放在那個專案自己的 workflow 裡。

---

## 改公版的流程

### 1. 開分支，不要直接推 main

main 有分支保護：必須開 PR、必須通過 `ci / CI Gate` 與 `security / Security Gate`。

### 2. 本地先驗

本 repo 沒有 Python，CI 檢查的是 workflow 語法、workflow 安全、shell script 與導入腳本：

```bash
# workflow 語法（PATH 上有 shellcheck 的話，actionlint 會連 run: 區塊的 bash 一起檢查）
actionlint -color

# consumer 範本也要檢查 —— 範本壞掉的話，每個照著導入的專案都會壞
actionlint -color 'templates/consumer-repo/.github/workflows/*.yml'

# workflow 安全（會連 templates/ 一起掃；本 repo 的放行規則在 .github/zizmor.yml）
zizmor .

# shell script
shellcheck scripts/*.sh

# 導入腳本的回歸測試（會自己 cd 到暫存目錄，不會動到本 repo）
bash scripts/test-adopt.sh
```

工具怎麼裝：actionlint / shellcheck / hadolint 到各自的 GitHub release 抓執行檔即可；
zizmor 可以 `pip install zizmor`。沒裝也沒關係 —— PR 上的 CI 跑的就是這幾支，只是慢一輪。

改到 `adopt.ps1` 的話，另外在 Windows 上確認 PowerShell **5.1** 載得起來（檔頭有指令），
而且檔案要維持 UTF-8 **有** BOM。

### 3. 送 PR 前的自我檢查

這幾條每一條都對應過去真的踩過的雷：

- [ ] **有沒有改到 input 名稱或 job 名稱？**
      consumer 的 ruleset 綁著 `ci / CI Gate`、`security / Security Gate` 這些字串，
      改名會讓既有專案的 required check 永遠 pending。這種改動要開 `v2`，不能移 `v1`
- [ ] **新增的 job 有沒有加進 `security-gate` / `ci-gate` 的 `needs`？**
      沒加＝這個檢查不會擋 PR，形同虛設
- [ ] **有 `if` 條件的新 job 有沒有被設成 required check？**
      不可以。被跳過的 required check，GitHub 要嘛當通過（等於沒檢查）、要嘛永遠 pending。
      只把它加進 gate 的 `needs`，由 gate 判斷（開了就必須 success）
- [ ] **新 action、container image、下載的執行檔有沒有釘死？**
      action 釘 commit SHA、image 釘 tag + digest、執行檔釘版本 + sha256。
      不要用 `@main` / `@master` / `:latest`。理由有二：供應鏈風險，
      以及上游升版新增規則會讓沒改程式的 repo 突然變紅
- [ ] **掃描工具「執行失敗」有沒有被當成「通過」？**
      下載用 `curl --fail`，`sha256sum -c` 對校驗碼，執行前先驗 `--version`，未預期的 exit code 一律擋下
- [ ] **有沒有多開一個不必要的 job？**
      每個 job 不滿一分鐘也算一分鐘。跑不到 30 秒的檢查併進既有 job 當步驟
- [ ] **`actions/checkout` 有沒有 `persist-credentials: false`？**
      這個 repo 沒有任何 job 需要 push，token 不該留在磁碟上（zizmor 會抓）
- [ ] **外部輸入有沒有先過 `env:`？**
      不要把 `${{ }}` 直接插進 `run:` 字串（shell injection）。
      這條連 `github.repository` 這種不可控的值也照做 —— 公版是給人抄的，寫法會被抄走
- [ ] **新增的自動留言有沒有停止條件？**
      次數上限 + 隱藏標記 防重複 + 達上限後停止（不是繼續重貼）。
      沒有上限的迴圈會燒光 AI credits 並把通知塞爆
- [ ] **README / CHANGELOG 有沒有跟著改？**
      新增 input 一定要進 README 的參數表 —— 沒寫在文件上的功能等於不存在

### 4. 合併之後：一定要發佈

⚠️ **合進 main 不等於生效。** 所有專案指向 `@v1`，沒有移動 tag 的話它們完全不會有感覺。

```bash
git tag -a v1.2.0 -m "說明" && git push origin v1.2.0   # 不可變的還原點
git tag -f v1 && git push -f origin v1                  # 大家指向的別名
```

並在 [CHANGELOG.md](CHANGELOG.md) 補上這一版。

> 破壞性變更（改／移除 input、改 job 名稱）走 `v2`，並公告各專案自行把 `@v1` 改成 `@v2`。

### 5. 高風險改動先試跑

動到掃描邏輯、gate 判定、Copilot 迴圈時，先在一個真實專案用 `@main` 跑過一輪，
再移動 `v1`。本 repo 自己的 CI 用 `./` 呼叫公版，PR 上就會用「這個 PR 的版本」跑，
是第一道保險，但它涵蓋不到 Python / Docker / hadolint / image 掃描那幾條路徑。

### 6. 升級某個掃描工具的版本

Dependabot 只會幫 `uses:` 的 action 升版。下面這幾個是**人工釘死**的，要升要自己來：

| 工具 | 在哪 | 怎麼拿新的校驗碼 |
|---|---|---|
| OSV-Scanner | `security-reusable.yml` 的 `VERSION` / `SHA256` | release 頁面的 `osv-scanner_SHA256SUMS`，找 `linux_amd64` 那行 |
| zizmor | `security-reusable.yml` | 抓 `zizmor-x86_64-unknown-linux-gnu.tar.gz` 自己 `sha256sum` |
| actionlint | `ci-reusable.yml` | release 的 `actionlint_<版本>_checksums.txt` |
| hadolint | `ci-reusable.yml` | release 的 `checksums.sha256`，找 `linux-x86_64` |
| Semgrep image | `security-reusable.yml` 的 `container.image` | `docker buildx imagetools inspect semgrep/semgrep:<版本>` 的 digest |
| gitleaks image | `security-reusable.yml` 的 `docker run` | `docker buildx imagetools inspect ghcr.io/gitleaks/gitleaks:<版本>` 的 digest |
| ruff | `ci-reusable.yml` 的 `ruff-version` 預設值 | 不用校驗碼（pip 有自己的 hash 機制），但要記得新版可能多規則 |

原則：**剛發布的版本先等一週**（跟 Dependabot 的 7 天 cooldown 一樣），掃描器升版等於所有專案一起吃到新規則，
先在本 repo 的 PR 上看一輪綠燈再移 `v1`。

---

## Commit 訊息

用 Conventional Commits：`feat:` / `fix:` / `docs:` / `refactor:` / `build(deps):`。
影響範圍寫在 scope 裡會更好讀：`fix(security):`、`fix(copilot):`。

## PR

- 每個 PR 聚焦單一目的，附「為什麼」與「怎麼驗證」
- 不要為了讓 PR 變綠而停用或跳過既有檢查
- PR 模板的檢查清單請據實勾選
