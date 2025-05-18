output "jaeger_loadbalancer_ip" {
  value = kubernetes_service.jaeger_lb.status[0].load_balancer[0].ingress[0].ip
}

output "grafana_loadbalancer_ip" {
  value = kubernetes_service.grafana.status[0].load_balancer[0].ingress[0].ip
}

output "chess_white_agent_loadbalancer_ip" {
  value = kubernetes_service.chess_white_agent.status[0].load_balancer[0].ingress[0].ip
}

output "chess_black_agent_loadbalancer_ip" {
  value = kubernetes_service.chess_black_agent.status[0].load_balancer[0].ingress[0].ip
}

output "opentelemetry_collector_loadbalancer_ip" {
  value = kubernetes_service.otel_collector_lb.status[0].load_balancer[0].ingress[0].ip
}