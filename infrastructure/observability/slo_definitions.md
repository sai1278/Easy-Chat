# Service Level Objectives (SLOs) & Agreements (SLAs)

This document formalises the service level parameters, targets, and monitoring equations for the Easy Chat platform.

---

## 1. HTTP API Request Latency
Tracks the execution latency of REST requests handled by microservice REST controllers.

| Metric | Target Window | SLA Threshold | SLO Target | Monitoring SLI Equation |
| :--- | :--- | :--- | :--- | :--- |
| **API Latency** | 30-Day Rolling | 95% of requests < 250ms | **99% of requests < 200ms** | `sum(rate(http_request_duration_seconds_bucket{le="0.2"}[30d])) / sum(rate(http_request_duration_seconds_count[30d]))` |

---

## 2. WebSocket Connection Availability
Tracks WebSocket session connection uptime and drop rates across chat and presence services.

| Metric | Target Window | SLA Threshold | SLO Target | Monitoring SLI Equation |
| :--- | :--- | :--- | :--- | :--- |
| **WS Session Availability** | 7-Day Rolling | 99.0% connection uptime | **99.9% connection uptime** | `(1 - (sum_over_time(websocket_failures[7d]) / sum_over_time(websocket_total_sessions[7d]))) * 100` |

---

## 3. Redis Cache & Presence Latency
Tracks Redis key-value operation times and pub/sub inbox delivery speed.

| Metric | Target Window | SLA Threshold | SLO Target | Monitoring SLI Equation |
| :--- | :--- | :--- | :--- | :--- |
| **Redis Operation Latency** | 24-Hour Rolling | 99% of operations < 15ms | **99.9% of operations < 10ms** | `sum(rate(redis_latency_seconds_bucket{le="0.01"}[24h])) / sum(rate(redis_latency_seconds_count[24h]))` |

---

## 4. PostgreSQL Database Performance
Tracks persistence layer write/read query execution latency.

| Metric | Target Window | SLA Threshold | SLO Target | Monitoring SLI Equation |
| :--- | :--- | :--- | :--- | :--- |
| **DB Query Performance** | 30-Day Rolling | 95% of queries < 100ms | **99% of queries < 50ms** | `sum(rate(db_query_duration_seconds_bucket{le="0.05"}[30d])) / sum(rate(db_query_duration_seconds_count[30d]))` |

---

## 5. Kafka Event Pipeline Lag
Tracks message delivery offsets and consumer queue lag thresholds.

| Metric | Target Window | SLA Threshold | SLO Target | Monitoring SLI Equation |
| :--- | :--- | :--- | :--- | :--- |
| **Kafka Pipeline Lag** | 1-Hour Rolling | Lag < 1000 messages | **Lag < 500 messages** | `sum(kafka_consumer_lag_messages) by (group, topic)` |
