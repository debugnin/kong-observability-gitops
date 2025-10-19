# Kong Observability GitOps

This repository contains ArgoCD applications for deploying the Kong observability stack using the Application of Applications pattern.

## Structure

```
kong-observability-gitops/
├── argocd/
│   ├── projects/
│   │   └── kong-observability-project.yaml    # ArgoCD project definition
│   └── applications/
│       ├── kong-observability-app-of-apps.yaml # Parent application
│       └── observability/                      # Child applications
│           ├── grafana.yaml
│           ├── jaeger.yaml
│           ├── loki.yaml
│           ├── otel-collector.yaml
│           └── prometheus.yaml
└── README.md
```

## Components

- **Prometheus**: Metrics collection and storage (kube-prometheus-stack)
- **Grafana**: Visualization and dashboards
- **Jaeger**: Distributed tracing
- **OpenTelemetry Collector**: Telemetry data collection and processing
- **Loki**: Log aggregation and storage

## Deployment

1. Apply the project:
   ```bash
   kubectl apply -f argocd/projects/kong-observability-project.yaml
   ```

2. Apply the parent application:
   ```bash
   kubectl apply -f argocd/applications/kong-observability-app-of-apps.yaml
   ```

The parent application will automatically deploy all child applications in the `kong-observability` namespace.

## Access

- **Grafana**: Port-forward to access the UI (Anonymous access enabled)
  ```bash
  kubectl port-forward -n kong-observability svc/grafana 3000:80
  ```
  Access at: http://localhost:3000 (no login required)

- **Prometheus**: Port-forward to access the UI
  ```bash
  kubectl port-forward -n kong-observability svc/prometheus-server 9090:80
  ```
  Access at: http://localhost:9090

- **Jaeger**: Port-forward to access the UI
  ```bash
  kubectl port-forward -n kong-observability svc/jaeger-query 16686:16686
  ```
  Access at: http://localhost:16686