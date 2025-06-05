resource "kubernetes_namespace" "oteldemoapp" {
  metadata {
    name = "otel-demo"
  }
}

resource "helm_release" "oteldemoapp" {
  name       = "otel-demo-app"
  namespace  = kubernetes_namespace.oteldemoapp.metadata[0].name
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-demo"

  values = [
    yamlencode({
      components = {
        frontend-proxy = {
          service = {
            type = "LoadBalancer"
          }
        }
      }
      jaeger = {
        enabled = false
      }
      prometheus = {
        enabled = true
      }
      grafana = {
        enabled = false
      }
      opensearch = {
        enabled = false
      }
      opentelemetry-collector = {
        enabled = true
        resources = {
          limits = {
            memory = "500Mi"
          }
        }
        config = {
          exporters = {
            otlp = {
              endpoint = "otel-collector.opentelemetry:4317"
              tls = {
                insecure = true
              }
            }
          }
          service = {
            pipelines = {
              traces = {
                receivers  = ["otlp", "jaeger", "zipkin"]
                processors = ["k8sattributes", "memory_limiter", "resource", "transform", "batch"]
                exporters  = ["otlp", "spanmetrics"]
              }
              metrics = {
                receivers  = ["httpcheck/frontend-proxy", "redis", "otlp", "spanmetrics"]
                processors = ["k8sattributes", "memory_limiter", "resource", "batch"]
                exporters  = ["otlp"]
              }
              logs = {
                receivers  = ["otlp"]
                processors = ["k8sattributes", "memory_limiter", "resource", "batch"]
                exporters  = ["otlp"]
              }
            }
            telemetry = {
              metrics = {
                level = "detailed"
                readers = [
                  {
                    periodic = {
                      interval = 10000
                      timeout  = 5000
                      exporter = {
                        otlp = {
                          protocol = "grpc"
                          endpoint = "otel-collector:4318"
                        }
                      }
                    }
                  }
                ]
              }
            }
          }
        }
      }
    })
  ]
}

data "kubernetes_service" "frontend_proxy" {
  metadata {
    name      = "frontend-proxy"
    namespace = kubernetes_namespace.oteldemoapp.metadata[0].name
  }

  depends_on = [helm_release.oteldemoapp]
}