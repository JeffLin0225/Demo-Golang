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

# cd.sh 沒收到明確 tag 參數時呼叫：取回「本機建置過、最新的那一版」的 tag。
#
# 「最新」錨定在 git commit 歷史，不是 Docker image metadata：
# 從 HEAD 開始依序往回找每個 commit 的 short SHA，回傳第一個本機已經建好
# image 的那個 —— 跟真正 CI/CD 判斷新舊的方式一致（真實環境是 CI 直接把
# commit SHA 傳給 CD，或透過 GitOps commit 驅動；這裡本機沒有真正的
# pipeline 串接，退而求其次用 git log 的祖先順序模擬同一件事）。
#
# 刻意不用 docker images 的 CreatedAt 排序：Docker build cache 只要某層
# 內容沒變就會沿用舊 layer（連 timestamp 都沿用），曾經出現多個 tag
# CreatedAt 完全相同、退而比較 tag 字串字母順序選錯版本的情況。
#
# 找不到任何已建置的 image 就印空字串，呼叫端自己判斷要不要擋下來。
latest_built_tag() {
  local sha candidate
  while read -r sha; do
    candidate="git-${sha}"
    if docker image inspect "${SERVICE_IMAGE_NAME}:${candidate}" >/dev/null 2>&1; then
      echo "$candidate"
      return 0
    fi
  done < <(git -C "$REPO_ROOT" log --format='%h')
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
