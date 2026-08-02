# ADR 0010: Real-Time Bidirectional Communication via WebSockets

**ADR Number:** ADR-0010  
**Title:** Real-Time Bidirectional Communication via WebSockets  
**Status:** Accepted  
**Date:** July 21, 2026  

---

## 1. Context
Instant messaging, typing indicators, read receipts, and device connection presence state require full-duplex, low-latency, bidirectional message delivery between clients and the Chat service.

## 2. Problem Statement
HTTP Long Polling or Server-Sent Events (SSE) introduce high header overhead, unidirectionality (SSE is server-to-client only), and connection teardown latency for client-to-server typing dispatches.

## 3. Decision
Standardize on WebSockets (`wss://`) for real-time bidirectional messaging. The Chat service upgrades HTTP connections ([`server.go:111`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/chat/internal/transport/websocket/server.go#L111)), handles double-close safety with `sync.Once` ([`server.go:183`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/chat/internal/transport/websocket/server.go#L183)), and uses non-blocking send queues ([`server.go:261`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/chat/internal/transport/websocket/server.go#L261)). The Flutter client manages auto-reconnection and heartbeats ([`websocket_client.dart:6-175`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/lib/core/network/websocket_client.dart#L6-L175)).

## 4. Evidence
* **WebSocket Upgrade & Handler:** [`apps/backend/services/chat/internal/transport/websocket/server.go:111-267`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/chat/internal/transport/websocket/server.go#L111-L267)
* **Flutter WebSocket Engine:** [`apps/frontend/lib/core/network/websocket_client.dart:6-175`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/lib/core/network/websocket_client.dart#L6-L175)

## 5. Alternatives Considered
* **HTTP Long Polling:** Rejected due to excessive HTTP handshake overhead.
* **gRPC Web Streaming:** Rejected due to browser client proxy dependencies and higher Dart client integration complexity compared to native WebSocket channels.

## 6. Tradeoffs
* Stateful connections require distributed Redis Pub/Sub routing across multi-instance backend pods.
* Idle TCP socket connections require ping/pong heartbeat handling to prevent firewall termination.

## 7. Consequences
* Sub-50ms glass-to-glass message transmission latency.
* Minimal frame header overhead (2 to 10 bytes per frame).

## 8. Risks
* Slow client connection buffers blocking backend event dispatch loops (mitigated via non-blocking channels).

## 9. Future Considerations
* Implement binary Protobuf frame encoding over WebSocket channels.
