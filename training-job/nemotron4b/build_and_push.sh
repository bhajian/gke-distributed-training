#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-openenv-8t66t}"
IMAGE="gcr.io/${PROJECT_ID}/nemotron4b-finetune:latest"

# Authenticate docker to GCR
(gcloud auth configure-docker -q) >/dev/null 2>&1 || gcloud auth configure-docker

docker build -t "$IMAGE" .
docker push "$IMAGE"

echo "Pushed: $IMAGE"
