#!/usr/bin/env bash
set -euo pipefail

SLINKY_VERSION="${SLINKY_VERSION:-1.0.0}"

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace --set crds.enabled=true

helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace prometheus --create-namespace --set installCRDs=true

helm install slurm-operator-crds oci://ghcr.io/slinkyproject/charts/slurm-operator-crds \
  --version "${SLINKY_VERSION}"

helm install slurm-operator oci://ghcr.io/slinkyproject/charts/slurm-operator \
  --version "${SLINKY_VERSION}" \
  --namespace slinky --create-namespace \
  --values k8s/slinky/values-operator.yaml

helm install slurm oci://ghcr.io/slinkyproject/charts/slurm \
  --version "${SLINKY_VERSION}" \
  --namespace slurm --create-namespace \
  --values k8s/slinky/values-slurm.yaml
