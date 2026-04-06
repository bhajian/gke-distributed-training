variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "us-central1"
}

variable "node_locations" {
  description = "Zones for the GKE cluster node pools"
  type        = list(string)
  default     = ["us-central1-a"]
}

variable "cluster_name" {
  description = "GKE cluster name"
  type        = string
  default     = "gke-a100"
}

variable "network_name" {
  description = "VPC name"
  type        = string
  default     = "gke-a100-vpc"
}

variable "subnet_name" {
  description = "Subnet name"
  type        = string
  default     = "gke-a100-subnet"
}

variable "subnet_cidr" {
  description = "Primary subnet CIDR"
  type        = string
  default     = "10.10.0.0/16"
}

variable "pods_cidr" {
  description = "Secondary range for pods"
  type        = string
  default     = "10.20.0.0/16"
}

variable "services_cidr" {
  description = "Secondary range for services"
  type        = string
  default     = "10.30.0.0/16"
}

variable "admin_cidr" {
  description = "CIDR block allowed to SSH to nodes (e.g. your public IP /32)"
  type        = string
}

variable "cpu_node_count" {
  description = "CPU node pool size"
  type        = number
  default     = 1
}

variable "cpu_machine_type" {
  description = "CPU node pool machine type"
  type        = string
  default     = "e2-standard-4"
}

variable "gpu_node_count" {
  description = "GPU node pool size"
  type        = number
  default     = 1
}

variable "gpu_machine_type" {
  description = "GPU node pool machine type"
  type        = string
  default     = "a2-ultragpu-2g"
}

variable "gpu_type" {
  description = "GPU accelerator type"
  type        = string
  default     = "nvidia-a100-80gb"
}

variable "gpu_count_per_node" {
  description = "Number of GPUs per GPU node"
  type        = number
  default     = 2
}

variable "gpu_driver_version" {
  description = "GPU driver version to install"
  type        = string
  default     = "LATEST"
}

variable "enable_guest_accelerator" {
  description = "Whether to set guest_accelerator block on the GPU node pool"
  type        = bool
  default     = true
}
