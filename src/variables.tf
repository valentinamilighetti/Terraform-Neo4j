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