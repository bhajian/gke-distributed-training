provider "nebius" {}

data "nebius_iam_v1_service_account" "node_group_sa" {
  count = var.node_service_account_name == "" ? 0 : 1

  parent_id = var.project_id
  name      = var.node_service_account_name
}

locals {
  node_service_account = var.node_service_account_name == "" ? {} : {
    service_account_id = data.nebius_iam_v1_service_account.node_group_sa[0].id
  }

  cpu_resources = merge(
    { platform = var.cpu_platform },
    var.cpu_preset == "" ? {} : { preset = var.cpu_preset }
  )

  gpu_resources = merge(
    { platform = var.gpu_platform },
    var.gpu_preset == "" ? {} : { preset = var.gpu_preset }
  )
}

resource "nebius_vpc_v1_network" "network" {
  parent_id = var.project_id

  name = var.network_name
}

resource "nebius_vpc_v1_subnet" "subnet" {
  parent_id  = var.project_id
  network_id = nebius_vpc_v1_network.network.id

  name = var.subnet_name

  ipv4_private_pools = {
    pools = [
      {
        cidrs = [
          {
            cidr = var.subnet_cidr
          }
        ]
      }
    ]
  }
}

resource "nebius_mk8s_v1_cluster" "cluster" {
  parent_id = var.project_id

  name = var.cluster_name

  control_plane = {
    subnet_id         = nebius_vpc_v1_subnet.subnet.id
    version           = var.kubernetes_version
    etcd_cluster_size = var.etcd_cluster_size
    endpoints = {
      public_endpoint = {}
    }
  }
}

resource "nebius_mk8s_v1_node_group" "cpu" {
  parent_id        = nebius_mk8s_v1_cluster.cluster.id
  fixed_node_count = var.cpu_node_count

  name = "${var.cluster_name}-cpu"

  template = merge(
    {
      resources = local.cpu_resources
    },
    local.node_service_account
  )
}

resource "nebius_mk8s_v1_node_group" "gpu" {
  parent_id        = nebius_mk8s_v1_cluster.cluster.id
  fixed_node_count = var.gpu_node_count

  name = "${var.cluster_name}-gpu"

  template = merge(
    {
      resources = local.gpu_resources
      metadata = {
        labels = {
          accelerator = "nvidia"
        }
      }
      taints = [
        {
          key    = "nvidia.com/gpu"
          value  = "present"
          effect = "NO_SCHEDULE"
        }
      ]
    },
    local.node_service_account
  )
}

resource "nebius_registry_v1_registry" "training" {
  parent_id   = var.project_id
  description = "Container registry for Nebius ML training images"

  name = var.registry_name
}
