resource "kubernetes_namespace" "cadvisor" {
  metadata {
    name = "cadvisor"
  }
}

resource "helm_release" "cadvisor" {
  name       = "cadvisor"
  namespace  = kubernetes_namespace.cadvisor.metadata[0].name
  repository = "oci://registry-1.docker.io/bitnamicharts"
  chart      = "cadvisor"
  version    = "0.1.4"
  values = [
    yamlencode({
      resourcesPreset = "none"
      service = {
        type = "ClusterIP"
      }
    })
  ]
}