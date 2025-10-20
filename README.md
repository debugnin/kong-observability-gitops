# Kong Observability GitOps

This repository contains ArgoCD applications for deploying a comprehensive Kong observability stack using the Application of Applications pattern. The stack provides full observability for Kong data planes with metrics, logs, and traces collection.

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Kong Gateway  │───►│ OpenTelemetry    │───►│   Jaeger        │
│   (Data Plane)  │    │ Collector        │    │   (Traces)      │
│                 │    │                  │    └─────────────────┘
│ • Prometheus    │    │ • OTLP Receiver  │    
│ • OpenTelemetry │    │ • Prometheus     │    ┌─────────────────┐
│ • HTTP Log      │    │   Scraper        │───►│   Prometheus    │
└─────────────────┘    │ • Log Processor  │    │   (Metrics)     │
         │              └──────────────────┘    └─────────────────┘
         │                       │              
         ▼                       ▼              ┌─────────────────┐
┌─────────────────┐    ┌──────────────────┐───►│   Loki          │
│   Fluent Bit    │───►│ OpenTelemetry    │    │   (Logs)        │
│   (Log Agent)   │    │ Collector        │    └─────────────────┘
│                 │    │ (Logs Pipeline)  │    
│ • Kubernetes    │    └──────────────────┘    ┌─────────────────┐
│   Log Collector │                            │   Grafana       │
│ • OTLP Output   │                            │   (Dashboards)  │
└─────────────────┘                            │                 │
                                               │ • Prometheus DS │
                                               │ • Loki DS       │
                                               │ • Jaeger DS     │
                                               └─────────────────┘
```

## Structure

```
kong-observability-gitops/
├── argocd/
│   ├── projects/
│   │   └── kong-observability-project.yaml    # ArgoCD project definition
│   └── applications/
│       ├── kong-observability-app-of-apps.yaml # Parent application
│       └── observability/                      # Child applications
│           ├── fluent-bit.yaml                 # Log collection
│           ├── grafana.yaml                    # Visualization
│           ├── jaeger.yaml                     # Distributed tracing
│           ├── loki.yaml                       # Log storage
│           ├── otel-collector.yaml             # Telemetry processing
│           └── prometheus.yaml                 # Metrics storage
├── generate_deck_and_run_k6.sh                # Kong config & load testing
└── README.md
```

## Components

### Core Observability Stack
- **OpenTelemetry Collector**: Central telemetry data processing hub
  - Receives traces/logs from Kong via OTLP
  - Scrapes metrics from Kong Prometheus endpoints
  - Routes data to appropriate backends
- **Prometheus**: Metrics collection, storage, and alerting
  - Scrapes metrics from OTel Collector
  - Includes Kong-specific alert rules
- **Grafana**: Unified visualization and dashboards
  - Pre-configured data sources for all backends
  - Anonymous access enabled
- **Jaeger**: Distributed tracing storage and UI
- **Loki**: Log aggregation and storage
- **Fluent Bit**: Kubernetes log collection agent
  - Collects container logs cluster-wide
  - Forwards to OTel Collector via OTLP

### Kong Integration
- **Prometheus Plugin**: Exposes Kong metrics
- **OpenTelemetry Plugin**: Sends traces to OTel Collector
- **HTTP Log Plugin**: Sends request logs to Fluent Bit
- **Alert Rules**: Kong-specific monitoring alerts

## Data Flow

1. **Metrics**: Kong → OTel Collector (scrape) → Prometheus → Grafana
2. **Traces**: Kong → OTel Collector (OTLP) → Jaeger → Grafana
3. **Logs**: Kong → Fluent Bit → OTel Collector (OTLP) → Loki → Grafana
4. **K8s Logs**: Fluent Bit → OTel Collector → Loki → Grafana

## Deployment

### Prerequisites
- Kubernetes cluster with ArgoCD installed
- Kong data planes deployed in separate namespaces

### Installation

1. Apply the ArgoCD project:
   ```bash
   kubectl apply -f argocd/projects/kong-observability-project.yaml
   ```

2. Deploy the observability stack:
   ```bash
   kubectl apply -f argocd/applications/kong-observability-app-of-apps.yaml
   ```

3. Wait for all applications to sync and become healthy:
   ```bash
   argocd app list | grep kong-observability
   ```

### Kong Configuration

Use the provided script to configure Kong with observability plugins:

```bash
# For Konnect
export KONNECT_TOKEN="your-token"
export CONTROL_PLANE_NAME="your-control-plane"
./generate_deck_and_run_k6.sh 60s 100 s 10 50 3 3

# For local Kong
./generate_deck_and_run_k6.sh
```

## Access

### Web UIs

- **Grafana**: 
  ```bash
  kubectl port-forward -n kong-observability svc/grafana 3000:80
  ```
  Access: http://localhost:3000 (no login required)

- **Prometheus**: 
  ```bash
  kubectl port-forward -n kong-observability svc/prometheus-server 9090:80
  ```
  Access: http://localhost:9090

- **Jaeger**: 
  ```bash
  kubectl port-forward -n kong-observability svc/jaeger-query 16686:16686
  ```
  Access: http://localhost:16686

### Data Sources (Pre-configured in Grafana)

- **Prometheus**: `http://prometheus-server.kong-observability.svc.cluster.local`
- **Loki**: `http://loki.kong-observability.svc.cluster.local:3100`
- **Jaeger**: `http://jaeger-query.kong-observability.svc.cluster.local:16686`

## Monitoring & Alerting

### Kong Alert Rules

The following alerts are configured in Prometheus:

- **KongHighLatency**: 90th percentile latency > 100ms (Critical)
- **KongHighErrorRate**: 5xx error rate > 0.5% (Info)
- **KongNon2XXSpike**: Non-2xx responses > 5% (Info)
- **KongTrafficSpike**: Traffic 20% above baseline (Info)
- **KongTrafficDrop**: Traffic 20% below baseline (Info)
- **Kong500Responses**: Any 500 responses detected (Critical)

### Load Testing

The repository includes a k6 load testing script that:
- Generates Kong configuration with observability plugins
- Creates multiple services and routes
- Runs configurable load tests
- Triggers alerts and generates telemetry data

## Troubleshooting

### Common Issues

1. **OTel Collector RBAC**: Ensure cluster role has cross-namespace pod access
2. **Service Discovery**: Check Kong pods have correct labels for Prometheus scraping
3. **Network Policies**: Verify inter-namespace communication is allowed
4. **Resource Limits**: Monitor resource usage in kong-observability namespace

### Verification

```bash
# Check all pods are running
kubectl get pods -n kong-observability

# Verify OTel Collector is scraping Kong metrics
kubectl logs -n kong-observability deployment/otel-collector-opentelemetry-collector

# Check Prometheus targets
kubectl port-forward -n kong-observability svc/prometheus-server 9090:80
# Visit http://localhost:9090/targets
```

## Configuration

All applications use GitOps principles with configuration stored in this repository. Modifications to the observability stack should be made via pull requests to ensure proper change management and deployment consistency.