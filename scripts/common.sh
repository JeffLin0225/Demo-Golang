#!/usr/bin/env bash
# 由 ci.sh / cd.sh / status.sh 共用的設定與工具函式。
# 這支不會被直接執行，只會被 source。

# 本機 build 的 image 純粹放在本機 docker image store，從沒 push 去任何地方
# （imagePullPolicy: Never），所以預設值刻意不用 ghcr.io 之類的 registry 字樣，
# 避免讓人誤以為這些 image 真的有被推上某個 registry。
# 真的要推去 GHCR 測試時，執行前覆蓋這個變數即可：
#   REGISTRY_PREFIX=ghcr.io/jefflin0225 ./scripts/ci.sh
REGISTRY_PREFIX="${REGISTRY_PREFIX:-local}"
SERVICE_IMAGE_NAME="${SERVICE_IMAGE_NAME:-sep-source}"
NAMESPACE="${NAMESPACE:-ns-demo-go-stg}"
DEPLOYMENT="${DEPLOYMENT:-sep-source}"
CONTAINER_NAME="${CONTAINER_NAME:-sep-source}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

BATCH_TARGETS=(
  "emailbatch:Batch/EmailBatch/Dockerfile"
  "linebatch:Batch/LineBatch/Dockerfile"
  "errorbatch:Batch/ErrorBatch/Dockerfile"
)

git_tag() {
  echo "git-$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
}

# cd.sh 沒收到明確 tag 參數時呼叫：直接問 Docker daemon 自己的 image
# metadata（建立時間），取回「本機建置過、最新的那一版」的 tag。
# 這是本機沒有真正 registry 時最接近的替代——真正環境裡 CD 會去 registry
# 查最新 push 的 tag，這裡 Docker 本機 image store 就是那個「registry」。
# 找不到任何已建置的 image 就印空字串，呼叫端自己判斷要不要擋下來。
latest_built_tag() {
  docker images "${SERVICE_IMAGE_NAME}" --format '{{.CreatedAt}}|{{.Tag}}' \
    | grep -v '<none>' \
    | sort -r \
    | head -n1 \
    | cut -d'|' -f2
}

# 把 BATCH_TARGETS 的 name 轉成對應環境變數名稱，例如
# emailbatch -> BATCH_IMAGE_EMAILBATCH，跟 service/main.go 讀取的 key 對齊。
batch_env_var() {
  echo "BATCH_IMAGE_$(echo "$1" | tr '[:lower:]' '[:upper:]')"
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
