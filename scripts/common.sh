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

# ============================================================
# CI 產出紀錄（build metadata）
#
# ci.sh 建置成功後，把「這次建出了什麼」明確寫進這個檔案；cd.sh 不帶參數時
# 唯一的依據就是它 —— 不查 docker image metadata、也不自己從 tag 推導 image
# 名稱，CI 寫什麼就部署什麼。
#
# 這是 CI 與 CD 拆成兩條獨立 pipeline 後唯一的交接通道，必須守住兩筆紀錄的
# 分工（搞混就會出現「CD 還沒跑，批次卻已經跑到沒驗證過的新版」）：
#   - CI 產出紀錄（這個檔案）＝「什麼被建出來了」，只有 cd.sh 會讀
#   - CD 版本閘門（Deployment 的 env）＝「線上實際跑哪一版」，runtime 只讀這個
#
# 刻意放在叢集外（純本機檔案）而不是寫成 ConfigMap，有兩個理由：
#   1. CI 階段不該持有叢集憑證。寫 ConfigMap 等於 build 階段就握有部署權限，
#      這是真實環境刻意守住的權限邊界（CI 只給 registry push 權限，
#      叢集憑證只給 CD）。
#   2. 放在叢集裡的紀錄遲早會有人掛進 runtime。一旦 runtime 讀得到 CI 寫的
#      紀錄，CI 就等於 CD，上面那條分工就破了。
#
# 真實環境對應物：Jenkins 的 archiveArtifacts / Azure DevOps 的 pipeline
# artifact —— CI stage 上傳、CD stage 下載的那包 build metadata。
# ============================================================
BUILD_STATE_FILE="${BUILD_STATE_FILE:-${REPO_ROOT}/.ci-build-state}"

# ci.sh 建置成功後呼叫：寫下這次的 tag 與「完整 image refs」。
#
# 連 image 全名都寫進紀錄（而不是只寫 tag、讓 cd.sh 自己拼）是刻意的：
# REGISTRY_PREFIX 可以被環境變數覆蓋，CI 用 ghcr.io/... 建置、CD 執行時沒帶
# 同一個變數的話就會拼出不存在的 local/...。把實際產出寫死才不會對不上。
write_build_state() {
  local tag="$1"
  local target name
  {
    echo "# 由 scripts/ci.sh 自動產生，請勿手改，也不要 commit。"
    echo "# 語意是「CI 建出了什麼」，不是「線上正在跑什麼」。"
    echo "# 線上跑什麼的版本閘門是 Deployment 的 env（只有 cd.sh 會寫），"
    echo "# runtime 永遠不讀這份檔案 —— 否則 CI 就等於 CD。"
    echo "BUILD_TAG=${tag}"
    echo "BUILD_COMMIT=$(git -C "$REPO_ROOT" rev-parse HEAD)"
    echo "BUILD_TIME=$(date -Iseconds)"
    echo "SERVICE_IMAGE=${SERVICE_IMAGE_NAME}:${tag}"
    for target in "${BATCH_TARGETS[@]}"; do
      name="${target%%:*}"
      echo "$(batch_env_var "$name")=${REGISTRY_PREFIX}/${name}:${tag}"
    done
  } > "$BUILD_STATE_FILE"
}

# 讀 CI 產出紀錄的單一欄位，檔案或欄位不存在就回傳非 0。
read_build_state() {
  local key="$1" value
  [[ -f "$BUILD_STATE_FILE" ]] || return 1
  value="$(grep -E "^${key}=" "$BUILD_STATE_FILE" | tail -n1 | cut -d'=' -f2-)"
  [[ -n "$value" ]] || return 1
  echo "$value"
}

# 讀出紀錄裡所有 BATCH_IMAGE_* 欄位，維持 KEY=value 整行格式，
# 可以直接餵給 kubectl set env。
read_build_state_batch_env() {
  [[ -f "$BUILD_STATE_FILE" ]] || return 1
  grep -E '^BATCH_IMAGE_[A-Z]+=' "$BUILD_STATE_FILE"
}

require_build_state() {
  if [[ -f "$BUILD_STATE_FILE" ]]; then
    return 0
  fi
  echo "[ERROR] 找不到 CI 產出紀錄: ${BUILD_STATE_FILE}" >&2
  echo "        cd.sh 不帶參數時只依據 CI 寫下的紀錄部署，不會自己猜版本。" >&2
  echo "        請先執行 ./scripts/ci.sh，或明確指定版本： ./scripts/cd.sh <tag>" >&2
  exit 1
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
