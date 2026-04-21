provider "kubernetes" {
  config_path = var.kubeconfig_path
}

resource "kubernetes_namespace_v1" "openshift_ai" {
  metadata {
    name = var.openshift_ai_namespace
  }
}

resource "kubernetes_manifest" "operator_group" {
  manifest = {
    apiVersion = "operators.coreos.com/v1"
    kind       = "OperatorGroup"
    metadata = {
      name      = "rhods-operator-group"
      namespace = var.openshift_ai_namespace
    }
    spec = {
      targetNamespaces = [var.openshift_ai_namespace]
    }
  }

  depends_on = [kubernetes_namespace_v1.openshift_ai]
}

resource "kubernetes_manifest" "subscription" {
  manifest = {
    apiVersion = "operators.coreos.com/v1alpha1"
    kind       = "Subscription"
    metadata = {
      name      = var.openshift_ai_subscription_name
      namespace = var.openshift_ai_namespace
    }
    spec = {
      channel             = var.openshift_ai_channel
      installPlanApproval = "Automatic"
      name                = var.openshift_ai_package_name
      source              = var.openshift_operator_source
      sourceNamespace     = var.openshift_operator_source_namespace
    }
  }

  depends_on = [kubernetes_manifest.operator_group]
}

resource "kubernetes_manifest" "datasciencecluster" {
  count = var.create_datascience_cluster ? 1 : 0

  manifest = {
    apiVersion = "datasciencecluster.opendatahub.io/v1"
    kind       = "DataScienceCluster"
    metadata = {
      name      = var.datascience_cluster_name
      namespace = var.openshift_ai_namespace
    }
    spec = {
      components = {
        dashboard = {
          managementState = "Managed"
        }
        workbenches = {
          managementState = "Managed"
        }
        codeflare = {
          managementState = "Managed"
        }
        trainingoperator = {
          managementState = "Managed"
        }
        kserve = {
          managementState = "Managed"
        }
      }
    }
  }

  depends_on = [kubernetes_manifest.subscription]
}
