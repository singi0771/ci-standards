# 已知限制（導入前先看）

這份文件記的是**實測過、但目前還不能用**的東西。
每一條都寫清楚：怎麼測的、結果是什麼、影響哪一段流程、以及查問題的步驟。

> 為什麼要有這份文件：這些結論原本只存在於某個已關閉 PR 的留言裡，
> 後來導入的人看不到，只會重踩一次同樣的雷。

| 限制 | 影響 | 現在該怎麼辦 |
|---|---|---|
| [只內建 Python 與 .NET 的 lint/test](#ci-reusable-只內建-python-與-net-的-linttest) | 其他語言、前端（React / Vue / Node） | 安全掃描照用；CI 的 lint/test 在呼叫端自己補一個 job |
| [沒有分支保護時紅燈擋不住 merge](#沒有分支保護時紅燈擋不住-merge) | Free 方案的 private repo、公司統一管制的 repo | 照 README「沒辦法設分支保護時」補位 |

---

## 實測基準：故意植入錯誤的測試 PR（2026-07-26）

查問題前先知道「哪些是確定好的」，才不會亂改。

做法：開一個 PR 故意植入三個錯誤 —— shellcheck 的 `SC2086`（未引用的 `rm -rf $TARGET`）、
`SC2045`（用 `ls` 輸出當迴圈來源）、以及把 `actions/checkout` 從釘死的 SHA 改回可變 tag（Semgrep 會抓）。

**確認可用的（不用再花時間查問題）：**

| 觀察項 | 結果 |
|---|---|
| `ci / CI Gate` 與 `security / Security Gate` 都變紅 | ✅ 三個植入的錯誤全被抓到 |
| 修好之後兩個 Gate 都回到綠 | ✅ |

> 這個基準是「Gate 真的擋得住」的證據。要重測就照上面植入同樣三個錯誤，
> 看兩個 Gate 會不會紅 —— 綠的話就是 Gate 判定寫壞了，那是最該立刻查的事。

---

## `ci-reusable` 只內建 Python 與 .NET 的 lint/test

**狀態：🟢 已知設計取捨，不是 bug**

`ci-reusable.yml` 內建兩種語言的 job，都是預設關、用到才開：

- Python：ruff + pytest（`run-python`）
- .NET（C# / F# / VB）：`dotnet format` + build + test（`run-dotnet`，2.0.0 新增）

其餘語言目前沒有對應的 job。這些專案**仍然照用公版**：`actionlint` / `shellcheck` / `docker build` / `hadolint`
都是語言無關的，安全掃描那邊（Semgrep / OSV / Trivy / gitleaks / zizmor）本來就自己認語言。
要語言原生的 lint/test，見 [README — 專案不是 Python](../README.md#專案不是-python)。

### 前端（React / Vue / Node）：安全掃描有、CI 沒有

| | 狀況 |
|---|---|
| Semgrep | ✅ `auto` 會挑 JS / TS 規則。⚠️ 對 `.vue` 單檔元件的支援有限，`<script>` 裡的程式可能只掃到一部分 |
| OSV-Scanner、Trivy（檔案系統） | ✅ 讀 `package-lock.json` / `yarn.lock` / `pnpm-lock.yaml` |
| gitleaks | ✅ 不分語言 |
| eslint、`tsc`、vitest / jest、`npm run build` | ❌ 公版沒有 Node 的 job，一個都不會跑 |

**現在的做法**：在專案自己的呼叫端 workflow 寫一個 job 跑 `npm ci` / lint / test / build，
用不同的 job id（例如 `node`），範例見 [README — 前端](../README.md#前端react--vue--node)。
**下一個要補的**就是公版的 `ci-node` job（加進 `ci-gate` 的 `needs`，呼叫端用一個 `run-node` 打開）。

> 推廣到更多專案之前，先盤點一次組織內的語言分布。
> 如果前端專案佔比高，`ci-node` 的優先度會高於其他所有待辦。

---

## 沒有分支保護時紅燈擋不住 merge

**狀態：🟢 平台限制，不是 bug**

Gate 會不會「擋住 merge」完全取決於 GitHub 的分支保護 / ruleset，公版本身做不到。
GitHub Free 方案的 **private** repo 不能用 ruleset（API 回 `403 Upgrade to GitHub Pro…`），
公司統一管理的 repo 也可能不讓各專案自己設。

這種 repo 一樣照常導入：Gate 照跑、照樣紅、push 到 main 之後也會再跑一輪，只是紅燈擋不住有寫入權限的人按 merge。
補位做法（團隊約定、merge 後看 main 那一輪、限縮寫入權限、需要時升級方案）見
[README — 沒辦法設分支保護時](../README.md#沒辦法設分支保護時)。

---

## 這份文件怎麼維護

- 每解決一條，把它**從這裡刪掉**，並在 [CHANGELOG](../CHANGELOG.md) 記一筆
- 新發現的限制，一律附上「怎麼測的 + 結果 + 查問題的步驟」，不要只寫「XX 好像不能用」
- 查問題的步驟要能讓沒有前後文的人照著跑
