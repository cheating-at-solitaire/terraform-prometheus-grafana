resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = var.namespace
  }
}

resource "helm_release" "kube_prometheus_stack" {
  name       = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.chart_version
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  # Local/dev friendly settings - don't wait forever, don't fail
  # the whole apply if one pod is slow to schedule.
  timeout       = 600
  wait          = true
  wait_for_jobs = true

  values = [
    templatefile("${path.module}/values.yaml.tpl", {
      grafana_admin_password = var.grafana_admin_password
      grafana_service_type   = var.grafana_service_type
      storage_size           = var.prometheus_storage_size
    }),
    yamlencode({
      alertmanager = {
        alertmanagerSpec = {
          # you can leave this empty or add resource limits if you want
        }
        config = local.alertmanager_config # reuses the same local defined in alertmanager.tf
      }
    })
  ]
}

