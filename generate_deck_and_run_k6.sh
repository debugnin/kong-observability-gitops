#!/bin/bash

# Configurable parameters for k6 load test
TEST_DURATION="${1:-60s}"  # Default to 60 seconds
RATE="${2:-100}"           # Default rate (iterations per time unit)
TIME_UNIT="${3:-s}"       # Time unit for rate (s, m, h)
PRE_ALLOCATED_VUS="${4:-10}"  # Number of pre-allocated VUs
MAX_VUS="${5:-50}"           # Max VUs

SERVICE_COUNT="${6:-3}"  # Default to 3 services if not provided
ROUTE_COUNT="${7:-3}"    # Default to 3 routes per service if not provided

# Konnect configuration
KONNECT_TOKEN="${8:-$KONNECT_TOKEN}"  # Konnect personal access token
CONTROL_PLANE_NAME="${9:-$CONTROL_PLANE_NAME}"  # Control plane name
KONNECT_ADDR="${10:-https://au.api.konghq.com}"  # Konnect address

# Output deck file
DECK_FILE="deck.yaml"

# Write the deck file header
cat <<EOF > $DECK_FILE
_format_version: "3.0"
plugins:
- config:
    content_type: application/json
    custom_fields_by_lua:
      spanid: |
        local h = kong.request.get_header('traceparent')
        return h:match("%-[a-f0-9]+%-([a-f0-9]+)%-")
      traceid: |
        local h = kong.request.get_header('traceparent')
        return h:match("%-([a-f0-9]+)%-[a-f0-9]+%-")
    flush_timeout: null
    headers: null
    http_endpoint: http://fluent-bit.kong-observability.svc.cluster.local:2020
    keepalive: 60000
    method: POST
    queue:
      initial_retry_delay: 0.01
      max_batch_size: 1
      max_bytes: null
      max_coalescing_delay: 1
      max_entries: 10000
      max_retry_delay: 60
      max_retry_time: 60
    queue_size: null
    retry_count: null
    timeout: 10000
  enabled: true
  name: http-log
  protocols:
  - grpc
  - grpcs
  - http
  - https
- config:
    batch_flush_delay: null
    batch_span_count: null
    connect_timeout: 1000
    traces_endpoint: http://otel-collector-opentelemetry-collector.kong-observability.svc.cluster.local:4318/v1/traces
    logs_endpoint: http://otel-collector-opentelemetry-collector.kong-observability.svc.cluster.local:4318/v1/logs
    header_type: preserve
    headers: null
    http_response_header_for_traceid: null
    queue:
      initial_retry_delay: 0.01
      max_batch_size: 200
      max_bytes: null
      max_coalescing_delay: 1
      max_entries: 10000
      max_retry_delay: 60
      max_retry_time: 60
    read_timeout: 5000
    resource_attributes:
      service.name: kong-otel-plugin
    send_timeout: 5000
  enabled: true
  name: opentelemetry
  protocols:
  - grpc
  - grpcs
  - http
  - https
- config:
    bandwidth_metrics: true
    latency_metrics: true
    per_consumer: true
    status_code_metrics: true
    upstream_health_metrics: true
  enabled: true
  name: prometheus
  protocols:
  - grpc
  - grpcs
  - http
  - https
services:
EOF

# Generate services and routes based on user input
for i in $(seq 1 $SERVICE_COUNT); do
  cat <<EOF >> $DECK_FILE
  - name: httpbin-service-$i
    enabled: true
    host: http-upstream-service
    path: /anything
    port: 443
    protocol: https
    read_timeout: 60000
    retries: 5
    routes:
EOF

  # Generate routes for each service based on user input
  for j in $(seq 1 $ROUTE_COUNT); do
    cat <<EOF >> $DECK_FILE
      - name: httpbin-service-$i-route-$j
        methods:
          - GET
        paths:
          - /service$i/route$j
        preserve_host: false
        protocols:
          - http
          - https
        regex_priority: 0
        strip_path: true
        https_redirect_status_code: 426
        request_buffering: true
        response_buffering: true
EOF
  done
done

# Add plugins section at the end
cat <<EOF >> $DECK_FILE
upstreams:
- algorithm: round-robin
  hash_fallback: none
  hash_on: none
  hash_on_cookie_path: /
  healthchecks:
    active:
      concurrency: 10
      healthy:
        http_statuses:
        - 200
        - 302
        interval: 5
        successes: 2
      http_path: /
      https_verify_certificate: true
      timeout: 1
      type: http
      unhealthy:
        http_failures: 1
        http_statuses:
        - 429
        - 404
        - 500
        - 501
        - 502
        - 503
        - 504
        - 505
        interval: 5
        tcp_failures: 0
        timeouts: 1
    passive:
      healthy:
        http_statuses:
        - 200
        - 201
        - 202
        - 203
        - 204
        - 205
        - 206
        - 207
        - 208
        - 226
        - 300
        - 301
        - 302
        - 303
        - 304
        - 305
        - 306
        - 307
        - 308
        successes: 0
      type: http
      unhealthy:
        http_failures: 0
        http_statuses:
        - 429
        - 500
        - 503
        tcp_failures: 0
        timeouts: 0
    threshold: 1
  name: http-upstream-service
  slots: 10000
  targets:
  - target: httpbin.konghq.com:443
    weight: 100
  use_srv_name: false
EOF

echo "deck.yaml file generated."

# Run the deck sync to apply the configuration
echo "Applying configuration with deck..."
if [ -n "$KONNECT_TOKEN" ] && [ -n "$CONTROL_PLANE_NAME" ]; then
  echo "Using Konnect configuration..."
  deck gateway sync $DECK_FILE --konnect-token "$KONNECT_TOKEN" --konnect-control-plane-name "$CONTROL_PLANE_NAME" --konnect-addr "$KONNECT_ADDR"
else
  echo "Using local Kong gateway..."
  deck gateway sync $DECK_FILE
fi

# Generate k6 test script
K6_SCRIPT="k6-test.js"

cat <<EOF > $K6_SCRIPT
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  duration: '${TEST_DURATION}',
  vus: ${PRE_ALLOCATED_VUS},
  thresholds: {
    http_req_duration: ['p(95)<500'], // 95% of requests should complete below 500ms
  },
  stages: [
    { duration: '${TEST_DURATION}', target: ${MAX_VUS} },
  ],
};

export default function () {
  const serviceNum = Math.floor(Math.random() * ${SERVICE_COUNT}) + 1;
  const routeNum = Math.floor(Math.random() * ${ROUTE_COUNT}) + 1;
  const url = \`http://localhost:8000/service\${serviceNum}/route\${routeNum}\`;

  const res = http.get(url);
  check(res, {
    'status is 200': (r) => r.status === 200,
  });
  sleep(1);
}
EOF

echo "k6 load test script generated."

# Run k6 load test
echo "Starting k6 load test..."
k6 run --vus ${PRE_ALLOCATED_VUS} --duration ${TEST_DURATION} ${K6_SCRIPT}
