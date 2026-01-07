resource "kubernetes_service" "neo4j" {
  metadata {
    name      = "neo4j"
    namespace = var.namespace
  }

  spec {
    selector = {
      app = "neo4j"
    }

    port {
      name        = "http"
      port        = 7474
      target_port = 7474
      node_port   = 30074  
    }

    port {
      name        = "bolt"
      port        = 7687
      target_port = 7687
      node_port   = 30687  
    }

    type = "NodePort" 
  }
  
  depends_on = [kubernetes_namespace.neo4j_ns]
}