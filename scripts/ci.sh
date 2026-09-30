#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# CI：只建置 image，不部署任何東西
#
#   ./scripts/ci.sh
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
docker build -q -f Service/Dockerfile -t "${SERVICE_IMAGE_NAME}:${TAG}" .

echo ""
echo "===== CI 完成 ====="
for target in "${BATCH_TARGETS[@]}"; do
  echo "  ${REGISTRY_PREFIX}/${target%%:*}:${TAG}"
done
echo "  ${SERVICE_IMAGE_NAME}:${TAG}"
echo ""
echo "叢集中執行的版本不受影響，仍是舊版。"
echo "要讓這一版生效： ./scripts/cd.sh ${TAG}"
