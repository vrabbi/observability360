locals {
  online_store_ui_image_name     = "${local.online_store_docker_images_name_prefix}-ui"
  online_store_ui_directory_name = "ui"
  online_store_ui_directory_path = "${local.online_store_directory_path}/${local.online_store_ui_directory_name}"
}

resource "azurerm_container_registry_task" "ui" {
  name                 = "ui-task"
  container_registry_id = data.azurerm_container_registry.demo.id
  tags = {
    owner = var.email
  }
  platform {
    os      = "Linux"
    architecture = "amd64"
  }
  docker_step {
    dockerfile_path = "ui/Dockerfile"
    context_path       = "${var.github_repo_url}#${var.github_repo_branch}:online_store"
    image_names      = [local.online_store_ui_image_name]
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

resource "azurerm_container_registry_task_schedule_run_now" "ui" {
  container_registry_task_id = azurerm_container_registry_task.ui.id
}

resource "kubernetes_deployment" "online_store_ui" {
  depends_on = [
    azurerm_container_registry_task_schedule_run_now.ui
  ]
  metadata {
    name      = "online-store-ui"
    namespace = kubernetes_namespace.online_store.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "online-store-ui"
      }
    }

    template {
      metadata {
        labels = {
          app = "online-store-ui"
        }
      }

      spec {
        container {
          name  = "online-store-ui"
          image = "${data.azurerm_container_registry.demo.login_server}/${local.online_store_ui_image_name}"
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
            container_port = 8501
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
            name  = "ORDER_SERVICE_URL"
            value = local.order_service_url
          }
          env {
            name  = "USER_SERVICE_URL"
            value = local.user_service_url
          }
          env {
            name  = "PRODUCT_SERVICE_URL"
            value = local.product_service_url
          }
          env {
            name  = "CART_SERVICE_URL"
            value = local.cart_service_url
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "online_store_ui" {
  metadata {
    name      = "ui"
    namespace = kubernetes_namespace.online_store.metadata[0].name
  }

  spec {
    selector = {
      app = "online-store-ui"
    }

    port {
      name        = "port-80"
      port        = 80
      target_port = 8501
      protocol    = "TCP"
    }

    type = "LoadBalancer"
  }
}