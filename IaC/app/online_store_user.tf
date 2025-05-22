locals {
  online_store_user_image_name     = "${local.online_store_docker_images_name_prefix}-user"
  online_store_user_directory_name = "user"
  online_store_user_directory_path = "${local.online_store_directory_path}/${local.online_store_user_directory_name}"
}

resource "azurerm_container_registry_task" "user" {
  name                 = "user-task"
  container_registry_id = data.azurerm_container_registry.demo.id
  tags = {
    owner = var.email
  }
  platform {
    os      = "Linux"
    architecture = "amd64"
  }
  docker_step {
    dockerfile_path = "user/Dockerfile"
    context_path       = "https://github.com/vrabbi/observability360#main:online_store"
    image_names      = [local.online_store_user_image_name]
    context_access_token = var.github_token
  }
}

resource "azurerm_container_registry_task_schedule_run_now" "user" {
  container_registry_task_id = azurerm_container_registry_task.user.id
}

resource "kubernetes_deployment" "online_store_user" {
  depends_on = [
    azurerm_container_registry_task_schedule_run_now.user
  ]
  metadata {
    name      = "online-store-user"
    namespace = kubernetes_namespace.online_store.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "online-store-user"
      }
    }

    template {
      metadata {
        labels = {
          app = "online-store-user"
        }
      }

      spec {
        container {
          name  = "online-store-user"
          image = "${data.azurerm_container_registry.demo.login_server}/${local.online_store_user_image_name}"
          resources {
            limits = {
              cpu    = "0.5"
              memory = "2Gi"
            }
            requests = {
              cpu    = "0.2"
              memory = "1Gi"
            }
          }

          port {
            container_port = 5000
            protocol       = "TCP"
          }

          env {
            name  = "OTEL_EXPORTER_OTLP_ENDPOINT"
            value = "http://${kubernetes_service.otel_collector.metadata[0].name}.${kubernetes_namespace.opentelemtry.metadata[0].name}.svc.cluster.local:4317"
          }

          env {
            name = "OTEL_PYTHON_LOGGING_AUTO_INSTRUMENTATION_ENABLED"
            value = "true"
          }

          volume_mount {
            name       = "online-store-db"
            mount_path = "/app/online_store/db"
          }

        }
        volume {
          name = "online-store-db"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.online_store_db.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "online_store_user" {
  metadata {
    name      = "user"
    namespace = kubernetes_namespace.online_store.metadata[0].name
  }

  spec {
    selector = {
      app = "online-store-user"
    }

    port {
      name        = "port-80"
      port        = 80
      target_port = 5000
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }
}