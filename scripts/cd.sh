#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# CD：把指定版本部署到 Kubernetes
#
# 用法：
#   ./scripts/cd.sh            → 不帶參數，部署「CI 產出紀錄裡寫的那一版」
#                                 （讀 .ci-build-state，見 common.sh）。
#                                 CD 不會自己猜版本：不查 docker image 的
#                                 CreatedAt、不排序 tag、不推導 image 名稱，
#                                 ci.sh 寫什麼就部署什麼。build 跟 deploy
#                                 可以分開時間、由不同 pipeline 觸發，deploy
#                                 端不需要人工把 build 端算出的 SHA 貼一次。
#   ./scripts/cd.sh <tag>      → 明確指定要部署的版本，略過 CI 產出紀錄，
#                                 用於刻意部署非最新版本（例如要跑舊版本的
#                                 batch 去跟新版本結果比較）
#
# 為什麼不是去查「最新建置的 image」：曾經踩過的坑 —— Docker build cache 會
# 沿用內容相同的舊 layer（連 CreatedAt 都繼承），多個 tag 時間戳一模一樣，
# 排序就退化成比較 tag 字串字母順序，選到的是 git-b00ef34 而不是真正的 HEAD。
# 「哪一版該上線」必須是被明確寫下來的事實，不能靠事後檢查旁路 metadata 推論。
#
# 可用的 tag 請先執行 ./scripts/status.sh 查看（必須是 ci.sh 已經建過的 tag）。
#
# 每次執行會把下面全部一起部署到同一個 Deployment（sep-source），
# 沒有「只部署 service」或「只換某一支 batch」的選項：
#   - service → 換掉 Deployment 的 container image
#   - emailbatch / linebatch / errorbatch → 三支的 image ref 都寫進對應的
#     BATCH_IMAGE_* 環境變數，呼叫端之後用 /api/callsep 的 batch_kind 參數選
#
# 可用環境變數覆蓋預設值（定義在 common.sh）：
#   NAMESPACE / DEPLOYMENT / CONTAINER_NAME   目標 k8s 資源（預設 ns-demo-go-stg / sep-source）
#
# batch_kind 沒有預設值這件事：呼叫端打 /api/callsep 一定要自己帶 batch_kind，
# 不帶就是 400，Service 不會幫忙猜要跑哪一支，所以這裡也沒有「預設批次」可以設定。
#
# 第一次部署前要先 kubectl apply -f k8s/ 建好 Deployment，這支只會「更新」既有的。
# ============================================================

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$REPO_ROOT"

TAG="${1:-}"
BATCH_ENV_ARGS=()

if [[ -z "$TAG" ]]; then
  # 不帶參數：完全依據 CI 寫下的產出紀錄，連 image 全名都照抄，
  # 不查 docker metadata、不自己從 tag 推導 —— CI 寫什麼就部署什麼。
  require_build_state

  TAG="$(read_build_state BUILD_TAG)"
  SERVICE_REF="$(read_build_state SERVICE_IMAGE)"
  if [[ -z "$TAG" || -z "$SERVICE_REF" ]]; then
    echo "[ERROR] CI 產出紀錄格式不完整: ${BUILD_STATE_FILE}" >&2
    echo "        請重新執行 ./scripts/ci.sh 產生，或明確指定版本： $0 <tag>" >&2
    exit 1
  fi

  while IFS= read -r env_line; do
    [[ -n "$env_line" ]] && BATCH_ENV_ARGS+=("$env_line")
  done < <(read_build_state_batch_env)

  echo "[INFO] 未指定 tag，依據 CI 產出紀錄部署： ${TAG}"
  echo "       紀錄來源: ${BUILD_STATE_FILE}"
  echo "       建置時間: $(read_build_state BUILD_TIME || echo '(未記錄)')"
  echo "       對應 commit: $(read_build_state BUILD_COMMIT || echo '(未記錄)')"
  echo ""
else
  # 明確指定 tag：刻意部署非最新版（例如新舊比較），沒有對應的 CI 紀錄可讀，
  # 只能從 tag 推導 image 名稱 —— 所以這條路徑要自己確保 REGISTRY_PREFIX
  # 與當初建置時一致。
  SERVICE_REF="${SERVICE_IMAGE_NAME}:${TAG}"
  for target in "${BATCH_TARGETS[@]}"; do
    name="${target%%:*}"
    BATCH_ENV_ARGS+=("$(batch_env_var "$name")=${REGISTRY_PREFIX}/${name}:${TAG}")
  done

  echo "[INFO] 手動指定版本： ${TAG}（略過 CI 產出紀錄）"
  echo ""
fi

require_cluster

# Deployment 的 imagePullPolicy 是 Never，image 必須已存在於本機 image store，
# 否則 Pod 會卡在 ErrImageNeverPull。先擋下來，錯誤訊息比較好懂。
require_image "$SERVICE_REF"

# 三支 batch 這次部署全部帶上去，呼叫端用 batch_kind 參數選要跑哪一支，
# 不是在 CD 時就決定死了，所以三支的 image 都要先確認存在。
for env_arg in "${BATCH_ENV_ARGS[@]}"; do
  require_image "${env_arg#*=}"
done

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "[ERROR] 找不到 Deployment ${DEPLOYMENT} (namespace: ${NAMESPACE})" >&2
  echo "        第一次部署請先執行： kubectl apply -f k8s/" >&2
  exit 1
fi

echo "===== CD: 部署 ${TAG} ====="
echo "  Service image    : ${SERVICE_REF}"
for env_arg in "${BATCH_ENV_ARGS[@]}"; do
  echo "  ${env_arg}"
done
echo ""

# 改 .spec.template 就會自動觸發 rolling update，不需要額外下重啟指令。
# 這裡分兩次下指令，所以會產生兩次 rollout；replicas=1 的展示環境無所謂，
# 要一次到位可以改用單一 kubectl patch 同時改 image 與 env。
kubectl set image "deployment/${DEPLOYMENT}" \
  "${CONTAINER_NAME}=${SERVICE_REF}" -n "$NAMESPACE"

kubectl set env "deployment/${DEPLOYMENT}" \
  "${BATCH_ENV_ARGS[@]}" -n "$NAMESPACE"

echo ""
echo "--- 等待 rollout 完成 ---"
if ! kubectl rollout status "deployment/${DEPLOYMENT}" -n "$NAMESPACE" --timeout=120s; then
  echo ""
  echo "[ERROR] rollout 失敗，Pod 現況：" >&2
  kubectl get pods -n "$NAMESPACE" -l "app=${DEPLOYMENT}" >&2
  exit 1
fi

echo ""
echo "===== CD 完成 ====="
echo "查看結果： ./scripts/status.sh"
echo "本機測試： kubectl port-forward svc/sep-source-svc 18080:8080 -n ${NAMESPACE}"
