# ADR 0012: Authentication via JWT & Keycloak Identity Management

**ADR Number:** ADR-0012  
**Title:** Authentication via JWT & Keycloak Identity Management  
**Status:** Accepted  
**Date:** July 21, 2026  

---

## 1. Context
The platform requires secure stateless identity assertion, user login, bcrypt password hashing, token validation, and claim propagation across API routes.

## 2. Problem Statement
Stateful session-based authentication requires shared session database lookups on every API request, reducing throughput and creating a central bottleneck under high request concurrency.

## 3. Decision
Adopt stateless JSON Web Tokens (JWT) for API request authentication. The Auth service hashes credentials using bcrypt work factor 12 ([`auth_usecase.go:22`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/auth/internal/application/auth_usecase.go#L22)), while the Gateway validates JWT claims and enforces algorithm verification ([`router.go:463-539`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/gateway/internal/transport/http/router.go#L463-L539)) before forwarding request contexts (`X-User-Id`, `X-User-Role`) to upstream microservices.

## 4. Evidence
* **Auth Validation Middleware:** [`apps/backend/services/gateway/internal/transport/http/router.go:424-461`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/gateway/internal/transport/http/router.go#L424-L461)
* **JWT Algorithm Enforcement:** [`apps/backend/services/gateway/internal/transport/http/router.go:463-539`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/gateway/internal/transport/http/router.go#L463-L539)
* **Bcrypt Work Factor 12 Hashing:** [`apps/backend/services/auth/internal/application/auth_usecase.go:22`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/auth/internal/application/auth_usecase.go#L22) and [`line 99`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/auth/internal/application/auth_usecase.go#L99)

## 5. Alternatives Considered
* **Opaque Session Tokens:** Rejected due to database lookup latency per HTTP request.
* **Basic Auth:** Rejected due to plain credentials header re-transmission risks.

## 6. Tradeoffs
* JWTs cannot be immediately revoked prior to expiry without a Redis token blacklist lookup.
* Symmetric HMAC key fallbacks require strict removal in production environments.

## 7. Consequences
* Zero-database-lookup authentication checks at the API Gateway.
* Standardized identity context headers forwarded to internal microservices.

## 8. Risks
* Shared symmetric fallback keys exposing token forgery vulnerability if environment variables are missing (mitigated by P0 roadmap task).

## 9. Future Considerations
* Complete migration to asymmetric RS256 token verification using Keycloak OIDC JWKS endpoints.
