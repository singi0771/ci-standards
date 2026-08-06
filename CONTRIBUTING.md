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

本 repo 沒有 Python，CI 檢查的是 workflow 語法與 shell script：

```bash
# workflow 語法（這個 image 內建 shellcheck，會連 run: 區塊的 bash 一起檢查）
docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:1.7.12 -color

# consumer 範本也要檢查 —— 範本壞掉的話，每個照著導入的專案都會壞
docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:1.7.12 -color \
  'templates/consumer-repo/.github/workflows/*.yml'

# shell script
shellcheck scripts/*.sh
```

### 3. 送 PR 前的自我檢查

這幾條每一條都對應過去真的踩過的坑：

- [ ] **有沒有改到 input 名稱或 job 名稱？**
      consumer 的 ruleset 綁著 `ci / CI Gate`、`security / Security Gate` 這些字串，
      改名會讓既有專案的 required check 永遠 pending。這種改動要開 `v2`，不能移 `v1`
- [ ] **新增的 job 有沒有加進 `security-gate` / `ci-gate` 的 `needs`？**
      沒加＝這個檢查不會擋門，形同虛設
- [ ] **有 `if` 條件的新 job 有沒有被設成 required check？**
      不可以。`skipped` 的 required check 永遠不回報 → PR 永久卡在 pending。
      只把它加進 gate 的 `needs`，由 gate 判斷（只有 `failure` / `cancelled` 才擋）
- [ ] **新 action 與新 container image 有沒有釘版本？**
      不要用 `@main` / `@master` / `:latest`。理由有二：供應鏈風險，
      以及上游升版新增規則會讓沒改碼的 repo 突然變紅
- [ ] **掃描工具「執行失敗」有沒有被當成「通過」？**
      下載用 `curl --fail`，執行前先驗 `--version`，未預期的 exit code 一律擋下
- [ ] **外部輸入有沒有先過 `env:`？**
      不要把 `${{ }}` 直接插進 `run:` 字串（shell injection）。
      這條連 `github.repository` 這種不可控的值也照做 —— 公版是給人抄的，寫法會被抄走
- [ ] **新增的自動留言有沒有收斂機制？**
      次數上限 + 隱藏 marker 去重 + 達上限後停止（不是繼續重貼）。
      沒有上限的迴圈會燒光 AI credits 並把通知塞爆
- [ ] **README / CHANGELOG 有沒有跟著改？**
      新增 input 一定要進 README 的參數表 —— 沒寫在文件上的功能等於不存在

### 4. 合併之後：一定要發佈

⚠️ **合進 main 不等於生效。** 所有專案指向 `@v1`，沒有移動 tag 的話它們完全不會有感覺。

```bash
git tag -a v1.2.0 -m "說明" && git push origin v1.2.0   # 不可變的回滾點
git tag -f v1 && git push -f origin v1                  # 大家指向的別名
```

並在 [CHANGELOG.md](CHANGELOG.md) 補上這一版。

> 破壞性變更（改／移除 input、改 job 名稱）走 `v2`，並公告各專案自行把 `@v1` 改成 `@v2`。

### 5. 高風險改動先試跑

動到掃描邏輯、gate 判定、Copilot 迴圈時，先在一個真實專案用 `@main` 跑過一輪，
再移動 `v1`。本 repo 自己的 CI 用 `./` 呼叫公版，PR 上就會用「這個 PR 的版本」跑，
是第一道保險，但它涵蓋不到 Python / Docker 那幾條路徑。

---

## Commit 訊息

用 Conventional Commits：`feat:` / `fix:` / `docs:` / `refactor:` / `build(deps):`。
影響範圍寫在 scope 裡會更好讀：`fix(security):`、`fix(copilot):`。

## PR

- 每個 PR 聚焦單一目的，附「為什麼」與「怎麼驗證」
- 不要為了讓 PR 變綠而停用或跳過既有檢查
- PR 模板的檢查清單請據實勾選
