#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROM_STACK_VERSION="${PROM_STACK_VERSION:-67.9.0}"
NAMESPACE="${NAMESPACE:-monitoring}"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
helm repo update prometheus-community

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --version "${PROM_STACK_VERSION}" \
  --namespace "${NAMESPACE}" --create-namespace \
  --values "${SCRIPT_DIR}/values-prometheus.yaml" \
  --wait --timeout 10m

echo "kube-prometheus-stack ${PROM_STACK_VERSION} installed in namespace ${NAMESPACE}."
echo "Grafana: kubectl port-forward -n ${NAMESPACE} svc/kube-prometheus-stack-grafana 3000:80"
echo "Default credentials: admin / prom-operator"
