locals {
  chess_namespace_name = "chess"

  chess_directory_path            = "../../chess"
  chess_docker_images_name_prefix = "${var.base_name}-ai-chess"
  chess_otel_directory_path       = "${local.chess_directory_path}/otel"
}

resource "kubernetes_namespace" "chess" {
  metadata {
    name = local.chess_namespace_name
  }
}