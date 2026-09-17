variable "kubeconfig_path" {
  description = "Path to your local kubeconfig file"
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "Kubeconfig context to use (leave null to use current-context)"
  type        = string
  default     = null
}

variable "namespace" {
  description = "Namespace to install the monitoring stack into"
  type        = string
  default     = "monitoring"
}

variable "chart_version" {
  description = "Version of the kube-prometheus-stack Helm chart"
  type        = string
  default     = "62.7.0" # pin a known-good version; bump deliberately
}

variable "grafana_admin_password" {
  description = "Admin password for Grafana"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "grafana_service_type" {
  description = "Kubernetes Service type for Grafana (ClusterIP, NodePort, LoadBalancer)"
  type        = string
  default     = "ClusterIP"
}

variable "prometheus_storage_size" {
  description = "PVC size for Prometheus data. Set to null to disable persistence (fine for local/dev)."
  type        = string
  default     = null
}
