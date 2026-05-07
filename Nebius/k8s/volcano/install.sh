#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VOLCANO_VERSION="${VOLCANO_VERSION:-1.11.0}"
NAMESPACE="${NAMESPACE:-volcano-system}"

helm repo add volcano-sh https://volcano-sh.github.io/helm-charts || true
helm repo update volcano-sh

helm upgrade --install volcano volcano-sh/volcano \
  --version "${VOLCANO_VERSION}" \
  --namespace "${NAMESPACE}" --create-namespace \
  --values "${SCRIPT_DIR}/values.yaml" \
  --wait --timeout 5m

echo "Volcano ${VOLCANO_VERSION} installed in namespace ${NAMESPACE}."
echo "Verify:  kubectl get pods -n ${NAMESPACE}"
echo "CRDs:    kubectl get crd | grep volcano"

kubectl apply -f "${SCRIPT_DIR}/default-queue.yaml"
echo "Default Volcano queues applied."
