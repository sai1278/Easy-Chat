# Architecture Decision Records (ADRs)

**Author:** Google Principal Software Architect  
**Repository:** EasyChat / Nearby Connect Monorepo  
**Status:** Approved Master Architectural Index  

---

## Executive Overview

This directory contains the complete collection of Architecture Decision Records (ADRs) for the monorepo. Each ADR documents an actual, verified architectural decision implemented directly within the source code, Protobuf schemas, database migrations, and deployment infrastructure.

---

## Current Status of all ADRs

| ADR ID | Title | Status | Primary Technology | Implementation Evidence |
| :---: | :--- | :---: | :--- | :--- |
| **[ADR-0001](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/adr/ADR-0001-go-microservices.md)** | Polyglot Go Microservices Architecture | **Accepted** | Go 1.22+ / Workspace | [`go.work:3`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/go.work#L3), [`auth/cmd/main.go:1`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/auth/cmd/auth/main.go#L1) |
| **[ADR-0002](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/adr/ADR-0002-flutter.md)** | Cross-Platform Client Development using Flutter | **Accepted** | Flutter / Dart | [`pubspec.yaml:1`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/pubspec.yaml#L1), [`main.dart:1`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/lib/main.dart#L1) |
| **[ADR-0003](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/adr/ADR-0003-riverpod.md)** | Declarative State Management with Flutter Riverpod | **Accepted** | Flutter Riverpod | [`main.dart:51`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/lib/main.dart#L51), [`chat_controller.dart:43`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/lib/features/chat/presentation/chat_controller.dart#L43) |
| **[ADR-0004](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/adr/ADR-0004-isar.md)** | Offline Local Storage using Isar NoSQL Database | **Accepted** | Isar Database | [`isar_service.dart:1`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/lib/core/database/isar_service.dart#L1), [`message_entity.dart:1`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/lib/core/database/entities/message_entity.dart#L1) |
| **[ADR-0005](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/adr/ADR-0005-redis.md)** | Redis for Caching, Device Presence, and Pub/Sub | **Accepted** | Redis Engine | [`server.go:252`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/chat/internal/transport/websocket/server.go#L252), [`presence/main.go:48`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/presence/cmd/presence/main.go#L48) |
| **[ADR-0006](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/adr/ADR-0006-kafka.md)** | Asynchronous Event Streaming using Apache Kafka | **Accepted** | Apache Kafka | [`chat/main.go:94`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/chat/cmd/chat/main.go#L94), [`pipeline.go:106`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/chat/internal/infrastructure/kafka/pipeline.go#L106) |
| **[ADR-0007](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/adr/ADR-0007-grpc.md)** | Inter-Service Communication via Protobuf & gRPC | **Accepted** | gRPC / Protobuf v3 | [`nearby.proto:1`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/proto/nearby/v1/nearby.proto#L1), [`generate_proto.sh:54`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/scripts/generate_proto.sh#L54) |
| **[ADR-0008](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/adr/ADR-0008-postgresql-partitioning.md)** | Relational Persistence & Partitioning via PostgreSQL | **Accepted** | PostgreSQL 15+ | [`000001_create_users.sql:1`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/database/migrations/000001_create_users_table.up.sql#L1), [`000005_indexes.sql:1`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/database/migrations/000005_performance_optimization_indexes.up.sql#L1) |
| **[ADR-0009](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/adr/ADR-0009-uber-h3-geospatial.md)** | Proximity Matching using Uber H3 Spatial Indexing | **Accepted** | Uber H3 Grid | [`redis.go:45`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/nearby/internal/infrastructure/cache/redis.go#L45), [`presence/main.go:87`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/presence/cmd/presence/main.go#L87) |
| **[ADR-0010](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/adr/ADR-0010-websockets.md)** | Real-Time Communication via WebSockets | **Accepted** | WebSocket Protocol | [`server.go:111`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/chat/internal/transport/websocket/server.go#L111), [`websocket_client.dart:6`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/lib/core/network/websocket_client.dart#L6) |
| **[ADR-0011](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/adr/ADR-0011-api-gateway.md)** | API Gateway Reverse Proxy, Rate Limiter & Circuit Breaker | **Accepted** | Reverse Proxy | [`router.go:34`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/gateway/internal/transport/http/router.go#L34), [`gateway/main.go:61`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/gateway/cmd/gateway/main.go#L61) |
| **[ADR-0012](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/adr/ADR-0012-jwt-keycloak-auth.md)** | Authentication via JWT & Keycloak Identity | **Accepted** | JWT / Bcrypt | [`router.go:424`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/gateway/internal/transport/http/router.go#L424), [`auth_usecase.go:22`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/auth/internal/application/auth_usecase.go#L22) |
| **[ADR-0013](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/adr/ADR-0013-kubernetes-helm.md)** | Container Orchestration via Kubernetes & Helm | **Accepted** | Kubernetes / Helm v3 | [`values.yaml:1`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/helm/easychat/values.yaml#L1), [`hpa.yaml:1`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/kubernetes/production/hpa.yaml#L1) |
| **[ADR-0014](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/adr/ADR-0014-github-actions-cicd.md)** | Continuous Integration & Deployment via GitHub Actions | **Accepted** | GitHub Actions | [`.github/workflows/ci.yml:1`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/.github/workflows/ci.yml#L1), [`cd.yml:1`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/.github/workflows/cd.yml#L1) |
| **[ADR-0015](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/adr/ADR-0015-opentelemetry-prometheus-grafana.md)** | Observability using OpenTelemetry, Prometheus & Grafana | **Accepted** | OpenTelemetry / SRE | [`tracing.go:17`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/shared/tracing/tracing.go#L17), [`alerts.yml:1`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/observability/prometheus/alerts.yml#L1) |
| **[ADR-0016](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/adr/ADR-0016-disaster-recovery.md)** | Automated Multi-Region Disaster Recovery Operator | **Accepted** | K8s Operator / Lease | [`dr-controller/main.go:1`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/dr-controller/main.go#L1), [`crd.yaml:1`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/dr/crds/disaster-recovery-policy-crd.yaml#L1) |
| **[ADR-0017](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/adr/ADR-0017-gdpr-compliance.md)** | Enterprise GDPR & Privacy Compliance Engine | **Accepted** | GDPR Engine / SHA256 | [`compliance.go:134`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/compliance/compliance.go#L134), [`001_gdpr_schema.sql:1`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/database/migrations/001_gdpr_compliance_schema.sql#L1) |

---

## Decision Timeline

```
[Platform Inception]
├── ADR-0001: Polyglot Go Microservices Architecture
├── ADR-0002: Cross-Platform Client Development using Flutter
└── ADR-0008: Relational Persistence & Partitioning via PostgreSQL
      │
[Core Data & Real-Time Transport]
├── ADR-0004: Offline Local Storage using Isar NoSQL
├── ADR-0005: Redis for Caching, Presence, and Pub/Sub
├── ADR-0006: Asynchronous Event Streaming via Apache Kafka
├── ADR-0007: Inter-Service Communication via Protobuf & gRPC
└── ADR-0010: Real-Time Communication via WebSockets
      │
[Security, Gateway & Client State]
├── ADR-0003: Declarative State Management with Flutter Riverpod
├── ADR-0009: Proximity Matching using Uber H3 Spatial Indexing
├── ADR-0011: API Gateway Reverse Proxy, Rate Limiter & Circuit Breaker
└── ADR-0012: Authentication via JWT & Keycloak Identity Management
      │
[Infrastructure & Enterprise Readiness]
├── ADR-0013: Container Orchestration via Kubernetes & Helm
├── ADR-0014: Continuous Integration & Deployment via GitHub Actions
├── ADR-0015: Observability using OpenTelemetry, Prometheus & Grafana
├── ADR-0016: Automated Multi-Region Disaster Recovery Operator
└── ADR-0017: Enterprise GDPR & Privacy Compliance Engine
```

---

## Cross References & Architectural Dependencies

```
                                ┌───────────────────────────┐
                                │ ADR-0011: API Gateway     │
                                └─────────────┬─────────────┘
                                              │
                    ┌─────────────────────────┼─────────────────────────┐
                    ▼                         ▼                         ▼
      ┌──────────────────────────┐┌──────────────────────────┐┌──────────────────────────┐
      │ ADR-0012: JWT Auth       ││ ADR-0010: WebSockets     ││ ADR-0007: gRPC / Proto  │
      └─────────────┬────────────┘└───────────┬──────────────┘└───────────┬──────────────┘
                    │                         │                           │
                    ▼                         ▼                           ▼
      ┌──────────────────────────┐┌──────────────────────────┐┌──────────────────────────┐
      │ ADR-0001: Go Services    ││ ADR-0005: Redis Pub/Sub  ││ ADR-0009: Uber H3 Grid   │
      └─────────────┬────────────┘└───────────┬──────────────┘└───────────┬──────────────┘
                    │                         │                           │
                    ├─────────────────────────┼───────────────────────────┘
                    ▼                         ▼
      ┌──────────────────────────┐┌──────────────────────────┐
      │ ADR-0008: PostgreSQL     ││ ADR-0006: Kafka Streaming│
      └─────────────┬────────────┘└───────────┬──────────────┘
                    │                         │
                    ▼                         ▼
      ┌──────────────────────────┐┌──────────────────────────┐
      │ ADR-0017: GDPR Compliance││ ADR-0016: DR Controller  │
      └──────────────────────────┘└──────────────────────────┘
```

---

## Individual ADR Files

1. [`ADR-0001-go-microservices.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/adr/ADR-0001-go-microservices.md)
2. [`ADR-0002-flutter.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/adr/ADR-0002-flutter.md)
3. [`ADR-0003-riverpod.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/adr/ADR-0003-riverpod.md)
4. [`ADR-0004-isar.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/adr/ADR-0004-isar.md)
5. [`ADR-0005-redis.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/adr/ADR-0005-redis.md)
6. [`ADR-0006-kafka.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/adr/ADR-0006-kafka.md)
7. [`ADR-0007-grpc.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/adr/ADR-0007-grpc.md)
8. [`ADR-0008-postgresql-partitioning.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/adr/ADR-0008-postgresql-partitioning.md)
9. [`ADR-0009-uber-h3-geospatial.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/adr/ADR-0009-uber-h3-geospatial.md)
10. [`ADR-0010-websockets.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/adr/ADR-0010-websockets.md)
11. [`ADR-0011-api-gateway.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/adr/ADR-0011-api-gateway.md)
12. [`ADR-0012-jwt-keycloak-auth.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/adr/ADR-0012-jwt-keycloak-auth.md)
13. [`ADR-0013-kubernetes-helm.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/adr/ADR-0013-kubernetes-helm.md)
14. [`ADR-0014-github-actions-cicd.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/adr/ADR-0014-github-actions-cicd.md)
15. [`ADR-0015-opentelemetry-prometheus-grafana.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/adr/ADR-0015-opentelemetry-prometheus-grafana.md)
16. [`ADR-0016-disaster-recovery.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/adr/ADR-0016-disaster-recovery.md)
17. [`ADR-0017-gdpr-compliance.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/adr/ADR-0017-gdpr-compliance.md)
