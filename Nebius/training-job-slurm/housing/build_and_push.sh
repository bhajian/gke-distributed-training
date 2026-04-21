#!/usr/bin/env bash
set -euo pipefail

IMAGE_REGISTRY="${IMAGE_REGISTRY:-}"
IMAGE_REPO="${IMAGE_REPO:-}"
IMAGE_NAME="housing-price-train"
PLATFORM="${PLATFORM:-linux/amd64}"

if [[ -z "$IMAGE_REGISTRY" || -z "$IMAGE_REPO" ]]; then
  echo "IMAGE_REGISTRY and IMAGE_REPO must be set. Example: export IMAGE_REGISTRY=quay.io; export IMAGE_REPO=my-org/training" >&2
  exit 1
fi

IMAGE="${IMAGE_REGISTRY}/${IMAGE_REPO}/${IMAGE_NAME}:latest"

docker buildx build --platform "$PLATFORM" -t "$IMAGE" --push .

echo "Pushed: $IMAGE"
