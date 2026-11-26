# GitHub Actions 分鐘數

公版在私有 repo 上每跑一次都會扣 Actions 額度。本文件說明計費規則、公版各 workflow 的最低用量與估算方式。
導入腳本（`adopt.sh`／`adopt.ps1`）結束時印出的預估即依本文件計算。

> 計費規則摘自 GitHub 官方文件（2026-11 查證）：
> [GitHub Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions)、
> [Actions runner pricing](https://docs.github.com/en/billing/reference/actions-runner-pricing)。
> GitHub 調整價格時以官方文件為準。

## 計費規則

| 規則 | 說明 |
|---|---|
| 每個 job 各自進位 | 每個 job 的執行時間無條件進位到整分鐘。跑 10 秒的 job 計 1 分鐘。官方原文：*"GitHub rounds the minutes and partial minutes each job uses up to the nearest whole minute."* |
| 畫面上的 Total duration 不是計費時間 | Total duration 是整個 workflow 從開始到結束的時間；多個 job 並行時，計費是各 job 進位後的加總 |
| 跳過的 job 不計費 | `if:` 為 false 的 job（畫面上灰色斜線）不佔 runner，不計費 |
| 公開 repo 免費 | 公開 repo 使用 GitHub 代管的標準 runner 不計費。ci-standards 本身是公開 repo，不佔額度 |
| 費用算在 repo 擁有者 | 私有 repo 的用量計入 repo 擁有者（個人帳號或組織），不是觸發者。同一擁有者底下的所有私有 repo 共用同一份每月額度 |
| reusable workflow 算在呼叫端 | 各專案以 `uses:` 呼叫公版時，job 跑在呼叫端 repo，計入呼叫端擁有者的額度 |
| 額度以金額計 | 每月內含額度：Free／Free for organizations $12、Pro／Team $18、Enterprise Cloud $300 |
| 依 runner 單價扣抵 | Linux 2-core $0.006／分鐘、Windows 2-core $0.010／分鐘、macOS $0.062／分鐘。換算：Free 的 $12 約為 Linux 2,000 分鐘；Windows 單價約為 Linux 的 1.7 倍，macOS 約 10 倍 |
| 用完的處理 | 帳號沒有付款方式時，額度用完即停止執行；有付款方式時超出部分照價計費，可用 budget 設上限 |

### 實例

某私有專案（Python、Docker），2026-11 前 26 天：

| 項目 | 數值 |
|---|---|
| 執行的 job 數 | 367 |
| 實際執行時間加總 | 137 分鐘 |
| 每個 job 進位後加總（計費） | 406 分鐘 |
| 跑不到 1 分鐘的 job 比例 | 94% |

實際只跑 137 分鐘，計費是 406 分鐘。主因是 2.4.x 以前 Security Scan 每次 6～7 個 job、CI 每次 3～5 個 job，每個都只跑 10～30 秒。
2.5.0 把兩者各合併為一個 job（見下節）。

## 公版各 workflow 的 job 數（2.5.0 起）與觸發時機（2.6.0 起）

| Workflow | 觸發 | job 數 | 最低計費 |
|---|---|---|---|
| CI（`ci / CI Gate`） | 發往正式分支的 PR 每次推送（草稿除外） | 1；`dotnet-runner` 不是 `ubuntu-latest` 時多 1 個 .NET job | 1 分鐘（Windows .NET 另計） |
| Security Scan（`security / Security Gate`） | 發往正式分支的 PR 每次推送（草稿除外）、每週排程 | 1 | 1 分鐘 |
| Branch Guard | push 到受保護分支（含 PR 合併） | 1 | 1 分鐘 |
| Release Tag（選配） | push 到正式分支 | 1 | 1 分鐘 |

2.4.x 以前 CI 為「每項檢查 1 個 job＋Gate」、Security 為「每項掃描 1 個 job＋Gate」，每次 PR 推送最少 6～10 分鐘。
2.5.x 以前的範本對發往任何分支的 PR 都執行；2.6.0 起功能分支 → develop 的 PR 不執行（見 README「觸發條件」）。

## 估算方式

最低用量＝各 job 至少 1 分鐘。實際用量看專案內容：

- **docker build、image 掃描**通常各需 1～3 分鐘，有 Dockerfile 的專案兩個 Gate 多半超過 1 分鐘。
- **gitleaks 完整歷史掃描**（排程、push 事件）隨 git 歷史大小成長，約 190 MB 的 repo 需 4～5 分鐘；PR 只掃新增的 commit。
- **相依套件安裝**（`pip install`、`dotnet restore`）沒有快取時較慢。

| 情境 | 最低 |
|---|---|
| 發往正式分支的 PR 每次推送（CI Gate＋Security Gate） | 2 分鐘 |
| 發往正式分支的 PR 推送 1 次後合併（＋Branch Guard） | 3 分鐘 |
| 發往正式分支的 PR 推送 N 次後合併 | 2N＋1 分鐘 |
| 功能分支 → develop 合併（PR 不執行，合併後 Branch Guard） | 1 分鐘 |
| develop 流程發版一次（發版 PR 推送 1 次後合併） | 3 分鐘（另加 Release Tag 1 分鐘） |
| 每週排程重掃 | 每次 1 分鐘，約 5 分鐘／月 |

月用量粗估：`(發往正式分支的 PR 推送次數 × 2) + (合併次數 × 1) + 5`，有 Dockerfile 時推送次數改乘 4～6。
develop 流程下，功能 PR 只計合併時的 Branch Guard；發版 PR 開著時 develop 每次前進都會讓它重跑一次。
同一帳號底下的私有 repo 用量相加，與每月額度比較。

## 查看實際用量

- **網頁**：右上頭像 → Settings → Billing and licensing → Usage，可依 repo、runner 種類篩選。組織則在組織的 Settings。
- **單次執行**：Actions 分頁點進 run，每個 job 右側的時間即該 job 的執行時間，各自進位後加總即為計費分鐘。
- **整個 repo**：以 gh CLI 列出每個 job 的起訖時間後加總（私有 repo 需有讀取權限的帳號）：

```bash
REPO=owner/repo
gh api --paginate "repos/$REPO/actions/runs?per_page=100" -q '.workflow_runs[].id' |
while read -r id; do
  gh api --paginate "repos/$REPO/actions/runs/$id/jobs?filter=all&per_page=100" \
    -q '.jobs[] | select(.started_at != null and .completed_at != null and .conclusion != "skipped")
        | [.started_at, .completed_at] | @tsv'
done | python3 -c '
import sys, math, datetime as d
p = lambda s: d.datetime.fromisoformat(s.replace("Z", "+00:00"))
secs = [(p(b) - p(a)).total_seconds() for a, b in (l.split() for l in sys.stdin)]
print(f"jobs={len(secs)} 實際={sum(secs)/60:.0f} 分鐘 計費={sum(max(1, math.ceil(s/60)) for s in secs if s > 0)} 分鐘")'
```

## 減少用量

| 公版已採用 | 專案可自行調整 |
|---|---|
| CI、Security 各合併為一個 job（2.5.0） | 無 Dockerfile 時 `scan-docker-image: false` |
| 只在 PR 發往正式分支時執行（2.6.0） | 發版 PR 不要太早開：開著時 develop 每次前進都會重跑 |
| 草稿 PR 不執行 | 排程改為每月：`cron: "0 3 1 * *"` |
| 連續推送自動取消前一次執行 | 本機先跑 lint／測試再推送，減少 PR 推送次數 |
| 只在 PR 上執行，合併後不重跑 | `dotnet-runner` 非必要不使用 Windows |
| PR 的 gitleaks 只掃新增的 commit | 專案自己的 workflow 不要在 push 與 PR 重複執行同一組檢查 |
| Trivy 預設不掃 secret；Dependabot docker／actions 每月 | Billing 設 budget 上限，避免超支 |

新增公版檢查時，一律加成既有 Gate job 的步驟，不另開 job（見 [CONTRIBUTING](../CONTRIBUTING.md)）。
