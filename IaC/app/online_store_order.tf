locals {
  online_store_order_image_name     = "${local.online_store_docker_images_name_prefix}-order"
  online_store_order_directory_name = "order"
  online_store_order_directory_path = "${local.online_store_directory_path}/${local.online_store_order_directory_name}"
}

resource "azurerm_container_registry_task" "order" {
  name                 = "order-task"
  container_registry_id = data.azurerm_container_registry.demo.id
  tags = {
    owner = var.email
  }
  platform {
    os      = "Linux"
    architecture = "amd64"
  }
  docker_step {
    dockerfile_path = "order/Dockerfile"
    context_path       = "${var.github_repo_url}#${var.github_repo_branch}:online_store"
    image_names      = ["${local.online_store_order_image_name}:latest","${local.online_store_order_image_name}:{{.Run.ID}}"]
    context_access_token = var.github_token
  }
  source_trigger {
    name = "git-commit"
    events = ["commit"]
    repository_url = var.github_repo_url
    source_type = "Github"
    branch = var.github_repo_branch
    enabled = true
    authentication {
      token = var.github_token
      token_type = "PAT"
    }
  }
}

resource "azurerm_container_registry_task_schedule_run_now" "order" {
  container_registry_task_id = azurerm_container_registry_task.order.id
}

resource "kubernetes_deployment" "online_store_order" {
  depends_on = [
    azurerm_container_registry_task_schedule_run_now.order
  ]
  metadata {
    name      = "online-store-order"
    namespace = kubernetes_namespace.online_store.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "online-store-order"
      }
    }

    template {
      metadata {
        labels = {
          app = "online-store-order"
        }
      }

      spec {
        container {
          name  = "online-store-order"
          image = "${data.azurerm_container_registry.demo.login_server}/${local.online_store_order_image_name}"
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
            container_port = 5003
            protocol       = "TCP"
          }

          env {
            name  = "OTEL_EXPORTER_OTLP_ENDPOINT"
            value = "http://${kubernetes_service.otel_collector.metadata[0].name}.${kubernetes_namespace.opentelemetry.metadata[0].name}.svc.cluster.local:4317"
          }

          env {
            name = "OTEL_PYTHON_LOGGING_AUTO_INSTRUMENTATION_ENABLED"
            value = "true"
          }

          env {
            name  = "CART_SERVICE_URL"
            value = "http://${kubernetes_service.online_store_cart.metadata[0].name}.${kubernetes_namespace.online_store.metadata[0].name}.svc.cluster.local"
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

resource "kubernetes_service" "online_store_order" {
  metadata {
    name      = "order"
    namespace = kubernetes_namespace.online_store.metadata[0].name
  }

  spec {
    selector = {
      app = "online-store-order"
    }

    port {
      name        = "port-80"
      port        = 80
      target_port = 5003
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }
}