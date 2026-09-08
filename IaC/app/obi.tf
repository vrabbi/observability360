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

  # The TCP stat metrics default to reporting src.address and dst.address, which is one series
  # per IP pair. Aggregate at the workload level instead.
  obi_tcp_stat_attributes = [
    "k8s.src.owner.name",
    "k8s.src.namespace",
    "k8s.dst.owner.name",
    "k8s.dst.namespace",
    "k8s.cluster.name",
    "host.id",
  ]

  # Infrastructure workloads whose flows would otherwise dominate the network metrics.
  obi_network_owner_exclusions = "{kube*,ksm*,cadvisor*,*prometheus*,*grafana*,*jaeger*,*otel-collector*,*ebpf-instrument*}"

  obi_metric_features = [
    "application",
    "application_service_graph",
    "network",
    "network_flow_packets",
    # stats_tcp_io is deliberately left out: it fires on every tcp_sendmsg and
    # tcp_cleanup_rbuf, unlike the other stat metrics which fire on close, failure or
    # retransmit only.
    "stats_tcp_rtt",
    "stats_tcp_failed_connections",
    "stats_tcp_retransmits",
  ]

  # HTTP request header capture, used for per-request cost attribution ("unit economics").
  # The captured headers are attached to spans only, as http.request.header.<name>, and land in
  # the TraceAttributes column of the OTELTraces table in ADX. The default policy excludes
  # everything, so only the headers listed in var.obi_capture_request_headers are ever read.
  # Set that variable to [] to turn header capture off entirely.
  obi_header_capture_config = length(var.obi_capture_request_headers) == 0 ? {} : {
    ebpf = {
      # The default HTTP capture window is too small to reach the header block.
      buffer_sizes = {
        http = var.obi_http_capture_bytes
      }
      payload_extraction = {
        http = {
          enrichment = {
            enabled = true
            policy = {
              default_action = {
                headers = "exclude"
                body    = "exclude"
              }
            }
            rules = [
              {
                action = "include"
                type   = "headers"
                scope  = "request"
                match = {
                  patterns = var.obi_capture_request_headers
                }
              },
            ]
          }
        }
      }
    }
  }

  obi_base_config = {
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
      features = local.obi_metric_features
    }

    # Application level instrumentation is scoped to the demo workloads, network flows and TCP
    # stats are collected cluster wide. OBI skips processes that already export OTLP metrics or
    # traces themselves, so the SDK instrumented services are not double counted.
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
        "obi.stat.tcp.rtt" = {
          include = local.obi_tcp_stat_attributes
        }
        "obi.stat.tcp.retransmits" = {
          include = local.obi_tcp_stat_attributes
        }
        "obi.stat.tcp.failed.connections" = {
          include = local.obi_tcp_stat_attributes
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

resource "kubernetes_namespace" "obi" {
  metadata {
    name = local.obi_namespace_name
  }
}

# OpenTelemetry eBPF Instrumentation (OBI), the upstream successor of Grafana Beyla.
# Runs as a privileged DaemonSet and exports zero-code application metrics/traces, service graph
# metrics, cluster wide network flow metrics and TCP statistics to the demo's OTEL collector.
resource "helm_release" "obi" {
  name       = "obi"
  namespace  = kubernetes_namespace.obi.metadata[0].name
  chart      = "opentelemetry-ebpf-instrumentation"
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
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
        data = merge(local.obi_base_config, local.obi_header_capture_config)
      }
    })
  ]

  depends_on = [
    kubernetes_daemonset.otel_collector,
  ]
}
