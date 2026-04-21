output "openshift_ai_namespace" {
  value = var.openshift_ai_namespace
}

output "subscription_name" {
  value = var.openshift_ai_subscription_name
}

output "check_subscription_command" {
  value = "oc -n ${var.openshift_ai_namespace} get subscription ${var.openshift_ai_subscription_name}"
}

output "check_csv_command" {
  value = "oc -n ${var.openshift_ai_namespace} get csv"
}
