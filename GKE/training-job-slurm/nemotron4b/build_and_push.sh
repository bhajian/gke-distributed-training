#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-}"
REGION="${REGION:-us-central1}"
REGISTRY="${REGISTRY:-${REGION}-docker.pkg.dev}"
REPO="${REPO:-gke-training}"
IMAGE_NAME="nemotron4b-finetune"
PLATFORM="${PLATFORM:-linux/amd64}"
CLOUD_BUILD="${CLOUD_BUILD:-0}"
CLOUD_BUILD_MACHINE_TYPE="${CLOUD_BUILD_MACHINE_TYPE:-e2-highmem-8}"

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

if [[ "$CLOUD_BUILD" == "1" ]]; then
  gcloud builds submit \
    --tag "$IMAGE" \
    --machine-type "$CLOUD_BUILD_MACHINE_TYPE" \
    --project "$PROJECT_ID"
else
  docker buildx build --platform "$PLATFORM" -t "$IMAGE" --push .
fi

echo "Pushed: $IMAGE"
