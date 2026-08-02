# ADR 0005: Redis for Caching, Device Presence, and Pub/Sub Messaging

**ADR Number:** ADR-0005  
**Title:** Redis for Caching, Device Presence, and Pub/Sub Messaging  
**Status:** Accepted  
**Date:** July 21, 2026  

---

## 1. Context
The platform requires distributed cross-node WebSocket message fan-out, sliding-window rate limiting, user device presence tracking, and high-frequency geospatial proximity lookups.

## 2. Problem Statement
Relying on PostgreSQL for presence state updates (10s heartbeats across millions of devices) would saturate database IOPS and exhaust connection limits.

## 3. Decision
Utilize Redis in-memory storage for high-speed cache operations:
* **Pub/Sub Channels:** Cross-node WebSocket routing (`chat:user:inbox:{userID}`).
* **Presence Sets:** Reference-counted user devices (`SADD`/`SREM`).
* **Geospatial Indexes:** Geo H3 location sets for proximity matching.
* **Rate Limiting:** Sliding-window request counters.

## 4. Evidence
* **WebSocket Redis Pub/Sub Subscriber:** [`apps/backend/services/chat/internal/transport/websocket/server.go:252`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/chat/internal/transport/websocket/server.go#L252) and [`line 285`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/chat/internal/transport/websocket/server.go#L285)
* **Presence Redis Initialization:** [`apps/backend/services/presence/cmd/presence/main.go:48-51`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/presence/cmd/presence/main.go#L48-L51)
* **Redis Spatial Cache Repository:** [`apps/backend/services/nearby/internal/infrastructure/cache/redis.go:45`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/nearby/internal/infrastructure/cache/redis.go#L45)

## 5. Alternatives Considered
* **Memcached:** Rejected due to lack of native Pub/Sub channels and Geo spatial indexes.
* **PostgreSQL In-Memory Tables:** Rejected due to operational complexity and lower throughput for ephemeral state.

## 6. Tradeoffs
* Ephemeral storage model requires state persistence fallback in PostgreSQL for chat history.
* Redis single-threaded execution model requires cluster sharding under extreme scale.

## 7. Consequences
* Sub-millisecond presence status updates and multi-node WebSocket fan-out.
* Offloaded database read/write pressure for transient states.

## 8. Risks
* Redis instance memory exhaustion if presence keys lack expiration TTLs.

## 9. Future Considerations
* Deploy Redis Cluster with multi-region replication.
