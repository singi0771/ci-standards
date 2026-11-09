# 公版自我測試用的 Dockerfile，不是要部署的 image。
# 本 repo 的 ci.yml / security.yml 用它跑 Docker build check（含 hadolint）與 Docker image (Trivy)，
# 改壞 reusable 裡的 Docker 路徑時，在本 repo 的 PR 上就會紅，不必等到 consumer 專案才發現。
#
# 刻意保持最小：
#   - FROM scratch：沒有 OS 套件，image 掃描不會因為上游新 CVE 讓每週排程重掃變紅
#   - COPY 的路徑相對 repo 根目錄：驗證 docker-context 預設值（"."）這條路徑
#     （2.2.1 以前的 DOCKER_CONTEXT 變數衝突就是壞在這裡）
#   - USER 非 root：避開 Trivy 設定檔掃描的 DS002（HIGH）
FROM scratch
COPY tests/docker/hello.txt /hello.txt
USER 65534
