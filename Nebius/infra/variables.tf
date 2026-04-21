variable "project_id" {
  description = "Nebius project ID (parent_id)"
  type        = string
}

variable "network_name" {
  description = "Name for the Nebius VPC network"
  type        = string
  default     = "nebius-ml-network"
}

variable "subnet_name" {
  description = "Name for the Nebius subnet"
  type        = string
  default     = "nebius-ml-subnet"
}

variable "subnet_cidr" {
  description = "CIDR block for the Nebius subnet"
  type        = string
  default     = "10.100.0.0/16"
}

variable "cluster_name" {
  description = "Managed Kubernetes cluster name"
  type        = string
  default     = "nebius-ml-cluster"
}

variable "kubernetes_version" {
  description = "Kubernetes version for control plane (MAJOR.MINOR)"
  type        = string
  default     = "1.33"
}

variable "etcd_cluster_size" {
  description = "Number of etcd instances for control plane"
  type        = number
  default     = 3
}

variable "cpu_node_count" {
  description = "CPU node group size"
  type        = number
  default     = 3
}

variable "cpu_platform" {
  description = "Nebius CPU platform"
  type        = string
  default     = "cpu-e2"
}

variable "cpu_preset" {
  description = "Nebius CPU preset (empty to use provider default)"
  type        = string
  default     = "2vcpu-8gb"
}

variable "gpu_node_count" {
  description = "GPU node group size"
  type        = number
  default     = 1
}

variable "gpu_platform" {
  description = "Nebius GPU platform"
  type        = string
  default     = "gpu-h200-sxm"
}

variable "gpu_preset" {
  description = "Nebius GPU preset (empty to use provider default)"
  type        = string
  default     = "1gpu-16vcpu-200gb"
}

variable "node_service_account_name" {
  description = "Node group service account name for pulling private Nebius registry images"
  type        = string
  default     = "k8s-node-group-sa"
}

variable "registry_name" {
  description = "Container Registry name"
  type        = string
  default     = "training-registry"
}
