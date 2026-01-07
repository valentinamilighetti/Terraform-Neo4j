resource "kubernetes_namespace" "neo4j_ns" {
  metadata {
    name = var.namespace
  }
}