locals {
  otel_collector_image_name              = "${var.base_name}-otel-collector:latest"
  opentelemetry_collector_directory_path = "../../opentelemetry-collector"
}

# OTEL Collector Identity
resource "azuread_application" "otel" {
  display_name = "otelcollector"
  owners       = [data.azuread_client_config.current.object_id]
}

resource "azuread_service_principal" "otel" {
  client_id                    = azuread_application.otel.client_id
  app_role_assignment_required = false
  owners                       = [data.azuread_client_config.current.object_id]
}

resource "azuread_service_principal_password" "otel" {
  service_principal_id = azuread_service_principal.otel.id
}

resource "azurerm_kusto_database_principal_assignment" "otel" {
  name                = "KustoPrincipalAssignment"
  resource_group_name = data.azurerm_resource_group.demo.name
  cluster_name        = data.azurerm_kusto_cluster.demo.name
  database_name       = data.azurerm_kusto_database.otel.name

  tenant_id      = data.azuread_client_config.current.tenant_id
  principal_id   = azuread_application.otel.client_id
  principal_type = "App"
  role           = "Ingestor"

  depends_on = [azuread_service_principal_password.otel]
}

# OTEL Collector Configuration
resource "local_file" "otel_collector_config" {
  filename = "${path.cwd}/${local.opentelemetry_collector_directory_path}/config.yaml"
  content = templatefile("${path.cwd}/${local.opentelemetry_collector_directory_path}/config.tftpl", {
    adx_cluster_uri = data.azurerm_kusto_cluster.demo.uri,
    application_id  = azuread_service_principal.otel.client_id,
    application_key = azuread_service_principal_password.otel.value,
    tenant_id       = data.azuread_client_config.current.tenant_id
  })
}

# OTEL Collector Kubernetes Resources
resource "kubernetes_namespace" "opentelemetry" {
  metadata {
    name = "opentelemetry"
  }
}

resource "kubernetes_service_account" "opentelemetry" {
  metadata {
    name      = "opentelemetry"
    namespace = kubernetes_namespace.opentelemetry.metadata[0].name
  }
}

resource "kubernetes_cluster_role" "opentelemetry" {
  metadata {
    name = "opentelemetry-read"
  }

  rule {
    api_groups = [""]
    resources  = ["*"]
    verbs      = ["get", "list", "watch"]
  }
}


resource "kubernetes_cluster_role_binding" "opentelemetry" {
  metadata {
    name = "opentelemetry-read"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "opentelemetry-read"
  }

  subject {
    kind      = "ServiceAccount"
    name      = "opentelemetry"
    namespace = kubernetes_namespace.opentelemetry.metadata[0].name
  }
}

resource "kubernetes_config_map" "collector_config" {
  metadata {
    name      = "collector-config"
    namespace = kubernetes_namespace.opentelemetry.metadata[0].name
  }

  data = {
    "config.yaml" = local_file.otel_collector_config.content
  }

  depends_on = [local_file.otel_collector_config]
}

resource "kubernetes_daemonset" "otel_collector" {
  metadata {
    name      = "otel-collector"
    namespace = kubernetes_namespace.opentelemetry.metadata[0].name
  }

  spec {
    selector {
      match_labels = {
        app = "otel-collector"
      }
    }

    template {
      metadata {
        labels = {
          app = "otel-collector"
        }
      }

      spec {
        service_account_name = kubernetes_service_account.opentelemetry.metadata[0].name
        container {
          name  = "otel-collector"
          image = "otel/opentelemetry-collector-contrib:0.120.0"
          resources {
            requests = {
              cpu    = "250m"
              memory = "500m"
            }
            limits = {
              cpu    = "500m"
              memory = "1Gi"
            }
            
          }

          port {
            container_port = 4317
            protocol       = "TCP"
          }

          port {
            container_port = 4318
            protocol       = "TCP"
          }

          volume_mount {
            name       = "collector-config"
            mount_path = "/etc/otelcol-contrib"
          }
          
          env {
            name = "K8S_NODE_NAME"
            value_from {
              field_ref {
                field_path = "spec.nodeName"
              }
            }
          }
        }
        volume {
          name = "collector-config"
          config_map {
            name = kubernetes_config_map.collector_config.metadata[0].name
            items {
              key  = "config.yaml"
              path = "config.yaml"
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "otel_collector" {
  metadata {
    name      = "otel-collector"
    namespace = kubernetes_namespace.opentelemetry.metadata[0].name
  }

  spec {
    selector = {
      app = "otel-collector"
    }

    port {
      name        = "grpc"
      port        = 4317
      target_port = 4317
      protocol    = "TCP"
    }

    port {
      name        = "http"
      port        = 4318
      target_port = 4318
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }
}