grafana:
  adminPassword: "${grafana_admin_password}"
  service:
    type: "${grafana_service_type}"
  persistence:
    enabled: false

prometheus:
  prometheusSpec:
    retention: 3d
%{ if storage_size != null ~}
    storageSpec:
      volumeClaimTemplate:
        spec:
          resources:
            requests:
              storage: "${storage_size}"
%{ else ~}
    # No persistence configured - fine for a local/dev cluster.
    # Data is lost if the Prometheus pod restarts.
%{ endif ~}

alertmanager:
  enabled: true
  alertmanagerSpec:
    storage: {}
