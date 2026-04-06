#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-openenv-8t66t}"
IMAGE="gcr.io/${PROJECT_ID}/nemotron4b-finetune:latest"
PLATFORM="${PLATFORM:-linux/amd64}"

# Authenticate docker to GCR
(gcloud auth configure-docker -q) >/dev/null 2>&1 || gcloud auth configure-docker

docker buildx build --platform "$PLATFORM" -t "$IMAGE" --push .

echo "Pushed: $IMAGE"
