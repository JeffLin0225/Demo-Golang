#!/usr/bin/env bash
# 由 ci.sh / cd.sh / status.sh 共用的設定與工具函式。
# 這支不會被直接執行，只會被 source。

REGISTRY_PREFIX="${REGISTRY_PREFIX:-ghcr.io/jefflin0225}"
SERVICE_IMAGE_NAME="${SERVICE_IMAGE_NAME:-sep-source}"
NAMESPACE="${NAMESPACE:-ns-demo-go-stg}"
DEPLOYMENT="${DEPLOYMENT:-sep-source}"
CONTAINER_NAME="${CONTAINER_NAME:-sep-source}"
# Service 的 BATCH_IMAGE 要指向哪一支 batch（emailbatch / linebatch / errorbatch）
BATCH_KIND="${BATCH_KIND:-emailbatch}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BATCH_TARGETS=(
  "emailbatch:Batch/EmailBatch/Dockerfile"
  "linebatch:Batch/LineBatch/Dockerfile"
  "errorbatch:Batch/ErrorBatch/Dockerfile"
)

git_tag() {
  echo "git-$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
}

require_image() {
  local ref="$1"
  if ! docker image inspect "$ref" >/dev/null 2>&1; then
    echo "[ERROR] 找不到 image: ${ref}" >&2
    echo "        請先執行 ./scripts/ci.sh 建置，或確認 tag 是否正確" >&2
    exit 1
  fi
}

require_cluster() {
  if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "[ERROR] 連不到 Kubernetes 叢集" >&2
    echo "        OrbStack 的 k8s 若未啟用，執行： orb start k8s" >&2
    exit 1
  fi
}
