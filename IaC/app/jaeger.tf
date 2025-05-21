locals {
  jaeger_directory_path = "../../jaeger"

  jaeger_plugin_directory_path   = "${local.jaeger_directory_path}/plugin"
  jaeger_kusto_plugin_image_name = "${var.base_name}-jaeger-kusto-plugin"

  jaeger_kusto_plugin_dns_label      = "${var.base_name}-jaeger-plugin"
  jaeger_kusto_plugin_clusterip_name = "jaeger-plugin"

  jaeger_dns_label      = "${var.base_name}-jaeger"
  jaeger_clusterip_name = "jaeger-clusterip"
  jaeger_image_name     = "jaegertracing/all-in-one:1.55"
}

# Jaeger Identity
resource "azuread_application" "jaeger" {
  display_name = "jaeger"
  owners       = [data.azuread_client_config.current.object_id]
}

resource "azuread_service_principal" "jaeger" {
  client_id                    = azuread_application.jaeger.client_id
  app_role_assignment_required = false
  owners                       = [data.azuread_client_config.current.object_id]
}

resource "azuread_service_principal_password" "jaeger" {
  service_principal_id = azuread_service_principal.jaeger.id
}

resource "azurerm_kusto_database_principal_assignment" "jaeger" {
  name                = "KustoJaegerPrincipalAssignment"
  resource_group_name = data.azurerm_resource_group.demo.name
  cluster_name        = data.azurerm_kusto_cluster.demo.name
  database_name       = data.azurerm_kusto_database.otel.name

  tenant_id      = data.azuread_client_config.current.tenant_id
  principal_id   = azuread_application.jaeger.client_id
  principal_type = "App"
  role           = "Viewer"

  depends_on = [azuread_service_principal_password.jaeger]
}

# Jaeger Plugin Config
resource "local_file" "jaeger_kusto_config" {
  filename = "${path.cwd}/${local.jaeger_plugin_directory_path}/jaeger-kusto-config.json"
  content = templatefile("${path.cwd}/${local.jaeger_plugin_directory_path}/jaeger-kusto-config.json.tftpl", {
    adx_cluster_uri = data.azurerm_kusto_cluster.demo.uri,
    adx_database    = data.azurerm_kusto_database.otel.name,
    application_id  = azuread_service_principal.jaeger.client_id,
    application_key = azuread_service_principal_password.jaeger.value,
    tenant_id       = data.azuread_client_config.current.tenant_id
  })
}

resource "azurerm_container_registry_agent_pool" "demo" {
  name                    = "demo"
  resource_group_name     = data.azurerm_resource_group.demo.name
  location                = data.azurerm_resource_group.demo.location
  container_registry_name = data.azurerm_container_registry.demo.name
}

# Jaeger Plugin Image
resource "azurerm_container_registry_task" "jaeger_plugin" {
  name                 = "jaeger-kusto-plugin-task"
  container_registry_id = data.azurerm_container_registry.demo.id
  platform {
    os      = "Linux"
    architecture = "amd64"
  }
  docker_step {
    dockerfile_path = "Dockerfile"
    context_path       = "https://github.com/vrabbi/observability360#main:jaeger/plugin"
    image_names      = [local.jaeger_kusto_plugin_image_name]
    context_access_token = var.github_token
  }
}

resource "azurerm_container_registry_task_schedule_run_now" "jaeger_plugin" {
  container_registry_task_id = azurerm_container_registry_task.jaeger_plugin.id
}

# Jaeger Kubernetes Resources
resource "kubernetes_namespace" "jaeger" {
  metadata {
    name = "jaeger"
  }
}

resource "kubernetes_secret" "jaeger_plugin_config" {
  metadata {
    name      = "jaeger-plugin-config"
    namespace = kubernetes_namespace.jaeger.metadata[0].name
  }

  data = {
    "jaeger-kusto-config.json" = base64encode(
      templatefile("${path.cwd}/${local.jaeger_plugin_directory_path}/jaeger-kusto-config.json.tftpl", {
        adx_cluster_uri = data.azurerm_kusto_cluster.demo.uri,
        adx_database    = data.azurerm_kusto_database.otel.name,
        application_id  = azuread_service_principal.jaeger.client_id,
        application_key = azuread_service_principal_password.jaeger.value,
        tenant_id       = data.azuread_client_config.current.tenant_id
      })
    )
  }

  type = "Opaque"
}

#resource "kubernetes_deployment" "jaeger_plugin" {
#  metadata {
#    name      = "jaeger-plugin"
#    namespace = kubernetes_namespace.jaeger.metadata[0].name
#  }

#  spec {
#    replicas = 1
#
#    selector {
#      match_labels = {
#        app = "jaeger-plugin"
#      }
#    }
#
#    template {
#      metadata {
#        labels = {
#          app = "jaeger-plugin"
#        }
#      }
#
#      spec {
#        volume {
#          name = "plugin-config"
#          secret {
#            secret_name = kubernetes_secret.jaeger_plugin_config.metadata[0].name
#          }
#        }
#        container {
#          volume_mount {
#            name       = "plugin-config"
#            mount_path = "/etc/jaeger-plugin"
#            read_only  = true
#          }
#          name  = "jaeger-plugin"
#          image = local.jaeger_kusto_plugin_image_name
#          resources {
#            limits = {
#              cpu    = "1"
#              memory = "2Gi"
#            }
#            requests = {
#              cpu    = "0.5"
#              memory = "1Gi"
#            }
#          }
#          port {
#            container_port = 6060
#            protocol       = "TCP"
#          }
#          port {
#            container_port = 8989
#            protocol       = "TCP"
#          }
#          env {
#            name  = "JAEGER_AGENT_HOST"
#            value = "${local.jaeger_clusterip_name}.${kubernetes_namespace.jaeger.metadata[0].name}.svc.cluster.local"
#          }
#          env {
#            name  = "JAEGER_AGENT_PORT"
#            value = "6831"
#          }
#        }
#      }
#    }
#  }
#}

resource "kubernetes_service" "jaeger_plugin" {
  metadata {
    name      = local.jaeger_kusto_plugin_clusterip_name
    namespace = kubernetes_namespace.jaeger.metadata[0].name
  }

  spec {
    selector = {
      app = "jaeger-plugin"
    }

    port {
      name        = "port-6060"
      port        = 6060
      target_port = 6060
      protocol    = "TCP"
    }

    port {
      name        = "port-8989"
      port        = 8989
      target_port = 8989
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }
}


#resource "kubernetes_deployment" "jaeger" {
#  metadata {
#    name      = "jaeger"
#    namespace = kubernetes_namespace.jaeger.metadata[0].name
#  }
#
#  spec {
#    replicas = 1
#
#    selector {
#      match_labels = {
#        app = "jaeger"
#      }
#    }
#
#    template {
#      metadata {
#        labels = {
#          app = "jaeger"
#        }
#      }
#
#      spec {
#        container {
#          name  = "jaeger"
#          image = local.jaeger_image_name
#          resources {
#            limits = {
#              cpu    = "2"
#              memory = "4Gi"
#            }
#            requests = {
#              cpu    = "1"
#              memory = "2Gi"
#            }
#          }
#          port {
#            container_port = 6831
#            protocol       = "UDP"
#          }
#          port {
#            container_port = 6832
#            protocol       = "UDP"
#          }
#          port {
#            container_port = 5778
#            protocol       = "TCP"
#          }
#          port {
#            container_port = 16686
#            protocol       = "TCP"
#          }
#          port {
#            container_port = 14268
#            protocol       = "TCP"
#          }
#          env {
#            name  = "SPAN_STORAGE_TYPE"
#            value = "grpc-plugin"
#          }
#          env {
#            name  = "GRPC_STORAGE_SERVER"
#            value = "${local.jaeger_kusto_plugin_clusterip_name}.${kubernetes_namespace.jaeger.metadata[0].name}.svc.cluster.local:8989"
#          }
#          env {
#            name  = "GRPC_STORAGE_CONNECTION_TIMEOUT"
#            value = "60s"
#          }
#          env {
#            name  = "GRPC_STORAGE_TLS_ENABLED"
#            value = "false"
#          }
#        }
#      }
#    }
#  }
#}

resource "kubernetes_service" "jaeger_clusterip" {
  metadata {
    name      = local.jaeger_clusterip_name
    namespace = kubernetes_namespace.jaeger.metadata[0].name
  }

  spec {
    selector = {
      app = "jaeger"
    }
    port {
      name        = "port-6831"
      port        = 6831
      target_port = 6831
      protocol    = "UDP"
    }
    port {
      name        = "port-6832"
      port        = 6832
      target_port = 6832
      protocol    = "UDP"
    }
    port {
      name        = "port-5778"
      port        = 5778
      target_port = 5778
      protocol    = "TCP"
    }
    port {
      name        = "port-16686"
      port        = 16686
      target_port = 16686
      protocol    = "TCP"
    }
    port {
      name        = "port-14268"
      port        = 14268
      target_port = 14268
      protocol    = "TCP"
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_service" "jaeger_lb" {
  metadata {
    name      = "jaeger-lb"
    namespace = kubernetes_namespace.jaeger.metadata[0].name
  }

  spec {
    selector = {
      app = "jaeger"
    }

    port {
      port        = 80
      target_port = 16686
      protocol    = "TCP"
    }

    type = "LoadBalancer"
  }
}