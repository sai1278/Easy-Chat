# Grafana Dashboard & Telemetry Guide

**Dashboard Directory:** [`infrastructure/observability/grafana/dashboards`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/observability/grafana/dashboards)

---

## 1. Overview

Grafana provides real-time visualization of system latencies, throughput, error rates, resource utilization, and queue backlog metrics across all microservices and infrastructure backends.

---

## 2. Configured Dashboards

### A. API Gateway & Microservices Latency Dashboard
- **Panels:**
  - HTTP Request Rate (RPS by status code `2xx`, `4xx`, `5xx`).
  - Latency Histogram Percentiles (P50, P95, P99 by service).
  - Active Goroutines & Memory Allocated per Go microservice binary.
- **Key PromQL Query (P95 Latency):**
  ```promql
  histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le, service))
  ```

### B. Redis Cluster & Memory Saturation Dashboard
- **Panels:**
  - Memory Usage (`used_memory` vs `maxmemory`).
  - Cache Hit / Miss Ratio (`keyspace_hits` / `keyspace_misses`).
  - Connected Clients & Command Rate (RPS for `GEOSEARCH`, `GET`, `SET`).

### C. PostgreSQL 16 Performance Dashboard
- **Panels:**
  - Connection Pool Utilization (`num_active_conns` vs `max_conns`).
  - Active Transactions & Deadlocks.
  - Disk I/O & Slow Query Duration (> 100ms).

### D. Kafka 3.7 Consumer Lag Dashboard
- **Panels:**
  - Topic Ingestion Rate (messages/sec on `chat-events`, `presence-events`).
  - Consumer Group Processing Lag per topic partition.

---

## 3. Importing Dashboards

1. Access Grafana UI at `http://grafana.easychat.local:3000`.
2. Navigate to **Dashboards -> Import**.
3. Upload `infrastructure/observability/grafana/dashboards/system_dashboard.json`.
