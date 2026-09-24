# 把 ci-standards 搬到組織底下

目前本 repo 在個人帳號 `singi0771` 下。搬到組織是**遲早要做、而且越晚做越痛**的事：
每多一個專案指向 `singi0771/ci-standards`，搬家時要協調的 repo 就多一個。

> **建議在導入第 3 個專案之前搬完。**

---

## 為什麼要搬（不只是「比較正式」）

| 好處 | 說明 |
|---|---|
| private repo 能開分支保護 | ruleset 在**免費個人帳號的 private repo 上直接被 403 擋掉**。Team 方案的 org 沒這個限制，這通常是搬家的直接動機 |
| Billing 統一 | Actions 分鐘集中看、集中設 spending limit |
| 權限與交接 | 公版不再綁在某一個人的帳號上。個人帳號離職／換手就是災難 |
| 可以用 org ruleset | 一次對「組織內所有 repo」要求 `Security Gate`，不必逐 repo 跑腳本 |

---

## 搬家前的準備（在還是個人 repo 時就先做）

- [ ] **把 `v1` 對到最新的 main**，並打好不可變的 `v1.x.y`（見 [版本策略](../README.md#版本策略)）
      —— 搬家過程中最不想處理的就是「版本本來就不對」
- [ ] 盤點**目前有哪些 repo 指向 `singi0771/ci-standards`**。搬完之後這些全部要改 `uses:`
- [ ] 確認目標 org 的方案（Team 以上才有 private repo 的 ruleset）
- [ ] 確認你在目標 org 有建立 repo / transfer repo 的權限

---

## 搬家步驟

### 1. Transfer repository

Settings → General → 最底下 Danger Zone → **Transfer ownership** → 填目標 org。

會**保留**：commit 歷史、所有 branch、**所有 tag（含 `v1`）**、Issues、PR、rulesets、repo secrets、Actions 設定。

會**變的**：`owner/repo` 路徑。GitHub 會建立 web / git 的 redirect，
但 **`uses:` 不要依賴 redirect** —— 版本解析牽涉到 tag 查找，行為不保證，
而且留著舊路徑會讓人搞不清楚公版到底在哪。**一律明確改掉。**

### 2. 改掉 repo 內所有寫死的 `owner/repo`

搬家當下這些全部要換（`ORG` 換成你的組織名）：

```bash
# 範本呼叫端
templates/consumer-repo/.github/workflows/ci.yml                      # 註解 + uses:
templates/consumer-repo/.github/workflows/security.yml                # 註解 + uses:
templates/consumer-repo/.github/zizmor.yml        # unpinned-uses 的放行規則
.github/zizmor.yml                                # 本 repo 自己的那份

# 導入腳本裡的預設值
scripts/adopt.sh                                  # STD_REPO_URL、DEFAULT_USES_REPO
scripts/adopt.ps1                                 # $StdRepoUrl、-UsesRepo 預設值、zizmor.yml 的替換字串

# 文件裡的範例
README.md                     # 導入步驟與範例中的 uses:
scripts/setup-branch-protection.sh   # 用法範例
```

一次性替換：

```bash
grep -rl 'singi0771/ci-standards' . --exclude-dir=.git \
  | xargs sed -i 's|singi0771/ci-standards|ORG/ci-standards|g'
```

改完**一定要跑 actionlint 與 zizmor 驗一次**（本 repo 的 CI 會連 `templates/` 一起檢查）：

```bash
actionlint -color
actionlint -color 'templates/consumer-repo/.github/workflows/*.yml'
zizmor .
bash scripts/test-adopt.sh
```

### 3. 換掉個人帳號的痕跡

- [ ] `.github/CODEOWNERS`：`@singi0771` → `@ORG/platform-team`（改成 team，不要綁個人）
- [ ] `LICENSE`：copyright holder 換成組織名
- [ ] `SECURITY.md`：回報管道換成組織的
- [ ] `scripts/setup-branch-protection.sh` 的用法範例

### 4. 可見性與存取權

- **維持 public** → 任何 repo 都能 `uses:` 呼叫，不必設定，而且 public repo 的 Actions 不計費
- **改成 private** → 必須另外開放：
  Settings → Actions → General → **Access** → `Accessible from repositories in the organization`
  沒開的話所有 consumer 會收到 `workflow was not found`

### 5. 組織層級設定（原本散在個人帳號的，現在集中）

- [ ] Org → Settings → Billing → **Spending limit**，Actions 設 **$0**
- [ ] Org → Settings → Actions → General → 確認 workflow 核准政策
- [ ] **把 required approvals 從 0 改成 1**。個人 repo 只有一個人時設 0 是不得已；
      組織裡公版一改就影響所有專案，**必須要有第二個人看過**。搭配 CODEOWNERS：

```bash
REQUIRED_APPROVALS=1 ./scripts/setup-branch-protection.sh ORG/ci-standards
```

### 6. 通知並切換所有 consumer

搬完之後，每一個 consumer repo 都要開一個小 PR：

```diff
-    uses: singi0771/ci-standards/.github/workflows/ci-reusable.yml@v1
+    uses: ORG/ci-standards/.github/workflows/ci-reusable.yml@v1
```

（`security.yml` 同理；`.github/zizmor.yml` 裡的放行規則也要換 owner，
不然 zizmor 會開始抱怨 `@v1` 沒釘 SHA。）
最省事的做法是用導入腳本一次換完：`adopt.sh --uses-repo ORG/ci-standards`。

> **順序很重要**：先確認新路徑的 `@v1` 真的解析得到（拿一個 repo 試一次），再通知其他人改。
> 全部改完之前**不要**刪掉或改名舊 repo。

### 7. 最後驗證

- [ ] 隨便挑一個 consumer 開 PR，確認 `ci / CI Gate`、`security / Security Gate` 兩個 check 有出現且會過
- [ ] 確認 ruleset 的 required check 名稱沒變（job id 沒動就不會變）
- [ ] 本 repo 自己的 CI / Security 仍然綠（它用 `./` 呼叫，不受路徑影響）
- [ ] 在 [CHANGELOG](../CHANGELOG.md) 記一筆搬遷

---

## 之後推廣到其他專案時

搬到 org 之後可以用**組織層級 ruleset**，不必每個 repo 各跑一次腳本：

Org → Settings → Rules → Rulesets → New branch ruleset，
target 選「所有 repo」或用名稱 pattern，required checks 一樣只填
`security / Security Gate` 與 `ci / CI Gate`。

> 開組織層級 ruleset **之前**，先確認每個目標 repo 都已經導入公版並跑過至少一次。
> 對還沒導入的 repo 強制 required check，那些 check 永遠不會出現 → 全組織的 PR 一起卡死。
> 這跟 [README 的 skipped check 死鎖](../README.md#分支保護讓流程非過不可)是同一類問題，只是規模放大。
