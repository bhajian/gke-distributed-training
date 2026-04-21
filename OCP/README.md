# OCP A100 Sandbox (OpenShift + OpenShift AI Operator)

This repo provisions OpenShift AI components with Terraform and runs the same training/serving workloads as the GKE variant.

## Prereqs
- `oc`, `kubectl`, `terraform`, `docker`, `envsubst`
- OpenShift cluster with GPU workers
- Cluster-admin permissions

## 1) Login
```bash
oc login https://api.<cluster-domain>:6443
oc whoami
```

## 2) Install OpenShift AI Operator (Terraform)
All Terraform files live in `infra/`.

```bash
cp infra/terraform.tfvars.example infra/terraform.tfvars
terraform -chdir=infra init
terraform -chdir=infra plan
terraform -chdir=infra apply
```

Verify subscription and CSV:
```bash
oc -n redhat-ods-operator get subscription rhods-operator
oc -n redhat-ods-operator get csv
```

Optional second pass to create `DataScienceCluster`:
1. Set `create_datascience_cluster = true` in `infra/terraform.tfvars`
2. Run `terraform -chdir=infra apply` again

## 3) Prepare GPU node labels for manifests
The training and serving manifests in this folder use:
```yaml
nodeSelector:
  accelerator: nvidia
```

Label your GPU nodes accordingly:
```bash
oc label node <gpu-node-name> accelerator=nvidia --overwrite
oc get nodes -L accelerator
```

## 4) Install Kueue + Kubeflow Training Operator
```bash
kubectl apply --server-side -f k8s/kueue/manifests.yaml
kubectl create ns training --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f k8s/kueue/queues.yaml

kubectl create ns kubeflow --dry-run=client -o yaml | kubectl apply -f -
kubectl apply --server-side -k k8s/kubeflow-training-operator
```

## 5) Build and push images
Use any registry reachable by your OpenShift cluster. The build scripts in this folder use:
- `IMAGE_REGISTRY` (example: `quay.io` or OpenShift internal route host)
- `IMAGE_REPO` (example: `my-org/ocp-training`)

Example with OpenShift internal registry route:
```bash
oc patch configs.imageregistry.operator.openshift.io/cluster \
  --type=merge -p '{"spec":{"defaultRoute":true}}'

export IMAGE_REGISTRY=$(oc get route default-route -n openshift-image-registry -o jsonpath='{.spec.host}')
export IMAGE_REPO=training

docker login -u kubeadmin -p "$(oc whoami -t)" "$IMAGE_REGISTRY"
```

Build images:
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
- This OCP variant keeps training and serving workloads aligned with the GKE variant.
- Ensure NVIDIA GPU support is enabled in your OpenShift cluster (typically via NVIDIA GPU Operator).
