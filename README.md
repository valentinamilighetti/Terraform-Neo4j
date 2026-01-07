# Infrastructure as Code per la distribuzione di Neo4j su Kubernetes
## Introduzione
Questo progetto implementa un’infrastruttura **Infrastructure as Code (IaC)** per il deploy automatizzato di un database a grafo **Neo4j** su un cluster **Kubernetes**.  
L’obiettivo è automatizzare la configurazione e la distribuzione dell’applicazione utilizzando il software **Terraform**.
## Prerequisiti
- openssh-server per l'accesso in remoto e chiavi SSH
- Kubernetes
## Cluster 
Il cluster Kubernetes è costituito da due macchine virtuali Lubuntu 24 connesse tramite una rete con NAT gestita da VirtualBox (`192.168.43.0/24`):
- nodo 1 (**master**): `192.168.43.10`
- nodo 2 (**worker**): `192.168.43.11`
## Installazione di Terraform
Sul nodo master, eseguire i seguenti comandi:
```bash
wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list

sudo apt update && sudo apt install terraform
```
## Deploy del progetto Terraform
Il deploy dell’infrastruttura è gestito tramite Terraform, che utilizza file .tf per descrivere in modo dichiarativo le risorse da creare su Kubernetes.

Di seguito sono descritti i principali file utilizzati nel progetto.
### Variabili
Il file `variables.tf` definisce la struttura e le proprietà delle variabili utilizzate:
```bash
variable "namespace" {
  description = "Namespace Kubernetes per Neo4j"
  type        = string
  default     = "neo4j-app"
}

variable "neo4j_password" {
  description = "Password per l'utente Neo4j"
  type        = string
  sensitive   = true
  default     = "*****"
}

variable "neo4j_storage" {
  description = "Dimensione dello storage (PVC) per Neo4j"
  type        = string
  default     = "10Gi"
}

variable "worker_node_name" {
  description = "Nome del nodo worker dove montare i dati"
  type        = string
  default     = "node2" 
}
```
`terraform.tfvars` contiene i valori assegnati alle variabili utilizzate per parametrizzare il deploy:
```bash
worker_node_name = "node2"
namespace        = "neo4j-app"
neo4j_password   = "*****"  
neo4j_storage    = "10Gi"
```
### `providers.tf`
Definisce i requisiti di Terraform e configura il provider Kubernetes utilizzato per interagire con il cluster.
```bash
terraform {
  required_version = ">= 1.0"
  
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"
}
```
### `namespace.tf`
Definisce il namespace Kubernetes dedicato al deploy dell’applicazione Neo4j.
```bash
resource "kubernetes_namespace" "neo4j_ns" {
  metadata {
    name = var.namespace
  }
}
```
### `secrets.tf`
Definisce il Secret Kubernetes utilizzato per gestire in modo sicuro le credenziali di accesso al database Neo4j.
```bash
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
```
### `storage.tf`
Definisce le risorse di storage persistente necessarie al funzionamento di Neo4j, configurando una StorageClass e un PersistentVolume per la memorizzazione dei dati.
```bash
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
```
Lo storage viene vincolato al nodo worker specificato tramite `node_affinity`, garantendo che i dati persistenti di Neo4j risiedano sul nodo 2.
### `neo4j-statefulset.tf`
Definisce lo **StatefulSet Kubernetes** responsabile del deploy del database Neo4j, configurando il pod, le risorse, le variabili d’ambiente e il collegamento allo storage persistente.
```bash
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
```
### `neo4j-service.tf`
Definisce il **Service Kubernetes** che espone il database Neo4j all’interno del cluster e verso l’esterno tramite NodePort.
```bash
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
```
### Deploy
Per eseguire il deploy dell’intero progetto, seguire questi passaggi sul nodo master:

```bash
# Inizializza Terraform e scarica i provider
terraform init

# Applica la configurazione dichiarativa per creare tutte le risorse
terraform apply
```
Per accedere al servizio basta collegarsi a http://192.168.43.11:30074 e inserire le credenziali di accesso.
## Esempio di utilizzo 
È stato utilizzato il dataset NORTHWIND, caricato nel nodo 2 con i seguenti comandi dall'interfaccia neo4j:
```cypher
# Carica Prodotti
LOAD CSV WITH HEADERS FROM "https://data.neo4j.com/northwind/products.csv" AS row
MERGE (n:Product {productID: row.productID})
SET n.name = row.productName, n.unitPrice = toFloat(row.unitPrice);

# Carica Categorie
LOAD CSV WITH HEADERS FROM "https://data.neo4j.com/northwind/categories.csv" AS row
MERGE (n:Category {categoryID: row.categoryID})
SET n.categoryName = row.categoryName, n.description = row.description;

# Carica Fornitori
LOAD CSV WITH HEADERS FROM "https://data.neo4j.com/northwind/suppliers.csv" AS row
MERGE (n:Supplier {supplierID: row.supplierID})
SET n.companyName = row.companyName;

# Crea Relazioni (Prodotti appartengono a Categorie)
LOAD CSV WITH HEADERS FROM "https://data.neo4j.com/northwind/products.csv" AS row
MATCH (p:Product {productID: row.productID})
MATCH (c:Category {categoryID: row.categoryID})
MERGE (p)-[:PART_OF]->(c);

# Crea Relazioni (Fornitori forniscono Prodotti)
LOAD CSV WITH HEADERS FROM "https://data.neo4j.com/northwind/products.csv" AS row
MATCH (p:Product {productID: row.productID})
MATCH (s:Supplier {supplierID: row.supplierID})
MERGE (s)-[:SUPPLIES]->(p);
```
### Esempio di Cypher query 
![esempio di query](query.png)