##############################################
# Loki - log aggregation (single-binary mode)
##############################################

resource "kubernetes_namespace" "loki" {
  metadata {
    name = "loki"
  }
}

resource "helm_release" "loki" {
  name       = "loki"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = "6.9.0" # pin a version; check for newer at https://github.com/grafana/loki/releases
  namespace  = kubernetes_namespace.loki.metadata[0].name

  values = [
    yamlencode({
      loki = {
        auth_enabled = false

        commonConfig = {
          replication_factor = 1
        }

        storage = {
          type = "filesystem"
        }

        # Filesystem-backed schema - fine for a home lab / single node.
        # If you outgrow this, swap storage.type to s3/gcs and update schemaConfig.
        schemaConfig = {
          configs = [
            {
              from         = "2024-01-01"
              store        = "tsdb"
              object_store = "filesystem"
              schema       = "v13"
              index = {
                prefix = "index_"
                period = "24h"
              }
            }
          ]
        }
      }

      # Single-binary deployment: everything (ingester, querier, etc.) in one pod.
      # This is the right mode for a home lab - the microservices mode is for
      # horizontally scaling in production.
      deploymentMode = "SingleBinary"

      singleBinary = {
        replicas = 1
        persistence = {
          enabled      = true
          size         = "20Gi" # adjust to what your cluster's storage class can give
          storageClass = null   # null = use cluster default; set explicitly if needed
        }
        resources = {
          requests = { cpu = "200m", memory = "256Mi" }
          limits   = { cpu = "1", memory = "1Gi" }
        }
      }

      # Disable the components that only matter in microservices/scalable mode
      backend  = { replicas = 0 }
      read     = { replicas = 0 }
      write    = { replicas = 0 }
      ingester = { replicas = 0 }
      querier  = { replicas = 0 }

      # Basic retention so your disk doesn't fill up silently
      limits_config = {
        retention_period = "168h" # 7 days; raise if you have the disk for it
      }

      compactor = {
        retention_enabled = true
      }

      # The chart's built-in gateway (nginx) fronting Loki - fine to leave default
      gateway = {
        enabled = true
      }
    })
  ]
}

##############################################
# Grafana Alloy - ships container logs to Loki
# (Promtail's successor; DaemonSet, one per node)
##############################################

resource "helm_release" "alloy" {
  name       = "alloy"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "alloy"
  version    = "0.12.0" # pin a version; check for newer at https://github.com/grafana/alloy
  namespace  = kubernetes_namespace.loki.metadata[0].name

  depends_on = [helm_release.loki]

  values = [
    yamlencode({
      alloy = {
        configMap = {
          content = <<-EOT
            // Discover pods on this node and read their container logs
            discovery.kubernetes "pods" {
              role = "pod"
            }

            discovery.relabel "pods" {
              targets = discovery.kubernetes.pods.targets

              rule {
                source_labels = ["__meta_kubernetes_namespace"]
                target_label  = "namespace"
              }
              rule {
                source_labels = ["__meta_kubernetes_pod_name"]
                target_label  = "pod"
              }
              rule {
                source_labels = ["__meta_kubernetes_pod_container_name"]
                target_label  = "container"
              }
            }

            loki.source.kubernetes "pods" {
              targets    = discovery.relabel.pods.output
              forward_to = [loki.write.default.receiver]
            }

            loki.write "default" {
              endpoint {
                url = "http://loki-gateway.loki.svc.cluster.local/loki/api/v1/push"
              }
            }
          EOT
        }
      }
    })
  ]
}

##############################################
# Grafana datasource - wire Loki into Grafana
# Adjust namespace/release name to match your existing Grafana install
##############################################

resource "kubernetes_config_map" "loki_datasource" {
  metadata {
    name      = "loki-datasource"
    namespace = "monitoring" # <-- change to whatever namespace your Grafana lives in
    labels = {
      # This label is what kube-prometheus-stack's Grafana sidecar watches for.
      # If your Grafana wasn't deployed via kube-prometheus-stack, add the
      # datasource directly in your existing Grafana Terraform/values instead.
      grafana_datasource = "1"
    }
  }

  data = {
    "loki-datasource.yaml" = yamlencode({
      apiVersion = 1
      datasources = [
        {
          name      = "Loki"
          type      = "loki"
          access    = "proxy"
          url       = "http://loki-gateway.loki.svc.cluster.local"
          isDefault = false
        }
      ]
    })
  }
}

