output "namespace" {
  value = kubernetes_namespace.monitoring.metadata[0].name
}

output "grafana_port_forward_command" {
  description = "Run this to access Grafana at http://localhost:3001"
  value       = "kubectl port-forward -n ${var.namespace} svc/kube-prometheus-stack-grafana 3001:80"
}

output "prometheus_port_forward_command" {
  description = "Run this to access the Prometheus UI at http://localhost:9090"
  value       = "kubectl port-forward -n ${var.namespace} svc/kube-prometheus-stack-prometheus 9090:9090"
}

output "grafana_admin_user" {
  value = "admin"
}

output "grafana_admin_password" {
  value     = var.grafana_admin_password
  sensitive = true
}
