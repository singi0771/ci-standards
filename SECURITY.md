# Security Policy

## 回報安全弱點

**請勿開公開 Issue 回報安全弱點。**

若你在本 repo 的公版 workflow 或相關腳本中發現安全問題，請透過
[GitHub Security Advisories](https://github.com/singi0771/ci-standards/security/advisories/new)
以私下方式回報。

這可以讓維護者在公開披露前先評估影響範圍、準備修補版本，保護所有使用公版的下游專案。

## 支援範圍

| 版本 | 支援狀態 |
|---|---|
| `@v1`（最新） | ✅ 支援中 |
| 舊 tag | ❌ 不再支援，請升級 |

## 揭露流程

1. 透過 Security Advisories 私下通報
2. 維護者確認後在 7 天內回應
3. 修補完成後發佈 patch，移動 `v1` tag
4. 公開 Advisory 並通知下游

## 注意

- 本 repo 沒有應用程式碼；弱點通常發生在 workflow 邏輯（shell injection、供應鏈、權限過寬）
- 若弱點屬於 **你自己的消費端 repo**（非公版本身），請在你自己的 repo 處理
