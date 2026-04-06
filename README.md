# GKE A100 Sandbox (Terraform + Kubernetes Manifests)

This repo provisions a GKE cluster with A100 GPUs and a CPU node pool, then installs GPU enablement and ML components via Kubernetes manifests.

## Prereqs
- `gcloud`, `terraform`, `kubectl`, `kustomize` (or `kubectl apply -k` support)
- GCP project with quota for A100 GPUs in `us-central1`

## 1) Authenticate and set project
```bash
gcloud auth login
gcloud auth application-default login

gcloud config set project openenv-8t66t
gcloud config set compute/region us-central1
gcloud config set compute/zone us-central1-a
```

## 2) Enable required APIs (once per project)
```bash
gcloud services enable \
  compute.googleapis.com \
  container.googleapis.com \
  iam.googleapis.com \
  serviceusage.googleapis.com
```

## 3) Terraform: create VPC + GKE + node pools
All Terraform files live in `infra/`.

### Configure variables
```bash
cp infra/terraform.tfvars.example infra/terraform.tfvars
```
Edit `infra/terraform.tfvars`:
```
project_id      = "openenv-8t66t"
admin_cidr      = "0.0.0.0/0"
region          = "us-central1"
node_locations  = ["us-central1-a"]

cpu_node_count   = 3
cpu_machine_type = "e2-standard-8"  # or n2-standard-8

gpu_node_count   = 1  # 1 node, 2x A100 40GB (a2-highgpu-2g)
gpu_machine_type = "a2-highgpu-2g"
gpu_type         = "nvidia-tesla-a100"
gpu_count_per_node = 2
```

### Apply
```bash
cd infra
terraform init
terraform plan
terraform apply
```

### Get kubeconfig
```bash
gcloud container clusters get-credentials gke-a100 --region us-central1 --project openenv-8t66t
```

## 4) Kubernetes installs (manifests)
All manifests live in `k8s/`.

### 4.1 NVIDIA device plugin (required for GPU scheduling)
```bash
kubectl apply -f k8s/nvidia/device-plugin.yaml
```

### 4.2 GPU test (nvidia-smi)
```bash
kubectl apply -f k8s/nvidia/gpu-test.yaml
kubectl logs job/nvidia-smi-test
```
Cleanup (optional):
```bash
kubectl delete job nvidia-smi-test
```

### 4.3 Kueue (use server-side apply)
Kueue CRDs can exceed the client-side annotation size limit, so use server-side apply:
```bash
kubectl apply --server-side -f k8s/kueue/manifests.yaml
```

Create Kueue queues for gang scheduling:
```bash
kubectl create ns training --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f k8s/kueue/queues.yaml
```

### 4.4 Kubeflow Training Operator (use server-side apply)
Create the namespace first, then use server-side apply because some CRDs exceed the client-side annotation size limit:
```bash
kubectl create ns kubeflow --dry-run=client -o yaml | kubectl apply -f -
kubectl apply --server-side -k k8s/kubeflow-training-operator
```

### 4.5 Training jobs (containerized, multi-node, Kueue gang scheduling)
All training jobs live under `training-job/` with source code, Dockerfiles, build scripts, and PyTorchJob manifests.

#### 4.5.1 Housing price prediction (DDP, 2x A100)
Build and push the image:
```bash
cd training-job/housing
export PROJECT_ID=openenv-8t66t
./build_and_push.sh
```
Submit the job:
```bash
kubectl apply -f training-job/housing/pytorchjob.yaml
kubectl get pytorchjob -n training
kubectl get pods -n training
```

#### 4.5.2 Nemotron 4B healthcare fine-tune (LoRA, DDP, 2x A100)
Build and push the image:
```bash
cd training-job/nemotron4b
export PROJECT_ID=openenv-8t66t
./build_and_push.sh
```
Submit the job:
```bash
kubectl apply -f training-job/nemotron4b/pytorchjob.yaml
kubectl get pytorchjob -n training
kubectl get pods -n training
```

These PyTorchJobs are labeled with `kueue.x-k8s.io/queue-name: training-queue`, so they are gang scheduled by Kueue.

### 4.6 vLLM Nemotron 3 Nano (single-node, 2x A100)
```bash
kubectl apply -f k8s/vllm/nemotron-vllm.yaml
kubectl get pods -n vllm
```
This deployment requests 2 GPUs per pod and uses `--tensor-parallel-size 2`, so it requires a 2‑GPU node (e.g., `a2-highgpu-2g`).

### 4.7 vLLM Nemotron 3 Nano (multi-node Ray launcher, 2x A100 on separate nodes)
This runs a **single vLLM server** sharded across **2 nodes with 1 GPU each** using Ray.

```bash
kubectl delete deployment -n vllm nemotron-nano-vllm
kubectl apply -f k8s/vllm/nemotron-fp8-multinode-ray.yaml
kubectl get pods -n vllm -o wide
```

Expose vLLM with a LoadBalancer:
```bash
kubectl apply -f k8s/vllm/vllm-ray-head-lb.yaml
kubectl get svc -n vllm -o wide
```

Test the API:
```bash
export VLLM_LB_IP=<EXTERNAL-IP>
curl http://$VLLM_LB_IP:8000/v1/models
```

If you need to pull from Hugging Face private models, create a token secret:
```bash
kubectl create secret generic hf-token -n vllm --from-literal=token=YOUR_HF_TOKEN
```

## 5) Training and fine-tuning (containerized, Kueue + gang scheduling)
All training workloads are under `training-job/` and run via Kubeflow Training Operator + Kueue.

### 5.1 Build + push images
Housing price prediction:
```bash
cd training-job/housing
export PROJECT_ID=openenv-8t66t
./build_and_push.sh
```

Nemotron 4B LoRA fine-tune:
```bash
cd training-job/nemotron4b
export PROJECT_ID=openenv-8t66t
./build_and_push.sh
```

### 5.2 Submit jobs (gang scheduled)
```bash
kubectl apply -f training-job/housing/pytorchjob.yaml
kubectl apply -f training-job/nemotron4b/pytorchjob.yaml
```

Check status:
```bash
kubectl get pytorchjob -n training
kubectl get pods -n training
```

If you need to reapply with a different queue label, delete the old job first (queue label is immutable):
```bash
kubectl delete pytorchjob -n training housing-price-train
kubectl delete pytorchjob -n training nemotron4b-healthcare-finetune
```

## Notes
- GPU driver install is handled by GKE based on the GPU node pool configuration in Terraform.
- NVIDIA device plugin is still required to advertise GPUs to Kubernetes.
- `admin_cidr = "0.0.0.0/0"` opens SSH/ICMP to nodes from anywhere. Acceptable for sandbox, not for production.

## Cleanup
```bash
cd infra
terraform destroy
```
# gke-distributed-training
