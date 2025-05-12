locals {
  application_namespace_name = "application"

  application_directory_path            = "../../ai_chess"
  application_ocker_images_name_prefix = "${var.base_name}-ai-chess"
  application_otel_directory_path       = "${local.application_directory_path}/otel"
}

resource "kubernetes_namespace" "application" {
  metadata {
    name = local.application_namespace_name
  }
}


resource "kubernetes_storage_class" "azurefile" {
  metadata {
    name = "azurefile-custom"
  }
  storage_provisioner = "kubernetes.io/azure-file"
  mount_options = [
    "dir_mode=0777",
    "file_mode=0777",
    "uid=1000",
    "gid=1000",
    "mfsymlinks",
    "nobrl",
    "cache=none"
  ]
  parameters = {
    skuName = "Standard_LRS"
  }
}

resource "kubernetes_persistent_volume_claim" "application__db" {
  metadata {
    name      = "application-db-pvc"
    namespace = kubernetes_namespace.application.metadata[0].name
  }
  spec {
    access_modes = ["ReadWriteMany"]
    resources {
      requests = {
        storage = "5Gi"
      }
    }
    storage_class_name = kubernetes_storage_class.azurefile.metadata[0].name
  }
}