# ADR 0011: API Gateway Reverse Proxy, Rate Limiting, & Circuit Breaking

**ADR Number:** ADR-0011  
**Title:** API Gateway Reverse Proxy, Rate Limiting, & Circuit Breaking  
**Status:** Accepted  
**Date:** July 21, 2026  

---

## 1. Context
The microservice backend needs a single ingress proxy for TLS termination, central authentication verification, IP sliding-window rate limiting, circuit breaker protection, Gzip compression, and HTTP header security.

## 2. Problem Statement
Exposing internal microservice endpoints directly to the public internet risks unauthorized access, DDoS flooding, un-sanitized headers, and cascading service crashes during upstream microservice outages.

## 3. Decision
Implement an API Gateway reverse proxy layer (`apps/backend/services/gateway`). The Gateway incorporates:
* **Circuit Breakers:** State machine (CLOSED, OPEN, HALF-OPEN) with 5-failure threshold and 10s cooldown ([`router.go:34-99`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/gateway/internal/transport/http/router.go#L34-L99)).
* **IP Rate Limiting:** Sliding-window rate limiters ([`router.go:122-146`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/gateway/internal/transport/http/router.go#L122-L146)).
* **Security Headers:** Enforces CSP, HSTS, X-Frame-Options ([`router.go:366-376`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/gateway/internal/transport/http/router.go#L366-L376)).
* **JWT Verification:** Central authentication validation ([`router.go:463-539`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/gateway/internal/transport/http/router.go#L463-L539)).

## 4. Evidence
* **Gateway Multiplexer & Router:** [`apps/backend/services/gateway/internal/transport/http/router.go:34-539`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/gateway/internal/transport/http/router.go#L34-L539)
* **TLS Enforcer & Entry:** [`apps/backend/services/gateway/cmd/gateway/main.go:61-153`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/gateway/cmd/gateway/main.go#L61-L153)

## 5. Alternatives Considered
* **Kong / Envoy Gateway:** Rejected to maintain zero third-party dependency footprint in Go code workspace and allow custom in-process circuit breaker fine-tuning.

## 6. Tradeoffs
* Gateway introduces single hop latency (~1-2ms).
* Centralized router logic creates a large core file (`router.go`) requiring future modular refactoring.

## 7. Consequences
* Unified ingress protection and threat mitigation.
* Upstream microservices isolated behind private network namespaces.

## 8. Risks
* Gateway router file complexity causing regression risks during route updates.

## 9. Future Considerations
* Refactor `router.go` into modular handler packages (`rate_limiter.go`, `circuit_breaker.go`).
