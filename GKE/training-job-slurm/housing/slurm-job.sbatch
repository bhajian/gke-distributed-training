#!/usr/bin/env bash
#SBATCH --job-name=housing-price-train
#SBATCH --partition=gpu
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=1
#SBATCH --gpus-per-task=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=00:30:00
#SBATCH --output=/tmp/housing-%j.out
#SBATCH --error=/tmp/housing-%j.err

set -euo pipefail

: "${HOUSING_IMAGE:=us-central1-docker.pkg.dev/YOUR_PROJECT_ID/gke-training/housing-price-train:latest}"

MASTER_ADDR=$(scontrol show hostnames "$SLURM_NODELIST" | head -n1)
MASTER_PORT=23456

export MASTER_ADDR MASTER_PORT
export WORLD_SIZE="$SLURM_NTASKS"

srun \
  --container-image="${HOUSING_IMAGE}" \
  bash -lc "torchrun --nnodes=${SLURM_NNODES} --nproc_per_node=1 --rdzv_backend=c10d --rdzv_endpoint=${MASTER_ADDR}:${MASTER_PORT} --rdzv_id=${SLURM_JOB_ID} /workspace/train.py"
