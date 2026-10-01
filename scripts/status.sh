#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# 比對「已建置的版本」與「叢集中實際運行的版本」
#
#   ./scripts/status.sh
#
# 跑完 ci.sh 之後執行這支，會看到新 image 已存在，
# 但運行中的版本沒有跟著變 —— 這就是 build 與 deploy 分離的證明。
# ============================================================

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
cd "$REPO_ROOT"

echo "===== 目前 HEAD ====="
echo "  $(git_tag)"
echo ""

echo "===== 已建置的 image（CI 產物）====="
docker images \
  --filter "reference=${REGISTRY_PREFIX}/*" \
  --filter "reference=${SERVICE_IMAGE_NAME}" \
  --format '{{.Repository}}:{{.Tag}}' | sort | sed 's/^/  /' || true
echo ""

echo "===== 叢集中運行的版本（CD 結果）====="
if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "  (連不到叢集，OrbStack 的 k8s 若未啟用請執行： orb start k8s)"
  exit 0
fi

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "  (Deployment 尚未建立，請先執行： kubectl apply -f k8s/)"
  exit 0
fi

echo "  Service image : $(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" \
  -o jsonpath='{.spec.template.spec.containers[0].image}')"
for target in "${BATCH_TARGETS[@]}"; do
  name="${target%%:*}"
  env_var="$(batch_env_var "$name")"
  printf '  %-20s: %s\n' "$env_var" "$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" \
    -o jsonpath="{.spec.template.spec.containers[0].env[?(@.name==\"${env_var}\")].value}")"
done
echo ""
kubectl get pods -n "$NAMESPACE" -l "app=${DEPLOYMENT}" | sed 's/^/  /'
