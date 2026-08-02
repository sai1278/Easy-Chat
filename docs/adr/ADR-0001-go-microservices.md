# ADR 0001: Polyglot Go Microservices Architecture

**ADR Number:** ADR-0001  
**Title:** Polyglot Go Microservices Architecture  
**Status:** Accepted  
**Date:** July 21, 2026  

---

## 1. Context
The platform requires a scalable, low-latency backend to support multi-user real-time chat, geo-proximity discovery, presence management, media scanning, compliance audit logging, and automated disaster recovery.

## 2. Problem Statement
Monolithic backend architectures introduce high deployment risks, tight coupling between independent domain features (e.g. video processing vs authentication), and resource contention under asynchronous WebSocket message surges.

## 3. Decision
Decompose backend capabilities into 10 decoupled, independently deployable Go microservices managed within a Go workspace (`go.work`). Each microservice adheres to Clean Architecture principles separating HTTP/gRPC transport, application use cases, domain logic, and persistence infrastructure.

## 4. Evidence
* **Go Workspace Configuration:** [`go.work:3-17`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/go.work#L3-L17)
* **Auth Microservice Entry:** [`apps/backend/services/auth/cmd/auth/main.go:1-60`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/auth/cmd/auth/main.go#L1-L60)
* **Chat Microservice Entry:** [`apps/backend/services/chat/cmd/chat/main.go:1-130`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/chat/cmd/chat/main.go#L1-L130)
* **Nearby Microservice Entry:** [`apps/backend/services/nearby/cmd/nearby/main.go:1-120`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/nearby/cmd/nearby/main.go#L1-L120)

## 5. Alternatives Considered
* **Monolithic Go Backend:** Rejected due to lack of independent service scaling and high blast radius during deployment failures.
* **Node.js / TypeScript Microservices:** Rejected due to higher runtime memory footprint and reduced Go concurrency efficiency under high-throughput WebSocket IO.

## 6. Tradeoffs
* **Increased Operational Overhead:** Requires container orchestration, Kubernetes manifests, and service health management across 10 distinct binaries.
* **Complex Cross-Service Communication:** Interservice sync/async network overhead replaces direct in-memory function calls.

## 7. Consequences
* Independent scaling and deployment of services (e.g. scaling Chat service replicas independently of Auth).
* Enforced boundary isolation between domain models.

## 8. Risks
* Network latency across inter-service HTTP/gRPC boundaries.
* Potential connection pool exhaustion if database connections are not multiplexed.

## 9. Future Considerations
* Introduce service mesh control plane (Linkerd/Istio) for dynamic mTLS and inter-service discovery.
