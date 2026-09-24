# 已知限制（導入前先看）

這份文件記的是**實測過、但目前還不能用**的東西。
每一條都寫清楚：怎麼測的、結果是什麼、影響哪一段流程、以及查問題的步驟。

> 為什麼要有這份文件：這些結論原本只存在於某個已關閉 PR 的留言裡，
> 後來導入的人看不到，只會重踩一次同樣的雷。

| 限制 | 影響 | 現在該怎麼辦 |
|---|---|---|
| [`upload-sarif: true` 尚未驗證可用](#upload-sarif-true-尚未驗證可用) | Security 分頁整合 | 維持 `false`，用 artifact |
| [只有 Python 的 lint/test](#ci-reusable-只內建-python-的-linttest) | 非 Python 專案 | `run-python: false` + 自己補一支 |

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

## `upload-sarif: true` 尚未驗證可用

**狀態：🟡 疑似不可用，維持 `false`**

`security-reusable.yml` 的 workflow 層 `permissions` 是 `contents: read`。
被呼叫的 reusable workflow **只能縮減呼叫端授予的權限、不能擴張**，
所以呼叫端就算自己加了 `security-events: write`，進到公版的 job 仍可能被縮掉 → upload 回 403。

也就是說 README 上「呼叫端 job 自行加 `permissions:`」這個說法**還沒有被實測證實**。

**查問題的步驟：**

1. 在本 repo（public，不需要 GHAS）開一個測試 PR，把 `.github/workflows/security.yml` 的
   `upload-sarif` 改成 `true`，並在該 job 加上 `permissions: { contents: read, security-events: write }`
2. 看 `Upload SARIF to Security tab` 這一步的結果：
   - 成功 → 只要更新文件說明「呼叫端必須自行加 permissions」
   - 403 / Resource not accessible → 公版要改：在 `security-reusable.yml` 的 workflow 層
     直接宣告 `security-events: write`。**但這是破壞性變更** —— 沒有授予該權限的呼叫端可能整支起不來，
     要按[版本策略](../README.md#版本策略)開 `v2`，不能移 `v1`
3. 在這之前，掃描結果一律走 artifact（`semgrep-sarif`），功能上沒有損失

---

## `ci-reusable` 只內建 Python 的 lint/test

**狀態：🟢 已知設計取捨，不是 bug**

`ci-reusable.yml` 內建的是 ruff + pytest。其餘語言目前沒有對應的 job。

非 Python 專案**仍然照用公版**，把 Python 關掉即可（`run-python: false`），
`actionlint` / `shellcheck` / `docker build` / `hadolint` 都是語言無關的，
安全掃描那邊（Semgrep / OSV / Trivy / gitleaks / zizmor）本來就自己認語言。
要語言原生的 lint/test，見 [README — 專案不是 Python](../README.md#專案不是-python)。

> 推廣到更多專案之前，先盤點一次組織內的語言分布。
> 如果 Node 專案佔比高，補一支 `ci-node-reusable.yml` 的優先度會高於其他所有待辦。

---

## 這份文件怎麼維護

- 每解決一條，把它**從這裡刪掉**，並在 [CHANGELOG](../CHANGELOG.md) 記一筆
- 新發現的限制，一律附上「怎麼測的 + 結果 + 查問題的步驟」，不要只寫「XX 好像不能用」
- 查問題的步驟要能讓沒有前後文的人照著跑
