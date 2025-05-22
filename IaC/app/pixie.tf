resource "kubernetes_namespace" "pixie" {
  metadata {
    name = "pl"
  }
}

resource "helm_release" "pixie" {
  name       = "pixie"
  namespace  = kubernetes_namespace.pixie.metadata[0].name
  repository = "https://artifacts.px.dev/helm_charts/operator"
  chart      = "pixie-operator-chart"
  values = [
    yamlencode({
      cloudAddr = "getcosmic.ai:443"
      deployKey = var.pixie_deployment_key
      clusterName = "${var.base_name}-aks"
    })
  ]
}