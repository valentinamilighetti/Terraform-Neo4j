resource "kubernetes_secret" "neo4j_credentials" {
  metadata {
    name      = "neo4j-auth-secret"
    namespace = var.namespace
  }

  data = {
    auth_string = "neo4j/${var.neo4j_password}"
  }

  type = "Opaque"
  
  depends_on = [kubernetes_namespace.neo4j_ns]
}