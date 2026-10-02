#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# CI：只建置 image，不部署任何東西
#
# 用法（不接受任何參數，tag 一律由 git HEAD 推導）：
#   ./scripts/ci.sh
#
# 每次執行會把下面 4 支 image 全部一起 build，沒有「只建一支」的選項：
#   - service（你的 API，對應 service/Dockerfile）
#   - emailbatch / linebatch / errorbatch（三支都建，見 Batch/ 底下對應目錄）
#
# 可用環境變數覆蓋預設值（定義在 common.sh）：
#   REGISTRY_PREFIX=local          batch image 的前綴，預設 local（純本機 tag，沒有 push 去任何 registry）
#   SERVICE_IMAGE_NAME=sep-source   service image 的名稱（本機 tag，不經 registry）
#
# 跑完之後叢集裡執行中的版本完全不變。
# 要讓新版生效必須另外執行 ./scripts/cd.sh <tag>，這是刻意的。
# ============================================================

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$REPO_ROOT"

# tag 一律由 git HEAD 推導，不接受外部指定。
# 允許手動指定 tag 等於允許同一個 tag 對到不同內容，immutable 的保證就沒了。
if [[ $# -gt 0 ]]; then
  echo "[ERROR] ci.sh 不接受參數，tag 一律由 git HEAD 決定" >&2
  exit 1
fi

TAG="$(git_tag)"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "[WARN] 工作目錄有未提交的變更"
  echo "[WARN] 建出來的 image 內容與 ${TAG} 不會一致，本機測試請自行斟酌"
  echo "[WARN] 正式 CI 是在乾淨的 checkout 上執行，不會有這個問題"
  echo ""
fi

echo "===== CI: 建置 ${TAG} ====="
echo ""

for target in "${BATCH_TARGETS[@]}"; do
  name="${target%%:*}"
  dockerfile="${target#*:}"
  echo "--- building ${name} ---"
  docker build -q -f "$dockerfile" -t "${REGISTRY_PREFIX}/${name}:${TAG}" .
done

echo "--- building ${SERVICE_IMAGE_NAME} ---"
docker build -q -f service/Dockerfile -t "${SERVICE_IMAGE_NAME}:${TAG}" .

echo ""
echo "===== CI 完成 ====="
for target in "${BATCH_TARGETS[@]}"; do
  echo "  ${REGISTRY_PREFIX}/${target%%:*}:${TAG}"
done
echo "  ${SERVICE_IMAGE_NAME}:${TAG}"
echo ""
echo "叢集中執行的版本不受影響，仍是舊版。"
echo "這是目前本機建置時間最新的版本，cd.sh 不帶參數執行時會自動部署這一版"
echo "（即使 build 跟 deploy 分開時間/隔天執行也一樣，不需要手動複製貼上 tag）。"
echo "要讓這一版生效： ./scripts/cd.sh            （不帶參數＝部署本機最新建置的版本）"
echo "要改部署別的版本： ./scripts/cd.sh <tag>     （例如要刻意跑舊版本做新舊比較）"
