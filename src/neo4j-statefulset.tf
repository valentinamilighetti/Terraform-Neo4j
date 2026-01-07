resource "kubernetes_stateful_set" "neo4j" {
  metadata {
    name      = "neo4j"
    namespace = var.namespace
    labels = {
      app = "neo4j"
    }
  }

  spec {
    service_name = "neo4j"
    replicas     = 1

    selector {
      match_labels = {
        app = "neo4j"
      }
    }

    template {
      metadata {
        labels = {
          app = "neo4j"
        }
      }

      spec {
      	enable_service_links = false
        node_selector = {
          "kubernetes.io/hostname" = var.worker_node_name
        }
        
        security_context {
          fs_group = 7474 
        }
        
        init_container {
          name    = "fix-permissions"
          image   = "alpine:latest"
          command = ["/bin/sh", "-c"]
          args    = [
            "chown -R 7474:7474 /data && chmod 755 /data && echo 'Permissions fixed for Neo4j'"
          ]
          
          security_context {
            run_as_user = 0  
          }
          
          volume_mount {
            name       = "data"
            mount_path = "/data"
          }
        }

        container {
          name  = "neo4j"
          image = "neo4j:5"

          security_context {
            run_as_user  = 7474
            run_as_group = 7474
          }

          env {
            name = "NEO4J_AUTH"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.neo4j_credentials.metadata[0].name
                key  = "auth_string"
              }
            }
          }

          env {
            name  = "NEO4J_ACCEPT_LICENSE_AGREEMENT"
            value = "yes"
          }
          
          env {
            name  = "NEO4J_server_config_strict__validation_enabled"
            value = "false"
          }

          env {
            name  = "NEO4J_server_memory_pagecache_size"
            value = "1G"
          }
          
          env {
            name  = "NEO4J_server_memory_heap_initial__size"
            value = "1G"
          }
          
          env {
            name  = "NEO4J_server_memory_heap_max__size"
            value = "1G"
          }

          port {
            name           = "bolt"
            container_port = 7687
          }

          port {
            name           = "http"
            container_port = 7474
          }

          volume_mount {
            name       = "data"
            mount_path = "/data"
          }

          resources {
            requests = {
              memory = "2Gi"
              cpu    = "500m"
            }
            limits = {
              memory = "3Gi"
              cpu    = "1000m"
            }
          }
          
          readiness_probe {
            tcp_socket {
              port = 7687
            }
            initial_delay_seconds = 90  
            period_seconds        = 20
            failure_threshold     = 3
          }
          
          liveness_probe {
            tcp_socket {
              port = 7687
            }
            initial_delay_seconds = 120
            period_seconds        = 30
            failure_threshold     = 3
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "data"
      }

      spec {
        access_modes = ["ReadWriteOnce"]
        storage_class_name = kubernetes_storage_class.manual.metadata[0].name
        resources {
          requests = {
            storage = var.neo4j_storage
          }
        }
      }
    }
  }
  
  depends_on = [
    kubernetes_namespace.neo4j_ns,
    kubernetes_persistent_volume.neo4j_pv
  ]
  
  timeouts {
    create = "15m"
    update = "15m"
  }
}