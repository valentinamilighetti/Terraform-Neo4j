resource "kubernetes_storage_class" "manual" {
  metadata {
    name = "manual"
  }
  storage_provisioner = "kubernetes.io/no-provisioner"
  volume_binding_mode = "WaitForFirstConsumer"
}

resource "kubernetes_persistent_volume" "neo4j_pv" {
  metadata {
    name = "neo4j-pv"
  }
  spec {
    capacity = {
      storage = "20Gi" 
    }
    
    access_modes = ["ReadWriteOnce"]
    
    persistent_volume_source {
      host_path {
        path = "/mnt/data/neo4j"
        type = "DirectoryOrCreate"
      }
    }
    
    storage_class_name = kubernetes_storage_class.manual.metadata[0].name
    
    node_affinity {
      required {
        node_selector_term {
          match_expressions {
            key      = "kubernetes.io/hostname"
            operator = "In"
            values   = [var.worker_node_name]
          }
        }
      }
    }
  }
  
  depends_on = [kubernetes_namespace.neo4j_ns]
}