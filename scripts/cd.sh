#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# CD：把指定版本部署到 Kubernetes
#
#   ./scripts/cd.sh git-0075eed
#
# 一定要明確指定 tag，不提供「自動抓最新」的行為。
# 那正是要避免的：build 完就自動生效。
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
BATCH_REF="${REGISTRY_PREFIX}/${BATCH_KIND}:${TAG}"

require_cluster

# Deployment 的 imagePullPolicy 是 Never，image 必須已存在於本機 image store，
# 否則 Pod 會卡在 ErrImageNeverPull。先擋下來，錯誤訊息比較好懂。
require_image "$SERVICE_REF"
require_image "$BATCH_REF"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "[ERROR] 找不到 Deployment ${DEPLOYMENT} (namespace: ${NAMESPACE})" >&2
  echo "        第一次部署請先執行： kubectl apply -f k8s/" >&2
  exit 1
fi

echo "===== CD: 部署 ${TAG} ====="
echo "  Service image : ${SERVICE_REF}"
echo "  BATCH_IMAGE   : ${BATCH_REF}"
echo ""

# 改 .spec.template 就會自動觸發 rolling update，不需要額外下重啟指令。
# 這裡分兩次下指令，所以會產生兩次 rollout；replicas=1 的展示環境無所謂，
# 要一次到位可以改用單一 kubectl patch 同時改 image 與 env。
kubectl set image "deployment/${DEPLOYMENT}" \
  "${CONTAINER_NAME}=${SERVICE_REF}" -n "$NAMESPACE"

kubectl set env "deployment/${DEPLOYMENT}" \
  "BATCH_IMAGE=${BATCH_REF}" -n "$NAMESPACE"

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
