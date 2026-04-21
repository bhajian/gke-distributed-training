output "network_id" {
  value = nebius_vpc_v1_network.network.id
}

output "subnet_id" {
  value = nebius_vpc_v1_subnet.subnet.id
}

output "cluster_id" {
  value = nebius_mk8s_v1_cluster.cluster.id
}

output "kubeconfig_command" {
  value = "nebius mk8s cluster get-credentials --id ${nebius_mk8s_v1_cluster.cluster.id} --external"
}

output "registry_id" {
  value = nebius_registry_v1_registry.training.id
}

output "registry_fqdn" {
  value = nebius_registry_v1_registry.training.status.registry_fqdn
}

output "image_prefix" {
  value = "${nebius_registry_v1_registry.training.status.registry_fqdn}/${nebius_registry_v1_registry.training.id}"
}
