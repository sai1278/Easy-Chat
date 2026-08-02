# ADR 0007: Inter-Service Communication via Protocol Buffers & gRPC

**ADR Number:** ADR-0007  
**Title:** Inter-Service Communication via Protocol Buffers & gRPC  
**Status:** Accepted  
**Date:** July 21, 2026  

---

## 1. Context
High-frequency inter-service communications (such as geospatial proximity lookups between Nearby Service and Gateway) require strongly typed, backwards-compatible, binary-serialized RPC interfaces.

## 2. Problem Statement
REST over JSON introduces CPU overhead from string parsing, lacks compile-time client/server contract verification, and risks runtime field type drift across microservice boundaries.

## 3. Decision
Adopt Protocol Buffers v3 as the standard API IDL (`proto/nearby/v1/*.proto`) and gRPC over HTTP/2 for inter-service communication. Protobuf compiler scripts (`scripts/generate_proto.sh`) output typed Go stubs (`internal/gen/v1`) and Dart client code.

## 4. Evidence
* **Protobuf Service Definitions:** [`proto/nearby/v1/nearby.proto:1-50`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/proto/nearby/v1/nearby.proto#L1-L50)
* **gRPC Server Listener:** [`apps/backend/services/nearby/cmd/nearby/main.go:108-116`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/nearby/cmd/nearby/main.go#L108-L116)
* **Protobuf Compilation Pipeline:** [`scripts/generate_proto.sh:54-67`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/scripts/generate_proto.sh#L54-L67)

## 5. Alternatives Considered
* **REST / JSON:** Rejected for inter-service backend calls due to high serialization latency and un-typed contracts.
* **Apache Thrift:** Rejected due to smaller ecosystem tooling support compared to gRPC/Protobuf.

## 6. Tradeoffs
* Requires proto compilation build steps before code execution.
* Binary payloads require specialized tools (e.g. `grpcurl`) for manual CLI debugging.

## 7. Consequences
* Sub-5ms inter-service RPC latency using HTTP/2 multiplexing.
* Automated compile-time verification of service request/response structs.

## 8. Risks
* Field tag numbering mismatches if developers break Protobuf backward compatibility rules.

## 9. Future Considerations
* Implement Buf schema registry validation in GitHub Actions CI workflows.
