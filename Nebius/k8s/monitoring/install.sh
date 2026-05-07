#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROM_STACK_VERSION="${PROM_STACK_VERSION:-67.9.0}"
LOKI_VERSION="${LOKI_VERSION:-6.30.0}"
PROMTAIL_VERSION="${PROMTAIL_VERSION:-6.16.6}"
NAMESPACE="${NAMESPACE:-monitoring}"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
helm repo add grafana https://grafana.github.io/helm-charts || true
helm repo update prometheus-community grafana

# 1. Prometheus + Grafana
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --version "${PROM_STACK_VERSION}" \
  --namespace "${NAMESPACE}" --create-namespace \
  --values "${SCRIPT_DIR}/values-prometheus.yaml" \
  --wait --timeout 10m

echo "kube-prometheus-stack ${PROM_STACK_VERSION} installed."

# 2. Pushgateway (for training metrics)
kubectl apply -f "${SCRIPT_DIR}/pushgateway.yaml"
echo "Prometheus Pushgateway installed."

# 3. Loki (log aggregation)
helm upgrade --install loki grafana/loki \
  --version "${LOKI_VERSION}" \
  --namespace "${NAMESPACE}" \
  --values "${SCRIPT_DIR}/values-loki.yaml" \
  --wait --timeout 10m

echo "Loki ${LOKI_VERSION} installed."

# 4. Promtail (log collector)
helm upgrade --install promtail grafana/promtail \
  --version "${PROMTAIL_VERSION}" \
  --namespace "${NAMESPACE}" \
  --values "${SCRIPT_DIR}/values-promtail.yaml" \
  --wait --timeout 5m

echo "Promtail ${PROMTAIL_VERSION} installed."

# 5. Dashboards
kubectl apply -f "${SCRIPT_DIR}/dashboards/"

echo ""
echo "=== Monitoring Stack Installed ==="
echo "Grafana:     kubectl port-forward -n ${NAMESPACE} svc/kube-prometheus-stack-grafana 3000:80"
echo "Credentials: admin / prom-operator"
echo ""
echo "Dashboards:"
echo "  - NVIDIA DCGM GPU Metrics   (GPU utilization, memory, temp, power)"
echo "  - Training Metrics           (loss curves, throughput, GPU memory)"
echo "  - Explore > Loki             (real-time training log streaming)"
