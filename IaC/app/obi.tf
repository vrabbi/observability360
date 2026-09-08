locals {
  obi_namespace_name = "obi"
  obi_otlp_endpoint  = "http://otel-collector.${kubernetes_namespace.opentelemetry.metadata[0].name}.svc.cluster.local:4317"

  # Attributes kept on the OBI network flow metrics. Keeping the list explicit bounds the
  # cardinality of the metric and gives the Grafana dashboards a stable series key
  # (host.id identifies the node that observed the flow). Note that host.id is only kept as a
  # resource attribute as long as it is part of this include list.
  obi_network_flow_attributes = [
    "k8s.src.owner.name",
    "k8s.src.namespace",
    "k8s.dst.owner.name",
    "k8s.dst.namespace",
    "k8s.cluster.name",
    "host.id",
  ]

  # Infrastructure workloads whose flows would otherwise dominate the network metrics.
  obi_network_owner_exclusions = "{kube*,ksm*,cadvisor*,*prometheus*,*grafana*,*jaeger*,*otel-collector*,*ebpf-instrument*}"
}

resource "kubernetes_namespace" "obi" {
  metadata {
    name = local.obi_namespace_name
  }
}

# OpenTelemetry eBPF Instrumentation (OBI), the upstream successor of Grafana Beyla.
# Runs as a privileged DaemonSet and exports zero-code application metrics/traces and
# cluster wide network flow metrics straight to the demo's OTEL collector.
resource "helm_release" "obi" {
  name       = "obi"
  namespace  = kubernetes_namespace.obi.metadata[0].name
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-ebpf-instrumentation"
  version    = "0.13.0"

  values = [
    yamlencode({
      # A single shared watcher of the Kubernetes API instead of one informer per node.
      k8sCache = {
        replicas = 1
      }

      resources = {
        requests = {
          cpu    = "100m"
          memory = "200Mi"
        }
        limits = {
          memory = "500Mi"
        }
      }

      config = {
        data = {
          # Reuse the collector that already ships the rest of the demo telemetry to ADX.
          otel_metrics_export = {
            endpoint = local.obi_otlp_endpoint
            protocol = "grpc"
            interval = "30s"
          }
          otel_traces_export = {
            endpoint = local.obi_otlp_endpoint
            protocol = "grpc"
          }
          # The chart defaults to a Prometheus scrape endpoint, we only export OTLP.
          prometheus_export = {
            port = 0
          }

          metrics = {
            features = ["application", "network", "network_flow_packets"]
          }

          # Application level instrumentation is scoped to the demo workloads, network flows
          # are collected cluster wide. OBI skips processes that already export OTLP metrics
          # or traces themselves, so the SDK instrumented services are not double counted.
          discovery = {
            instrument = [
              { k8s_namespace = local.online_store_namespace_name },
              { k8s_namespace = kubernetes_namespace.oteldemoapp.metadata[0].name },
            ]
            exclude_instrument = [
              { exe_path = "{*ebpf-instrument*,*otelcol*}" },
            ]
          }

          # socket_filter works with every CNI, the tc based source conflicts with CNIs that
          # install their own tc programs.
          network = {
            source = "socket_filter"
          }

          attributes = {
            kubernetes = {
              enable       = true
              cluster_name = "${var.base_name}-aks"
            }
            select = {
              "obi.network.flow.bytes" = {
                include = local.obi_network_flow_attributes
              }
              "obi.network.flow.packets" = {
                include = local.obi_network_flow_attributes
              }
            }
          }

          filter = {
            network = {
              k8s_src_owner_name = {
                not_match = local.obi_network_owner_exclusions
              }
              k8s_dst_owner_name = {
                not_match = local.obi_network_owner_exclusions
              }
            }
          }

          routes = {
            unmatched = "heuristic"
          }
        }
      }
    })
  ]

  depends_on = [
    kubernetes_daemonset.otel_collector,
  ]
}
