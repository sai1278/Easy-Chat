# ADR 0015: Observability using OpenTelemetry, Prometheus, Loki, & Grafana

**ADR Number:** ADR-0015  
**Title:** Observability using OpenTelemetry, Prometheus, Loki, & Grafana  
**Status:** Accepted  
**Date:** July 21, 2026  

---

## 1. Context
Microservices operating in Kubernetes require centralized distributed tracing, real-time metric collection, structured log aggregation, SLA alerting, and operational dashboards to maintain high availability.

## 2. Problem Statement
Debugging issues across multi-service asynchronous message flows (e.g. Chat $\rightarrow$ Kafka $\rightarrow$ Notification) without distributed trace context propagation leads to high mean-time-to-resolution (MTTR) and invisible latency bottlenecks.

## 3. Decision
Deploy a unified open-standard observability stack:
* **Tracing:** OpenTelemetry Go SDK (`shared/tracing/tracing.go`) injecting W3C TraceContext headers.
* **Logging:** Structured JSON logging using Go `log/slog` (`shared/logger/logger.go`) with UUIDv4 request correlation IDs (`X-Request-ID`).
* **Metrics & Alerting:** Prometheus metric exporters (`/metrics`) with alerting rules (`alerts.yml`, `compliance-alerts.yml`).
* **Dashboards:** Grafana SRE & System operational dashboards (`infrastructure/observability/grafana/dashboards/`).

## 4. Evidence
* **OpenTelemetry SDK Initializer:** [`apps/backend/shared/tracing/tracing.go:17-45`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/shared/tracing/tracing.go#L17-L45)
* **Prometheus Alerting Rules:** [`infrastructure/observability/prometheus/alerts.yml:1-50`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/observability/prometheus/alerts.yml#L1-L50)
* **Grafana SRE Dashboard:** [`infrastructure/observability/grafana/dashboards/sre_operations_dashboard.json:1`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/observability/grafana/dashboards/sre_operations_dashboard.json#L1)

## 5. Alternatives Considered
* **Datadog / New Relic:** Rejected due to proprietary vendor lock-in and high recurring SaaS licensing costs.

## 6. Tradeoffs
* Small CPU/memory overhead for OpenTelemetry trace sampling and metric scraping.
* Storage management required for Loki log retention.

## 7. Consequences
* End-to-end trace visibility across microservice HTTP, gRPC, and Kafka boundaries.
* Real-time alerting on SLA breaches (HTTP 5xx $> 1\%$, $p_{95}$ latency $> 200\text{ms}$).

## 8. Risks
* High trace sampling rates causing storage growth during traffic surges.

## 9. Future Considerations
* Implement adaptive sampling in OpenTelemetry Collector based on error rates.
