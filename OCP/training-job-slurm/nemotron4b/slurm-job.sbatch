#!/usr/bin/env bash
#SBATCH --job-name=nemotron4b-finetune
#SBATCH --partition=gpu
#SBATCH --nodes=2
#SBATCH --ntasks-per-node=1
#SBATCH --gpus-per-task=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=48G
#SBATCH --time=01:00:00
#SBATCH --output=/tmp/nemotron4b-%j.out
#SBATCH --error=/tmp/nemotron4b-%j.err

set -euo pipefail

: "${NEMOTRON_IMAGE:=quay.io/example-org/training/nemotron4b-finetune:latest}"

MASTER_ADDR=$(scontrol show hostnames "$SLURM_NODELIST" | head -n1)
MASTER_PORT=23456

export MASTER_ADDR MASTER_PORT
export WORLD_SIZE="$SLURM_NTASKS"

srun \
  --container-image="${NEMOTRON_IMAGE}" \
  bash -lc "torchrun --nnodes=${SLURM_NNODES} --nproc_per_node=1 --rdzv_backend=c10d --rdzv_endpoint=${MASTER_ADDR}:${MASTER_PORT} --rdzv_id=${SLURM_JOB_ID} /workspace/train.py"
