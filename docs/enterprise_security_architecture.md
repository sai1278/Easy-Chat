# Enterprise Security Architecture Design
## Zero-Trust Infrastructure, OAuth2/OIDC, SPIRE Identity, WAF, and Runtime Hardening

---

## 1. Identity & Access Control (OAuth2 / OIDC)
Nearby Connect leverages Keycloak as the centralized OpenID Connect (OIDC) identity provider.

```
[ Mobile Client ] ──(Auth Code + PKCE)──► [ Keycloak OIDC ] ──(JWKS Public Key)──► [ Go API Middleware ]
                                                                                           │
                                                                                    (Validate claims)
                                                                                           ▼
                                                                                   [ Context Injection ]
```

### 1.1. Authorization Code Flow with PKCE
To protect client transactions, authentication utilizes the **Authorization Code Flow with Proof Key for Code Exchange (PKCE)**:
1.  **Code Verifier**: The client generates a high-entropy cryptographically secure random string `code_verifier`.
2.  **Code Challenge**: The client hashes the verifier with SHA256 (`code_challenge`) and registers it with Keycloak during redirect authorization.
3.  **Token Exchange**: Keycloak validates the `code_verifier` matching the challenge during token request exchange, eliminating authorization code interception vulnerabilities.

### 1.2. Backend JWT Validation
Go microservices intercept all requests using OIDC middleware (`auth.go`):
*   **JWKS Public Key Caching**: Public RSA verification keys are fetched from the JWKS provider endpoint (`/protocol/openid-connect/certs`) and cached locally.
*   **Signature Checking**: Verifies RS256 token signatures natively using RSA and SHA256 hashes.
*   **Claims Auditing**: Enforces standard checks for expiration (`exp`), issuer (`iss`), and audience (`aud`).
*   **RBAC Scopes**: Parses user roles and scopes to block unauthorized calls before handler routing.

---

## 2. SPIFFE/SPIRE Workload Identity

We implement zero-trust networking using **SPIFFE (Secure Production Identity Framework for Everyone)** and **SPIRE**:

*   **SPIRE Server**: The root Certificate Authority (CA) that manages trust bundles and workload registration.
*   **SPIRE Agent**: Runs as a daemonset on every node. It performs local kernel-level workload attestation (verifying pod namespaces, service accounts, and labels).
*   **Workload Registration (`spire-workloads.yaml`)**: Automatically registers pod specifications.
*   **Istio Integration**: SPIRE is configured as the custom CA provider for Istio. The Envoy sidecars query the SPIRE Agent via the Envoy SDS (Secret Discovery Service) API to retrieve **SVIDs** (SPIFFE Verifiable Identity Documents) in the form of X.509 certificates. mTLS is enforced using these SVIDs.

---

## 3. Ingress WAF & DDoS Shielding

Edge protections are enforced at the NGINX Ingress controller layer:

### 3.1. Web Application Firewall (WAF)
*   **Engine**: ModSecurity Web Application Firewall.
*   **Ruleset**: OWASP ModSecurity Core Rule Set (CRS) protecting against SQL Injection, Cross-Site Scripting (XSS), Command Injection, and Path Traversal.
*   **Logging**: Blocks anomalous queries, printing transaction logs to `/var/log/nginx/modsec_audit.log`.

### 3.2. DDoS Throttling & Rate Limiting
To defend against volumetric denial-of-service attempts, NGINX Ingress annotations enforce:
*   `limit-connections: "50"`: Limits a single source IP to a maximum of 50 concurrent TCP connections.
*   `limit-rps: "100"`: Throttles API requests to 100 requests/sec per IP.
*   `limit-burst: "150"`: Integrates token-bucket buffering to accommodate high burst events safely.

---

## 4. Runtime Protection & Supply Chain Verification

### 4.1. Falco Runtime Auditing
Falco agents monitor Linux kernel system calls to detect real-time anomalies:
*   Spawning interactive shells (`sh`, `bash`) inside Nearby Connect service pods.
*   Executing file writes on read-only root directories.
*   Suspicious syscalls indicating namespace escapes.

### 4.2. Kubernetes Audit Logs
Audits all cluster management commands, writing log entries when Secrets, ConfigMaps, or RBAC rules are updated.

### 4.3. Admission Control Signature Validation
Kyverno policies (`image-verification.yaml`) intercept pod deployments during the admission phase, validating that all images from `ghcr.io/easychat/*` are signed with our private Cosign key. Unsigned or modified image deployments are blocked automatically.
