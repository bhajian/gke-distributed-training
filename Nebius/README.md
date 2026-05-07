# Nebius Distributed Training on Managed Kubernetes

Provision a GPU-enabled Kubernetes cluster on Nebius Cloud and run distributed PyTorch training jobs using **Kubeflow Training Operator** with **Volcano** gang scheduling, or optionally via **SLURM** (Slinky).

## Architecture

```
Nebius Project
├── VPC Network (10.100.0.0/16)
│   └── MK8s Cluster (K8s 1.33)
│       ├── 3x CPU nodes (4vCPU, 16GB) ── operators, monitoring
│       └── 2x GPU nodes (1x H200 each) ── training workloads
├── Container Registry
└── NVMe local scratch on GPU nodes (/mnt/nvme)
```

**Kubernetes Stack:**
- NVIDIA GPU Operator (device plugin + DCGM exporter)
- Volcano (gang scheduling)
- Kubeflow Training Operator (PyTorchJob CRD, integrated with Volcano)
- Prometheus + Grafana (monitoring with GPU dashboards)
- NVMe DaemonSet (format and mount local NVMe on GPU nodes)

**Training Examples:**
1. Housing Price Prediction — simple DDP on California housing dataset (2 GPUs)
2. Nemotron 4B Fine-tuning — LoRA fine-tuning on healthcare dataset (2 GPUs)

## Prerequisites

- [Nebius CLI](https://docs.nebius.com/cli/install)
- [Terraform](https://www.terraform.io/downloads) >= 1.5
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Helm](https://helm.sh/docs/intro/install/) >= 3.12
- [Docker](https://docs.docker.com/get-docker/) with buildx
- `jq`, `envsubst` (from `gettext`)
- Nebius project with GPU quota

## 1. Authenticate with Nebius

```bash
nebius auth login
nebius config set parent-id YOUR_PROJECT_ID
export NEBIUS_IAM_TOKEN="$(nebius iam get-access-token)"
```

## 2. Provision Infrastructure with Terraform

```bash
cp infra/terraform.tfvars.example infra/terraform.tfvars
# Edit infra/terraform.tfvars — set your project_id at minimum
```

Review and apply:

```bash
terraform -chdir=infra init
terraform -chdir=infra plan
terraform -chdir=infra apply
```

This creates:
- 1 VPC + subnet (10.100.0.0/16)
- MK8s cluster with 3 CPU nodes (4vCPU, 16GB) + 2 GPU nodes (1x H200 each)
- Container registry for training images
- GPU nodes with pre-installed CUDA drivers (`gpu_drivers_preset`)

Get kubeconfig and export registry coordinates:

```bash
$(terraform -chdir=infra output -raw kubeconfig_command)
kubectl get nodes

export IMAGE_REGISTRY=$(terraform -chdir=infra output -raw registry_fqdn)
export IMAGE_REPO=$(terraform -chdir=infra output -raw registry_id)
```

Verify GPU nodes appear with label `accelerator=nvidia`.

## 3. Install Kubernetes Components

Install components **in this order** — dependencies matter.

### 3.1 NVMe Local Storage

Format and mount NVMe drives on GPU nodes as local scratch at `/mnt/nvme`:

```bash
kubectl apply -f k8s/nvme/format-nvme-daemonset.yaml
kubectl get pods -n kube-system -l app=nvme-format-mount
```

> If GPU nodes have NVMe drives, they are formatted as ext4 and mounted at `/mnt/nvme`.
> If no NVMe is found, the DaemonSet creates `/mnt/nvme` as a directory on the boot disk.

### 3.2 NVIDIA GPU Operator

Installs the device plugin, DCGM exporter, and container toolkit:

```bash
./k8s/nvidia-gpu-operator/install.sh
```

Verify GPUs are detected:

```bash
kubectl get pods -n nvidia-gpu-operator
kubectl apply -f k8s/nvidia/gpu-test.yaml
kubectl logs job/nvidia-smi-test
kubectl delete job nvidia-smi-test
```

### 3.3 Volcano Scheduler

```bash
./k8s/volcano/install.sh
```

Verify:

```bash
kubectl get pods -n volcano-system
kubectl get queue -o wide
```

You should see `default` and `training` queues.

### 3.4 Kubeflow Training Operator (with Volcano)

```bash
kubectl create ns kubeflow --dry-run=client -o yaml | kubectl apply -f -
kubectl apply --server-side -k k8s/kubeflow-training-operator
```

> **Note:** Use `--server-side` to avoid annotation size limits on CRDs.

Verify the operator uses Volcano:

```bash
kubectl get deployment training-operator -n kubeflow -o yaml | grep gang-scheduler
```

You should see `--gang-scheduler-name=volcano` in the container args.

### 3.5 Monitoring (Prometheus + Grafana + DCGM)

```bash
./k8s/monitoring/install.sh
kubectl apply -f k8s/monitoring/dashboards/gpu-dcgm-configmap.yaml
```

Access Grafana:

```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80
```

Open http://localhost:3000 (credentials: `admin` / `prom-operator`).
The **NVIDIA DCGM GPU Metrics** dashboard shows GPU utilization, memory, temperature, power, and tensor core activity.

### 3.6 Quick DDP Validation

Before building custom images, verify the full stack works with a built-in test:

```bash
kubectl create ns training --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f k8s/kubeflow-training-operator/pytorchjob-ddp.yaml
kubectl get pods -n training -w
```

Wait for the job to complete, then check logs:

```bash
kubectl logs -n training -l training.kubeflow.org/job-name=pytorch-ddp --all-containers=true
```

You should see `DDP test completed`. Clean up:

```bash
kubectl delete pytorchjob pytorch-ddp -n training
```

## 4. Docker Registry Authentication

```bash
export NB_CR_SA_ID=$(nebius iam service-account get-by-name --name k8s-node-group-sa --format json | jq -r '.metadata.id')
export NB_CR_PASSWORD=$(nebius iam static-key issue --account-service-account-id "$NB_CR_SA_ID" --service CONTAINER_REGISTRY --format json | jq -r '.token')

docker login "$IMAGE_REGISTRY" -u iam -p "$NB_CR_PASSWORD"
```

## 5. Build and Push Training Images

For ARM Macs, set `export PLATFORM=linux/amd64` first.

```bash
# Housing
cd training-job-kubeflow/housing
./build_and_push.sh
cd ../..

# Nemotron 4B
cd training-job-kubeflow/nemotron4b
./build_and_push.sh
cd ../..
```

## 6. Submit Training Jobs

### Housing Price Prediction

```bash
envsubst < training-job-kubeflow/housing/pytorchjob.yaml | kubectl apply -f -
```

Monitor:

```bash
kubectl get pytorchjob -n training
kubectl get pods -n training -w
kubectl logs -n training -l training.kubeflow.org/job-name=housing-price-train --all-containers=true -f
```

### Nemotron 4B Healthcare Fine-tuning

```bash
envsubst < training-job-kubeflow/nemotron4b/pytorchjob.yaml | kubectl apply -f -
```

Monitor:

```bash
kubectl get pytorchjob -n training
kubectl logs -n training -l training.kubeflow.org/job-name=nemotron4b-healthcare-finetune --all-containers=true -f
```

## 7. Monitor GPU Metrics

During training, open Grafana (see step 3.5) and navigate to **GPU > NVIDIA DCGM GPU Metrics**. Filter by namespace `training` to see real-time:

- GPU utilization (%)
- GPU memory used/free
- Temperature and power draw
- Tensor core utilization
- PCIe throughput

## 8. (Optional) SLURM Path

Install the Slinky operator for SLURM-based job submission:

```bash
export SLINKY_VERSION=1.0.0
./k8s/slinky/install.sh
```

Build and push SLURM images:

```bash
cd training-job-slurm/housing && ./build_and_push.sh && cd ../..
cd training-job-slurm/nemotron4b && ./build_and_push.sh && cd ../..
```

Submit jobs:

```bash
export SLURM_LOGIN_POD="$(kubectl -n slurm get pod -l app.kubernetes.io/component=login -o jsonpath='{.items[0].metadata.name}')"

# Housing
export HOUSING_IMAGE="${IMAGE_REGISTRY}/${IMAGE_REPO}/housing-price-train:latest"
kubectl -n slurm exec -i "${SLURM_LOGIN_POD}" -- \
  sbatch --export=ALL,HOUSING_IMAGE="${HOUSING_IMAGE}" \
  < training-job-slurm/housing/slurm-job.sbatch

# Nemotron 4B
export NEMOTRON_IMAGE="${IMAGE_REGISTRY}/${IMAGE_REPO}/nemotron4b-finetune:latest"
kubectl -n slurm exec -i "${SLURM_LOGIN_POD}" -- \
  sbatch --export=ALL,NEMOTRON_IMAGE="${NEMOTRON_IMAGE}" \
  < training-job-slurm/nemotron4b/slurm-job.sbatch
```

Check SLURM jobs:

```bash
kubectl -n slurm exec -it "${SLURM_LOGIN_POD}" -- squeue
kubectl -n slurm exec -it "${SLURM_LOGIN_POD}" -- sinfo
```

## 9. (Optional) vLLM Serving

### Single-node (2 GPUs, tensor parallel)

```bash
kubectl create ns vllm --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic hf-token -n vllm --from-literal=token=YOUR_HF_TOKEN
kubectl apply -f k8s/vllm/nemotron-vllm.yaml
```

### Multi-node Ray cluster

```bash
kubectl apply -f k8s/vllm/nemotron-fp8-multinode-ray.yaml
kubectl apply -f k8s/vllm/vllm-ray-head-lb.yaml
kubectl get svc -n vllm -o wide
```

## Cleanup

```bash
kubectl delete pytorchjob --all -n training
terraform -chdir=infra destroy
```

## Troubleshooting

**GPU Operator pods crashing**: Drivers may conflict with the boot image. Set `driver.enabled: false` in `k8s/nvidia-gpu-operator/values.yaml` and re-run `./k8s/nvidia-gpu-operator/install.sh`.

**Volcano pods not scheduling**: Verify CRDs exist (`kubectl get crd | grep volcano`) and queues are created (`kubectl get queue`).

**Training operator not using Volcano**: Check `kubectl get deployment training-operator -n kubeflow -o yaml | grep gang`. The `--gang-scheduler-name=volcano` flag must be present.

**NVMe not mounted**: Check `kubectl logs -n kube-system -l app=nvme-format-mount -c format-and-mount`. The `1gpu-16vcpu-200gb` preset may not include local NVMe — the DaemonSet handles this gracefully by creating `/mnt/nvme` as a directory on the boot disk.

**NCCL errors**: With 2x 1-GPU nodes (no InfiniBand), NCCL uses TCP/IP. Ensure `NCCL_SOCKET_IFNAME=eth0` is set. Check connectivity between GPU nodes by exec'ing into a training pod and pinging the other node.

## Notes

- GPU nodes are labeled `accelerator=nvidia` and tainted `nvidia.com/gpu=present:NoSchedule`
- All training manifests use `envsubst` for image path templating — always submit with `envsubst < file.yaml | kubectl apply -f -`
- Volcano gang scheduling ensures all replicas of a PyTorchJob are scheduled together or not at all
- The `node_service_account_name` in terraform.tfvars controls whether nodes can pull from the private registry
- HuggingFace model cache for nemotron4b is stored on NVMe (`/mnt/nvme/hf-cache`) for faster downloads
