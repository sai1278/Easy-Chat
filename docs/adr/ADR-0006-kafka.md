# ADR 0006: Asynchronous Event Streaming using Apache Kafka

**ADR Number:** ADR-0006  
**Title:** Asynchronous Event Streaming using Apache Kafka  
**Status:** Accepted  
**Date:** July 21, 2026  

---

## 1. Context
Chat message events, push notifications, and compliance audit events require durable, fault-tolerant, ordered, asynchronous processing pipelines decoupled from HTTP API response loops.

## 2. Problem Statement
Synchronous HTTP API execution for notification delivery or compliance logging increases API request latency, risks cascading failures during third-party outage, and drops messages under traffic surges.

## 3. Decision
Deploy Apache Kafka as the core asynchronous event stream broker. The system defines partitioned topics (`chat-messages`, `chat-notifications`) with consumer groups (`chat-service-group`) and Dead Letter Topics (`chat-messages-dlq`) for unparseable payloads.

## 4. Evidence
* **Kafka Pipeline Initialization:** [`apps/backend/services/chat/cmd/chat/main.go:94-108`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/chat/cmd/chat/main.go#L94-L108)
* **Kafka Consumer Goroutine:** [`apps/backend/services/chat/cmd/chat/main.go:126-129`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/chat/cmd/chat/main.go#L126-L129)
* **Kafka Event Pipeline Implementation:** [`apps/backend/services/chat/internal/infrastructure/kafka/pipeline.go:106`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/chat/internal/infrastructure/kafka/pipeline.go#L106)

## 5. Alternatives Considered
* **RabbitMQ:** Rejected due to lower message replay durability and lower partition throughput compared to Kafka.
* **AWS SQS / SNS:** Rejected to maintain cloud-agnostic infrastructure compatibility.

## 6. Tradeoffs
* Requires ZooKeeper/KRaft cluster infrastructure management.
* Message consumer logic must handle idempotent processing.

## 7. Consequences
* Guaranteed message delivery and replay capability.
* Complete decoupling of API gateway handlers from background processing.

## 8. Risks
* Consumer group lag under peak spikes requiring automated autoscaling.

## 9. Future Considerations
* Integrate Schema Registry for Protobuf message serialization over Kafka topics.
