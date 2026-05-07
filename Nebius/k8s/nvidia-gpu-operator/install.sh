#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GPU_OPERATOR_VERSION="${GPU_OPERATOR_VERSION:-v25.3.0}"
NAMESPACE="${NAMESPACE:-nvidia-gpu-operator}"

helm repo add nvidia https://helm.ngc.nvidia.com/nvidia || true
helm repo update nvidia

helm upgrade --install gpu-operator nvidia/gpu-operator \
  --version "${GPU_OPERATOR_VERSION}" \
  --namespace "${NAMESPACE}" --create-namespace \
  --values "${SCRIPT_DIR}/values.yaml" \
  --wait --timeout 15m

echo "NVIDIA GPU Operator ${GPU_OPERATOR_VERSION} installed in namespace ${NAMESPACE}."
echo "Verify:  kubectl get pods -n ${NAMESPACE}"
echo "Test:    kubectl apply -f $(dirname "${SCRIPT_DIR}")/nvidia/gpu-test.yaml"
