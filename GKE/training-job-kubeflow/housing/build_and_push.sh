#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-us-central1}"
REGISTRY="${REGISTRY:-${REGION}-docker.pkg.dev}"
REPO="${REPO:-gke-training}"
IMAGE_NAME="housing-price-train"
PLATFORM="${PLATFORM:-linux/amd64}"

if [[ -z "$PROJECT_ID" ]]; then
  echo "PROJECT_ID is not set. Example: export PROJECT_ID=YOUR_PROJECT_ID" >&2
  exit 1
fi

if [[ "$REGISTRY" == *"gcr.io" ]]; then
  IMAGE="${REGISTRY}/${PROJECT_ID}/${IMAGE_NAME}:latest"
else
  IMAGE="${REGISTRY}/${PROJECT_ID}/${REPO}/${IMAGE_NAME}:latest"
fi

# Authenticate docker to registry
gcloud auth configure-docker "$REGISTRY" --quiet

docker buildx build --platform "$PLATFORM" -t "$IMAGE" --push .

echo "Pushed: $IMAGE"
