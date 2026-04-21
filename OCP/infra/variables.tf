variable "kubeconfig_path" {
  description = "Path to kubeconfig used by Terraform"
  type        = string
  default     = "~/.kube/config"
}

variable "openshift_ai_namespace" {
  description = "Namespace where OpenShift AI operator is installed"
  type        = string
  default     = "redhat-ods-operator"
}

variable "openshift_ai_subscription_name" {
  description = "Subscription name for OpenShift AI"
  type        = string
  default     = "rhods-operator"
}

variable "openshift_ai_package_name" {
  description = "OLM package name for OpenShift AI"
  type        = string
  default     = "rhods-operator"
}

variable "openshift_ai_channel" {
  description = "Operator channel for OpenShift AI"
  type        = string
  default     = "stable"
}

variable "openshift_operator_source" {
  description = "Operator source"
  type        = string
  default     = "redhat-operators"
}

variable "openshift_operator_source_namespace" {
  description = "Namespace for operator source"
  type        = string
  default     = "openshift-marketplace"
}

variable "create_datascience_cluster" {
  description = "Create a DataScienceCluster CR (set true after the operator and CRDs are ready)"
  type        = bool
  default     = false
}

variable "datascience_cluster_name" {
  description = "Name of the DataScienceCluster custom resource"
  type        = string
  default     = "default-dsc"
}
