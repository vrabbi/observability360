locals {
  grafana_image_name     = "${var.base_name}-grafana"
  grafana_directory_path = "../../grafana"
}

resource "time_rotating" "example" {
  rotation_days = 180
}

resource "azuread_application" "grafana_to_adx" {
  display_name = "grafana_to_adx"
  owners       = [data.azuread_client_config.current.object_id]

  password {
    display_name = "${var.base_name}-secret"
    start_date   = time_rotating.example.id
    end_date     = timeadd(time_rotating.example.id, "4320h")
  }
}

resource "azuread_service_principal" "grafana_to_adx" {
  client_id                    = azuread_application.grafana_to_adx.client_id
  app_role_assignment_required = false
  owners                       = [data.azuread_client_config.current.object_id]
}

resource "azurerm_kusto_database_principal_assignment" "grafana_to_adx" {
  name                = "GrafanaQueryToADX"
  resource_group_name = data.azurerm_resource_group.demo.name
  cluster_name        = data.azurerm_kusto_cluster.demo.name
  database_name       = data.azurerm_kusto_database.otel.name

  tenant_id      = data.azuread_client_config.current.tenant_id
  principal_id   = azuread_application.grafana_to_adx.client_id
  principal_type = "App"
  role           = "Viewer"
}

#resource "azurerm_role_assignment" "grafana_to_communication_service" {
#  scope                = azurerm_communication_service.demo.id
#  role_definition_name = azurerm_role_definition.communication_service_role.name
#  principal_id         = azuread_service_principal.grafana_to_adx.object_id
#  principal_type = "ServicePrincipal"
#}

resource "azuread_service_principal_password" "grafana_to_adx" {
  service_principal_id = azuread_service_principal.grafana_to_adx.id
  depends_on = [ azurerm_kusto_database_principal_assignment.grafana_to_adx ]
}
resource "kubernetes_secret" "adx_datasource" {
  metadata {
    name      = "adx-datasource"
    namespace = kubernetes_namespace.grafana.metadata[0].name
  }

  data = {
    "adx-datasource.yml" = templatefile("${path.cwd}/${local.grafana_directory_path}/provisioning/datasources/adx-datasource.yml.tftpl", {
      adx_fqdn              = data.azurerm_kusto_cluster.demo.uri
      adx_database          = data.azurerm_kusto_database.otel.name
      grafana_client_id     = azuread_application.grafana_to_adx.client_id
      grafana_client_secret = azuread_service_principal_password.grafana_to_adx.value
      tenant_id             = data.azuread_client_config.current.tenant_id
    })
  }

  type = "Opaque"
}

resource "kubernetes_secret" "grafana_ini" {
  metadata {
    name      = "grafana-ini"
    namespace = kubernetes_namespace.grafana.metadata[0].name
  }

  data = {
    "grafana.ini" = templatefile("${path.cwd}/${local.grafana_directory_path}/grafana.ini.tftpl", {
      user         = "${azurerm_communication_service.demo.name}|${azuread_application.grafana_to_adx.client_id}|${data.azuread_client_config.current.tenant_id}"
      password     = tolist(azuread_application.grafana_to_adx.password).0.value
      from_address = azurerm_email_communication_service_domain.demo.mail_from_sender_domain
    })
  }

  type = "Opaque"
}

resource "kubernetes_secret" "contact_group" {
  metadata {
    name      = "grafana-contact-group"
    namespace = kubernetes_namespace.grafana.metadata[0].name
  }

  data = {
    "contact_group.yml" = templatefile("${path.cwd}/${local.grafana_directory_path}/provisioning/alerting/contact_group.yml.tftpl", {
      email = var.email
    })
  }

  type = "Opaque"
}

resource "azurerm_container_registry_task" "grafana" {
  name                 = "grafana-task"
  container_registry_id = data.azurerm_container_registry.demo.id
  tags = {
    owner = var.email
  }
  platform {
    os      = "Linux"
    architecture = "amd64"
  }
  docker_step {
    dockerfile_path = "Dockerfile"
    context_path       = "https://github.com/vrabbi/observability360#main:grafana"
    image_names      = [local.grafana_image_name]
    context_access_token = var.github_token
  }
}

resource "azurerm_container_registry_task_schedule_run_now" "grafana" {
  container_registry_task_id = azurerm_container_registry_task.grafana.id
}

resource "kubernetes_namespace" "grafana" {
  metadata {
    name = "grafana"
  }
}

resource "kubernetes_deployment" "grafana" {
  depends_on = [
    azurerm_container_registry_task_schedule_run_now.grafana
  ]
  metadata {
    name      = "grafana"
    namespace = kubernetes_namespace.grafana.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "grafana"
      }
    }

    template {
      metadata {
        labels = {
          app = "grafana"
        }
      }

      spec {
        container {
          name  = "grafana"
          image = "${data.azurerm_container_registry.demo.login_server}/${local.grafana_image_name}"

          port {
            container_port = 3000
          }

          env {
            name  = "GF_INSTALL_PLUGINS"
            value = "grafana-opensearch-datasource,grafana-azure-data-explorer-datasource"
          }

          volume_mount {
            name       = "grafana-ini"
            mount_path = "/etc/grafana/grafana.ini"
            sub_path   = "grafana.ini"
            read_only  = true
          }

          volume_mount {
            name       = "adx-datasource"
            mount_path = "/etc/grafana/provisioning/datasources/adx-datasource.yml"
            sub_path   = "adx-datasource.yml"
            read_only  = true
          }

          volume_mount {
            name       = "contact-group"
            mount_path = "/etc/grafana/provisioning/alerting/contact_group.yml"
            sub_path   = "contact_group.yml"
            read_only  = true
          }
        }

        volume {
          name = "grafana-ini"
          secret {
            secret_name = kubernetes_secret.grafana_ini.metadata[0].name
          }
        }

        volume {
          name = "adx-datasource"
          secret {
            secret_name = kubernetes_secret.adx_datasource.metadata[0].name
          }
        }

        volume {
          name = "contact-group"
          secret {
            secret_name = kubernetes_secret.contact_group.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "grafana" {
  metadata {
    name      = "grafana"
    namespace = kubernetes_namespace.grafana.metadata[0].name
  }

  spec {
    selector = {
      app = "grafana"
    }

    port {
      port        = 80
      target_port = 3000
    }
    type = "LoadBalancer"
  }
}