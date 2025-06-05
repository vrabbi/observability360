output "jaeger_loadbalancer_ip" {
  value = kubernetes_service.jaeger_lb.status[0].load_balancer[0].ingress[0].ip
}

output "grafana_loadbalancer_ip" {
  value = kubernetes_service.grafana.status[0].load_balancer[0].ingress[0].ip
}

output "online_store_ui_loadbalancer_ip" {
  value = kubernetes_service.online_store_ui.status[0].load_balancer[0].ingress[0].ip
}

output "otel_demo_app_loadbalancer_ip" {
  value       = data.kubernetes_service.frontend_proxy.status[0].load_balancer[0].ingress[0].ip
}