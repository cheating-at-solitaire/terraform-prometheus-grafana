##############################################################
# Alertmanager
#
# IMPORTANT: check first whether you already have this.
# If your Prometheus was installed via the kube-prometheus-stack
# Helm chart, Alertmanager is already deployed alongside it.
# Check with:
#   kubectl get pods -n <your-monitoring-namespace> | grep alertmanager
#
# If it's already there, skip the helm_release below entirely and
# jump straight to the alertmanager_config + PrometheusRule sections -
# just merge the "alertmanagerSpec" / "alertmanager" values block
# into your EXISTING kube-prometheus-stack helm_release resource
# instead of creating a new one.
##############################################################

# --- Only use this if Alertmanager is NOT already installed ---
resource "helm_release" "alertmanager" {
  count = var.deploy_standalone_alertmanager ? 1 : 0

  name       = "alertmanager"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "alertmanager"
  version    = "1.15.0"     # pin a version; check for newer at the chart repo
  namespace  = "monitoring" # match your existing Prometheus/Grafana namespace

  values = [
    yamlencode({
      replicaCount = 1

      config = local.alertmanager_config

      persistence = {
        enabled = true
        size    = "2Gi"
      }

      resources = {
        requests = { cpu = "100m", memory = "128Mi" }
        limits   = { cpu = "250m", memory = "256Mi" }
      }
    })
  ]
}

variable "deploy_standalone_alertmanager" {
  description = "Set to false if Alertmanager already came bundled with kube-prometheus-stack"
  type        = bool
  default     = true
}

##############################################################
# Alertmanager config - routing, grouping, and where alerts go
##############################################################

variable "ntfy_topic_url" {
  description = <<-EOT
    Full ntfy.sh topic URL to send alert notifications to, e.g.
    "https://ntfy.sh/your-homelab-alerts-xyz123". Pick a random/unguessable
    topic name since ntfy.sh topics are public unless you self-host.
    Subscribe to the same topic in the ntfy app (iOS/Android) or a browser
    tab at that URL to receive the notifications.
  EOT
  type        = string
  sensitive   = true
}

locals {
  alertmanager_config = {
    global = {
      resolve_timeout = "5m"
    }

    route = {
      receiver        = "ntfy-default"
      group_by        = ["alertname", "namespace"]
      group_wait      = "30s" # wait to see if related alerts arrive before first notification
      group_interval  = "5m"  # wait between notifications for new alerts in an existing group
      repeat_interval = "4h"  # don't re-notify about the same unresolved alert more than this often

      routes = [
        {
          # Example: route anything labeled severity=critical to the same
          # receiver but with faster repeat - add more routes as needed
          match           = { severity = "critical" }
          receiver        = "ntfy-default"
          repeat_interval = "1h"
        }
      ]
    }

    receivers = [
      {
        name = "ntfy-default"
        webhook_configs = [
          {
            # ntfy.sh accepts a plain POST body as the notification text.
            # Alertmanager's webhook_configs always sends its own JSON payload
            # rather than a custom template, so ntfy will show the raw JSON -
            # readable but not pretty. If you want cleanly formatted
            # notifications instead, ntfy has a dedicated Alertmanager
            # integration guide: https://docs.ntfy.sh/integrations/#alertmanager
            url           = var.ntfy_topic_url
            send_resolved = true
          }
        ]
      }
    ]

    inhibit_rules = [
      {
        # If a whole node is down, don't also page for every pod on it
        source_match    = { alertname = "NodeDown" }
        target_match_re = { alertname = ".*" }
        equal           = ["node"]
      }
    ]
  }
}

##############################################################
# Example Prometheus alert rules
# (Requires the Prometheus Operator CRDs - already installed
# if you're using kube-prometheus-stack)
##############################################################

resource "kubernetes_manifest" "starter_alert_rules" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"
    metadata = {
      name      = "homelab-starter-alerts"
      namespace = "monitoring" # match your Prometheus namespace
      labels = {
        # Match whatever label your Prometheus Operator's ruleSelector expects
        # (kube-prometheus-stack default is usually "release: <helm-release-name>")
        release = "kube-prometheus-stack"
      }
    }
    spec = {
      groups = [
        {
          name = "homelab.rules"
          rules = [
            {
              alert  = "NodeDown"
              expr   = "up{job=\"node-exporter\"} == 0"
              for    = "5m"
              labels = { severity = "critical" }
              annotations = {
                summary     = "Node {{ $labels.instance }} is down"
                description = "{{ $labels.instance }} has been unreachable for 5+ minutes."
              }
            },
            {
              alert  = "PodCrashLooping"
              expr   = "increase(kube_pod_container_status_restarts_total[15m]) > 3"
              for    = "5m"
              labels = { severity = "warning" }
              annotations = {
                summary     = "Pod {{ $labels.namespace }}/{{ $labels.pod }} is crash-looping"
                description = "Container {{ $labels.container }} has restarted more than 3 times in 15 minutes."
              }
            },
            {
              alert  = "HighDiskUsage"
              expr   = "100 - ((node_filesystem_avail_bytes{fstype!=\"tmpfs\"} * 100) / node_filesystem_size_bytes{fstype!=\"tmpfs\"}) > 85"
              for    = "10m"
              labels = { severity = "warning" }
              annotations = {
                summary     = "Disk usage above 85% on {{ $labels.instance }}"
                description = "Filesystem {{ $labels.mountpoint }} on {{ $labels.instance }} is over 85% full."
              }
            }
          ]
        }
      ]
    }
  }
}

