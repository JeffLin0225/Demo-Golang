#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# CD：把指定版本部署到 Kubernetes
#
# 用法（一定要明確指定 tag，沒有「自動抓最新」的行為）：
#   ./scripts/cd.sh <tag>
#   例如： ./scripts/cd.sh git-0075eed
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
if [[ -z "$TAG" ]]; then
  echo "用法: $0 <tag>    例如: $0 git-0075eed" >&2
  echo "可用的 tag 請執行 ./scripts/status.sh 查看" >&2
  exit 1
fi

SERVICE_REF="${SERVICE_IMAGE_NAME}:${TAG}"

require_cluster

# Deployment 的 imagePullPolicy 是 Never，image 必須已存在於本機 image store，
# 否則 Pod 會卡在 ErrImageNeverPull。先擋下來，錯誤訊息比較好懂。
require_image "$SERVICE_REF"

# 三支 batch 這次部署全部帶上去，呼叫端用 batch_kind 參數選要跑哪一支，
# 不是在 CD 時就決定死了，所以三支的 image 都要先確認存在。
BATCH_ENV_ARGS=()
for target in "${BATCH_TARGETS[@]}"; do
  name="${target%%:*}"
  ref="${REGISTRY_PREFIX}/${name}:${TAG}"
  require_image "$ref"
  BATCH_ENV_ARGS+=("$(batch_env_var "$name")=${ref}")
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
