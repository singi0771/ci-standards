<!--
這是 ci-standards 自己的 PR 模板（中央公版 repo 用）。
給各專案複製的那份在 templates/consumer-repo/.github/pull_request_template.md，不要改錯。
-->

## 修改目的
<!-- 為什麼要做這個變更？解決什麼問題 / Issue？ -->

## 修改內容
<!-- 具體改了什麼 -->

## 影響範圍

- [ ] 只動文件 / 範例，不影響任何專案的 CI 行為
- [ ] 動到公版邏輯 —— **所有指向 `@v1` 的專案下次跑 CI 就會吃到**
- [ ] 動到 `templates/` —— 影響之後新導入的專案

## 相容性（動到公版邏輯時必填）

- [ ] 沒有改／移除任何 input 名稱
- [ ] 沒有改任何 job 名稱（使用端的 ruleset 綁著 `ci / CI Gate`、`security / Security Gate`）
- [ ] 若有以上任一項 → **這是破壞性變更，要開 `v2`，不能移 `v1`**

## 公版自我檢查
<!-- 每一條都對應過去真的踩過的雷，詳見 CONTRIBUTING.md -->

- [ ] 新增的 job 已加進 `ci-gate` / `security-gate` 的 `needs`
- [ ] 有 `if` 條件的 job **沒有**被設成 required check
- [ ] 新 action 釘了 commit SHA、新 image 釘了 digest、新下載的執行檔有 sha256（不用 `@main`、`:latest`）
- [ ] 掃描工具「執行失敗」會擋下，不會被當成通過
- [ ] 外部輸入先過 `env:`，沒有把 `${{ }}` 直接塞進 `run:` 字串
- [ ] 新增的自動留言有次數上限 + 標記防重複 + 達上限後停止
- [ ] 沒有為了一個不到 30 秒的檢查另開一個 job（每個 job 至少算一分鐘）

## 怎麼驗證的

- [ ] `actionlint`（含 `templates/` 那次）
- [ ] `zizmor .`
- [ ] `shellcheck scripts/*.sh`
- [ ] `bash scripts/test-adopt.sh`（動到 `scripts/` 或 `templates/` 時）
- [ ] 本 repo 的 CI + Security Scan + adopt 回歸測試全綠（用 `./` 跑的是這個 PR 的版本）
- [ ] 高風險改動：已在真實專案用 `@main` 試跑
- [ ] 其他（說明）：

## 文件

- [ ] 新增／變更的 input 已寫進 README 參數表
- [ ] CHANGELOG.md 已補上這次改動
- [ ] 若解決了某條已知限制，已從 `docs/KNOWN-LIMITATIONS.md` 移除

## 合併後要做的事

- [ ] 打 `vX.Y.Z` 不可變 tag
- [ ] 移動 `v1`（**不做的話所有專案完全不會有感覺**）
