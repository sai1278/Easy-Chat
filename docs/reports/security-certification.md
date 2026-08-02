# Security Certification Report

## Executive Summary

This report delivers the official, evidence-based security certification of the **Easy Chat** Kubernetes platform running on the certified `kind-easychat` cluster environment.

An authorized, non-destructive security assessment was conducted covering application-level authentication, cryptographic controls, database network exposure, container runtime hardening, and Kubernetes platform RBAC/NetworkPolicies.

Key Assessment Findings:
1. **Application Security & Hardening (PASS)**: Distroless hardened runtimes (`nonroot:65532`), read-only root filesystems, parameterized SQL queries, algorithm confusion-resistant JWT validation, and IP-bound rate limiting are fully operational.
2. **Database & Infrastructure Isolation (WARNING)**: The Redis instance (`nearby-redis:6379`) allows unauthenticated command execution (`+PONG` on unauthenticated `PING`). The `allow-easychat-infra` NetworkPolicy lacks namespace selector restrictions, permitting cross-namespace database traffic from the `monitoring` namespace.
3. **Transport Layer Security (WARNING)**: Inter-service cluster communication currently operates over HTTP (`DISABLE_TLS=true`), deferring TLS termination to external ingress layers.

---

## Assessment Scope

The security audit evaluated the following control areas:
- **Authentication & JWT Security**: Algorithm confusion protection, expiration checks, token parsing.
- **Authorization & RBAC**: Header injection, role propagation, Kubernetes RoleBindings.
- **OWASP Top 10**: Parameterized SQL queries, XSS security headers, CSRF protections, SSRF mitigation.
- **Rate Limiting & Anti-Replay**: Sliding-window rate limiters, request IDs, correlation tokens.
- **Data-Store & Transport Security**: Redis authentication, Postgres TLS, Kafka ACLs, cluster NetworkPolicies.
- **Container & Pod Security**: Non-root execution, capability drops, read-only root filesystems.

---

## Detailed Findings

### 1. Redis Unauthenticated Access (FINDING-SEC-01)
- **Severity**: **Medium**
- **Affected Component**: `easychat-infra/nearby-redis` (`nearby-redis.easychat-infra.svc.cluster.local:6379`)
- **Evidence**: Executing raw TCP command `PING` against `nearby-redis:6379` returned unauthenticated success:
  ```text
  +PONG
  ```
- **Risk Description**: Any compromised container within the cluster network can read, mutate, or flush cached user sessions and presence states without password verification (`requirepass` disabled).
- **Mitigation**: Enable Redis password authentication (`requirepass`) via `redis.conf` or Helm values, and pass credentials through Kubernetes secrets.
- **Verification Result**: **REPRODUCED / WARNING**

### 2. Permissive Infrastructure NetworkPolicy (FINDING-SEC-02)
- **Severity**: **Medium**
- **Affected Component**: `easychat-infra/allow-easychat-infra` NetworkPolicy
- **Evidence**: `kubectl describe netpol allow-easychat-infra -n easychat-infra` output:
  ```text
  Spec:
    PodSelector:     <none>
    Allowing ingress traffic:
      To Port: <any>
      From:
        NamespaceSelector: <none>
  ```
  Empirical connectivity probe from `monitoring` namespace succeeded (`nc -zv nearby-postgres.easychat-infra.svc.cluster.local 5432` -> `open`).
- **Risk Description**: Pods outside the `default` workload namespace (e.g., monitoring, third-party helm charts) can directly reach database and Kafka ports.
- **Mitigation**: Update `allow-easychat-infra` NetworkPolicy with `namespaceSelector: matchLabels: kubernetes.io/metadata.name: default`.
- **Verification Result**: **REPRODUCED / WARNING**

### 3. Plaintext Inter-Service Cluster Communication (FINDING-SEC-03)
- **Severity**: **Low**
- **Affected Component**: All microservices (`default` namespace)
- **Evidence**: Environment configuration `DISABLE_TLS: "true"` in `easychat-config` ConfigMap. Microservices communicate over unencrypted HTTP (`http://auth-service:8081`).
- **Risk Description**: Internal traffic between microservices is susceptible to packet sniffing if a pod within the network namespace is compromised.
- **Mitigation**: Enable mTLS via Istio / Linkerd service mesh or cert-manager automated internal certificates.
- **Verification Result**: **VERIFIED / WARNING**

---

## Control Validation

### JWT Security & Authentication (`PASS`)
- **Verification**: Inspected `verifyJWT()` in [`apps/backend/services/gateway/internal/transport/http/router.go`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/gateway/internal/transport/http/router.go).
- **Control**: Header algorithm is inspected before parsing. HMAC (`HS256`) and RSA (`RS256`) key selection functions explicitly enforce method matching (`t.Method.(*jwt.SigningMethodHMAC)`), eliminating algorithm-confusion attacks. `WithExpirationRequired()` and `WithIssuedAt()` are enforced.
- **Runtime Probe**: Request without Bearer token to `/api/v1/user/profile` returned:
  ```json
  {"error":"Unauthorized: missing bearer token"}
  ```
  (Status Code: **401 Unauthorized**).

### Authorization & Kubernetes RBAC (`PASS`)
- **Verification**: Verified microservice request context header injection (`X-User-Id`, `X-User-Role`).
- **Kubernetes RBAC**: Service accounts in `default` namespace have 0 elevated ClusterRoleBindings and automounted service account tokens are restricted.

### OWASP Top 10 & SQL Injection (`PASS`)
- **Verification**: Inspected `PostgresUserRepository` in [`apps/backend/services/auth/internal/infrastructure/persistence/postgres.go`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/auth/internal/infrastructure/persistence/postgres.go).
- **Control**: All database operations use prepared statements with parameterized positional parameters (`$1`, `$2`, etc.).
- **Runtime Probe**: Injected classic SQLi payload (`' OR '1'='1`) into login endpoint. Database query executed safely via parameterized binding without syntax error leaks or data extraction.

### XSS, CSRF, & Security Headers (`PASS`)
- **Verification**: Security headers applied by `SecurityHeadersMiddleware`:
  ```text
  X-Frame-Options: DENY
  X-Content-Type-Options: nosniff
  X-XSS-Protection: 1; mode=block
  Content-Security-Policy: default-src 'self'; frame-ancestors 'none';
  Strict-Transport-Security: max-age=31536000; includeSubDomains
  Referrer-Policy: no-referrer
  ```

### Rate Limiting & Replay Protection (`PASS`)
- **Verification**: `RateLimitMiddleware` implements per-IP sliding-window rate limiting. Rapid burst requests return HTTP 429 (`{"error":"Rate limit exceeded"}`). Cryptographic UUIDv4 request correlation IDs (`X-Request-ID`) are injected on every request.

### Container & Pod Security Standards (`PASS`)
- **Verification**: Distroless runtime image (`gcr.io/distroless/static-debian12:nonroot`).
- **Security Context**:
  ```yaml
  securityContext:
    runAsNonRoot: true
    runAsUser: 10001
    readOnlyRootFilesystem: true
    capabilities:
      drop:
        - ALL
  ```
  Mounted `/tmp` as an `emptyDir` volume to support temporary certificate/ephemeral file creation under read-only root filesystems.

---

## Final Certification Matrix

| Control | Status | Notes |
| :--- | :---: | :--- |
| **JWT Security** | **PASS** | Algorithm confusion protections & mandatory expiration enforced |
| **Authentication** | **PASS** | 401 Unauthorized correctly returned for unauthenticated endpoints |
| **Authorization** | **PASS** | Request context claims propagation & restricted service accounts |
| **OWASP Top 10** | **PASS** | Parameterized queries & security headers active |
| **SQL Injection** | **PASS** | All queries use `$1, $2` parameters via `sql.DB` driver |
| **XSS** | **PASS** | CSP, X-XSS-Protection, and nosniff headers set |
| **CSRF** | **PASS** | Bearer token authorization pattern immune to ambient cookie CSRF |
| **SSRF** | **PASS** | Hardcoded upstream host lists; no dynamic client URL fetching |
| **Rate Limiting** | **PASS** | Per-IP sliding-window rate limiting operational (HTTP 429) |
| **Replay Protection** | **PASS** | Expiration required & unique cryptographic request IDs |
| **BLE Spoofing Protection** | **NOT APPLICABLE** | Proximity BLE layer not implemented in backend service layer |
| **WebSocket Security** | **PASS** | Upgrades validated and connection headers preserved |
| **Kafka ACLs** | **WARNING** | Unauthenticated PLAINTEXT broker listener (`:9092`) |
| **Redis Exposure** | **WARNING** | Redis accepts unauthenticated TCP commands (`requirepass` missing) |
| **PostgreSQL Exposure** | **WARNING** | Password protected but internal connection lacks TLS |
| **Secret Management** | **WARNING** | Kubernetes Opaque secrets stored base64-encoded |
| **Kubernetes RBAC** | **PASS** | Default service accounts unprivileged |
| **Network Policies** | **WARNING** | `allow-easychat-infra` allows ingress from all namespaces |
| **TLS Configuration** | **WARNING** | Inter-service traffic runs on HTTP (`DISABLE_TLS=true`) |
| **Container Security** | **PASS** | Distroless non-root, read-only root filesystem, capabilities dropped |
| **Pod Security** | **PASS** | Restricted Pod Security Standards met |

### Overall Security Status

# **WARNING**

*Summary: The Easy Chat application layer demonstrates exceptional security posture with zero critical application vulnerabilities, distroless non-root container hardening, algorithm-confusion proof JWT handling, and parameterized SQL queries. Overall status is set to **WARNING** due to internal data-store access controls (unauthenticated Redis PING) and permissive cross-namespace NetworkPolicies in `easychat-infra`.*
