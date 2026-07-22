# Prometheus Metrics Catalog

**Config File:** [`infrastructure/observability/prometheus/prometheus.yml`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/observability/prometheus/prometheus.yml)  
**Alert Rules:** [`infrastructure/observability/prometheus/alerts.yml`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/observability/prometheus/alerts.yml)

---

## 1. Exported Metric Definitions

### A. HTTP & gRPC Microservice Telemetry
* `http_requests_total{service, method, handler, code}`: Counter tracking API throughput by status code.
* `http_request_duration_seconds{service, handler}`: Histogram tracking HTTP latency buckets.
* `grpc_server_handled_total{grpc_service, grpc_method, grpc_code}`: Counter tracking gRPC RPC invocations.
* `grpc_server_handling_seconds{grpc_service, grpc_method}`: Histogram tracking gRPC execution latency.

### B. WebSocket Telemetry (Chat Service)
* `websocket_active_connections{room_id}`: Gauge tracking connected WebSocket clients.
* `websocket_messages_received_total`: Counter for inbound WS messages.
* `websocket_messages_sent_total`: Counter for outbound WS receipts and messages.
* `websocket_reconnect_replay_total`: Counter for historical message replay events.

### C. Infrastructure Telemetry
* `redis_memory_used_bytes`: Gauge tracking Redis memory usage.
* `redis_connected_clients`: Gauge tracking active Redis connection pool size.
* `pg_stat_database_xact_commit`: Counter for Postgres transaction commits.
* `pg_stat_database_numbackends`: Gauge for Postgres database connection pool size.
* `kafka_consumergroup_lag{consumergroup, topic}`: Gauge tracking Kafka queue lag.

---

## 2. Configured Production Alerts (`alerts.yml`)

1. **HighP95Latency:** Triggered if HTTP P95 latency exceeds 500ms for > 2 minutes.
2. **HighErrorRate:** Triggered if 5xx HTTP error rate exceeds 1% for > 1 minute.
3. **RedisMemoryNearLimit:** Triggered if Redis memory exceeds 85% of allocated capacity.
4. **KafkaConsumerLagHigh:** Triggered if consumer processing lag on `chat-events` exceeds 1,000 messages.
5. **PostgresHighConnections:** Triggered if database connections exceed 80% of `max_connections`.
