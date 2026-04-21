# Nebius Managed Kubernetes Sandbox (Terraform + Kubernetes Manifests)

This repo provisions Nebius networking, Managed Kubernetes, node groups, and Container Registry with Terraform, then runs the same training/serving workloads as the GKE/OCP variants.

## Prereqs
- `nebius` CLI, `terraform`, `kubectl`, `docker`, `jq`, `envsubst`
- Nebius project with GPU quota

## 1) Authenticate and set access
```bash
nebius auth login
nebius config set parent-id YOUR_PROJECT_ID

# Terraform user-auth mode (recommended for local use)
export NEBIUS_IAM_TOKEN="$(nebius iam get-access-token)"
```

## 2) Terraform: create network + MK8s + node groups + registry
All Terraform files live in `infra/`.

```bash
cp infra/terraform.tfvars.example infra/terraform.tfvars
```
Edit `infra/terraform.tfvars` and set at least:
```hcl
project_id = "YOUR_PROJECT_ID"
```

Apply:
```bash
terraform -chdir=infra init
terraform -chdir=infra plan
terraform -chdir=infra apply
```

Get kubeconfig:
```bash
$(terraform -chdir=infra output -raw kubeconfig_command)
kubectl cluster-info
```

Export registry coordinates for build/deploy steps:
```bash
export IMAGE_REGISTRY=$(terraform -chdir=infra output -raw registry_fqdn)
export IMAGE_REPO=$(terraform -chdir=infra output -raw registry_id)
```

## 3) Install GPU and training components
Install NVIDIA device plugin:
```bash
kubectl apply -f k8s/nvidia/device-plugin.yaml
kubectl apply -f k8s/nvidia/gpu-test.yaml
kubectl logs job/nvidia-smi-test
```

Install Kueue and Kubeflow Training Operator:
```bash
kubectl apply --server-side -f k8s/kueue/manifests.yaml
kubectl create ns training --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f k8s/kueue/queues.yaml

kubectl create ns kubeflow --dry-run=client -o yaml | kubectl apply -f -
kubectl apply --server-side -k k8s/kubeflow-training-operator
```

## 4) Authenticate Docker to Nebius Container Registry
Issue a static key for Container Registry and log in:
```bash
export NB_CR_SA_ID=$(nebius iam service-account get-by-name --name k8s-node-group-sa --format json | jq -r '.metadata.id')
export NB_CR_PASSWORD=$(nebius iam static-key issue --account-service-account-id "$NB_CR_SA_ID" --service CONTAINER_REGISTRY --format json | jq -r '.token')

docker login "$IMAGE_REGISTRY" -u iam -p "$NB_CR_PASSWORD"
```

## 5) Build and push images
```bash
cd training-job-kubeflow/housing
./build_and_push.sh

cd ../nemotron4b
./build_and_push.sh
```

## 6) Submit training jobs
Housing:
```bash
envsubst < training-job-kubeflow/housing/pytorchjob.yaml | kubectl apply -f -
kubectl get pytorchjob -n training
kubectl get pods -n training
```

Nemotron 4B:
```bash
envsubst < training-job-kubeflow/nemotron4b/pytorchjob.yaml | kubectl apply -f -
kubectl get pytorchjob -n training
kubectl get pods -n training
```

Logs:
```bash
kubectl logs -n training -l training.kubeflow.org/job-name=housing-price-train --all-containers=true
kubectl logs -n training -l training.kubeflow.org/job-name=nemotron4b-healthcare-finetune --all-containers=true
```

## 7) Slurm path (optional)
```bash
export SLINKY_VERSION=1.0.0
./k8s/slinky/install.sh
kubectl -n slurm get pods
```

Submit housing:
```bash
export HOUSING_IMAGE=${IMAGE_REGISTRY}/${IMAGE_REPO}/housing-price-train:latest
export SLURM_LOGIN_POD=$(kubectl -n slurm get pods | awk '/login/{print $1; exit}')
kubectl -n slurm exec -i "$SLURM_LOGIN_POD" -- sbatch - < training-job-slurm/housing/slurm-job.sbatch
```

Submit nemotron:
```bash
export NEMOTRON_IMAGE=${IMAGE_REGISTRY}/${IMAGE_REPO}/nemotron4b-finetune:latest
export SLURM_LOGIN_POD=$(kubectl -n slurm get pods | awk '/login/{print $1; exit}')
kubectl -n slurm exec -i "$SLURM_LOGIN_POD" -- sbatch - < training-job-slurm/nemotron4b/slurm-job.sbatch
```

## 8) vLLM serving
Single-node:
```bash
kubectl apply -f k8s/vllm/nemotron-vllm.yaml
kubectl get pods -n vllm
```

Multi-node Ray:
```bash
kubectl apply -f k8s/vllm/nemotron-fp8-multinode-ray.yaml
kubectl apply -f k8s/vllm/vllm-ray-head-lb.yaml
kubectl get svc -n vllm -o wide
```

## Notes
- Terraform labels GPU nodes with `accelerator=nvidia`; manifests in this folder select that label.
- The node group service account defaults to `k8s-node-group-sa` so pods can pull private Nebius registry images.
