# Production Implementation Roadmap

**Author:** Google Principal Engineer & Technical Program Lead  
**Repository:** EasyChat / Nearby Connect Monorepo  
**Date:** July 21, 2026  
**Status:** Approved Master Implementation Roadmap  
**Target Document:** `docs/project/implementation-roadmap.md`  
**Input Baselines:**
- `docs/reports/audit-validation.md`
- `docs/reports/production-readiness-gap.md`
- `docs/project/engineering-backlog.md`

---

## Executive Summary

This implementation roadmap establishes the sequential, multi-phase engineering plan required to resolve all validated audit findings, production readiness blockers, and security/reliability risks across the monorepo. Every task in this roadmap traces directly to empirical evidence documented in [`docs/reports/audit-validation.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/audit-validation.md), [`docs/reports/production-readiness-gap.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/production-readiness-gap.md), and [`docs/project/engineering-backlog.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/project/engineering-backlog.md).

No work is invented or speculative. Implementation follows strict priority ordering ($P0 \rightarrow P1 \rightarrow P2 \rightarrow P3$) under enterprise GitOps and CI/CD controls.

---

## Phase 1 – Critical Production Blockers (P0)

### 1. Objective
Eliminate all P0 compile-time errors, security vulnerabilities in version control, hardcoded secret leaks, missing end-to-end message encryption, build version mismatches, and Helm connection string errors that block CI/CD pipeline execution and basic deployment safety.

### 2. Scope
Fix Flutter widget test type mismatches, rotate and externalize hardcoded credentials from Helm templates, implement end-to-end message payload encryption, align Go module versions across the workspace and CI runner, and construct full PostgreSQL connection strings in Helm deployment templates.

### 3. Tasks
* **Task 1.1: Fix Flutter Test Type Mismatches**
  * **Traceability:** Backlog `P0-1`, Audit Verified `#1` & `#2`, PRR Section 6.
  * **Source Evidence:** [`apps/frontend/test/widget_test.dart:55`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/test/widget_test.dart#L55) returns `Stream<List<dynamic>>` instead of `Stream<List<MessageEntity>>`; [`line 18`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/test/widget_test.dart#L18) `FakeWebSocketClient` missing `implements WebSocketClient`.
  * **Action:** Update return type to `Stream<List<MessageEntity>>` and add `implements WebSocketClient` to test fake.
* **Task 1.2: Remove Hardcoded Secrets from Helm Manifests**
  * **Traceability:** Backlog `P0-2`, Audit Verified `#6`, PRR Section 3.
  * **Source Evidence:** Plaintext credentials committed in [`infrastructure/helm/easychat/templates/secrets.yaml:8-16`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/helm/easychat/templates/secrets.yaml#L8-L16).
  * **Action:** Migrate credentials to Kubernetes ExternalSecrets Operator / Vault integration; rotate DB, AWS, and JWT keys.
* **Task 1.3: Implement End-to-End Message Payload Encryption**
  * **Traceability:** Backlog `P0-3`, Audit Verified `#12`, PRR Section 3.
  * **Source Evidence:** Plaintext byte casting in [`apps/frontend/lib/features/chat/data/chat_repository.dart:58`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/lib/features/chat/data/chat_repository.dart#L58) and Base64 encoding at [`line 75`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/lib/features/chat/data/chat_repository.dart#L75); proto schema expects encrypted bytes ([`proto/nearby/v1/chat.proto:60-64`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/proto/nearby/v1/chat.proto#L60-L64)).
  * **Action:** Implement TweetNaCl AEAD payload encryption before transmission; add key management logic.
* **Task 1.4: Align Go Workspace Compiler Versions**
  * **Traceability:** Backlog `P0-4`, Audit Verified `#8`, PRR Section 1.
  * **Source Evidence:** [`apps/backend/go.mod:3`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/go.mod#L3) (Go 1.24) vs [`apps/backend/services/nearby/go.mod:3`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/nearby/go.mod#L3) (Go 1.26.1) vs [`.github/workflows/ci.yml:22`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/.github/workflows/ci.yml#L22) (Go 1.22).
  * **Action:** Align all Go module versions and CI setup runners to Go 1.22 LTS.
* **Task 1.5: Fix Helm Database Connection URL Template**
  * **Traceability:** Backlog `P0-5`, Audit Verified `#7`, PRR Section 9.
  * **Source Evidence:** [`infrastructure/helm/easychat/templates/deployments.yaml:51-55`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/helm/easychat/templates/deployments.yaml#L51-L55) references password key only for `DATABASE_URL`.
  * **Action:** Construct complete connection string `postgresql://$(USER):$(PASS)@$(HOST):$(PORT)/$(DB)` in deployment env.

### 4. Files Expected to Change
* [`apps/frontend/test/widget_test.dart`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/test/widget_test.dart)
* [`apps/frontend/lib/features/chat/data/chat_repository.dart`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/lib/features/chat/data/chat_repository.dart)
* [`apps/backend/go.mod`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/go.mod)
* [`apps/backend/services/nearby/go.mod`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/nearby/go.mod)
* [`infrastructure/helm/easychat/templates/secrets.yaml`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/helm/easychat/templates/secrets.yaml)
* [`infrastructure/helm/easychat/templates/deployments.yaml`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/helm/easychat/templates/deployments.yaml)
* [`infrastructure/helm/easychat/values.yaml`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/helm/easychat/values.yaml)

### 5. Estimated Engineering Hours
* Task 1.1: 0.5 hours
* Task 1.2: 2.0 hours
* Task 1.3: 8.0 hours
* Task 1.4: 0.5 hours
* Task 1.5: 1.0 hour
* **Phase 1 Total:** 12.0 Engineering Hours

### 6. Dependencies
* Task 1.1 must precede frontend CI verification.
* Tasks 1.2 and 1.5 must be applied together during Helm chart refactoring.
* Task 1.3 requires passing widget tests (Task 1.1).

### 7. Risks
* Key rotation during Task 1.2 may break existing test connections if secrets are misaligned.
* Payload encryption (Task 1.3) could introduce serialization incompatibilities with legacy unencrypted packets.

### 8. Mitigation Strategy
* Maintain fallback decryption pathways for pre-encrypted offline Isar cache records.
* Perform dry-run Helm template rendering (`helm template`) before staging deployment.

### 9. Rollback Strategy
* Git revert phase commits; restore previous Helm secret references using backup manifests.

### 10. Testing Strategy
* **Unit Testing:** `flutter test` for `FakeChatRepository` and encryption round-trip.
* **Integration Testing:** `go test -v ./apps/backend/...` module compilation.
* **Contract Testing:** `go test -v ./tests/contracts/...` schema validation.
* **Load Testing:** N/A (deferred to Phase 3).
* **Security Testing:** Gosec scan (`reusable-go.yml`) and Trivy vulnerability check.
* **Chaos Testing:** N/A.

### 11. Validation Gate
* **Gate 1:** `flutter analyze` and `flutter test` pass with 0 errors.
* **Gate 2:** `go work sync` and `go test ./...` build cleanly across all microservices.
* **Gate 3:** Zero hardcoded plaintext credentials detected by Trivy scanner in Helm templates.

### 12. Deliverables
* Patched Flutter test mocks and encryption handlers.
* ExternalSecrets operator integration for Helm.
* Aligned `go.mod` files.
* Verified `DATABASE_URL` Helm templates.

### 13. Exit Criteria
* All 5 P0 blockers marked VERIFIED CLOSED; CI pipeline completes 100% green on `main`.

---

## Phase 2 – Security & Reliability (P0 / P1)

### 1. Objective
Eliminate authentication vulnerabilities, deploy database connection proxying, fix CI canary metric parsing, repair local Docker environment health checks, add configurable retention policies, and enforce WebSocket backpressure.

### 2. Scope
Migrate Gateway and microservices to asymmetric RS256 / JWKS validation, deploy PgBouncer connection pooling sidecars, refactor CD workflow Prometheus JSON parsing with `jq`, repair local Kafka health checks in `docker-compose.yml`, expose `RETENTION_PURGE_DAYS_THRESHOLD` in Helm ConfigMap, and add backpressure handling to WebSocket outbound buffers.

### 3. Tasks
* **Task 2.1: Mandate Asymmetric RS256 JWT Verification**
  * **Traceability:** PRR Action Item Matrix `P0`, PRR Section 3.
  * **Source Evidence:** Default fallback to symmetric key `test_secret_key` in [`apps/backend/services/gateway/cmd/gateway/main.go:43`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/gateway/cmd/gateway/main.go#L43); algorithm matching logic in [`router.go:463-539`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/gateway/internal/transport/http/router.go#L463-L539).
  * **Action:** Enforce mandatory RS256 token verification using Keycloak OIDC JWKS endpoint; fail startup if HMAC secret used in production.
* **Task 2.2: Deploy PgBouncer Connection Proxy**
  * **Traceability:** PRR Action Item Matrix `P1`, PRR Section 2.
  * **Source Evidence:** Hardcoded max connections `db.SetMaxOpenConns(25)` across 8 microservices without multiplexing ([`apps/backend/services/auth/cmd/auth/main.go:54`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/auth/cmd/auth/main.go#L54)).
  * **Action:** Add PgBouncer deployment/sidecar template to Helm chart to multiplex PostgreSQL connections.
* **Task 2.3: Replace Prometheus Canary Metric Parsing with `jq`**
  * **Traceability:** Backlog `P1-1`, Audit Verified `#14`, PRR Section 9.
  * **Source Evidence:** Fragile `grep -oP` JSON parsing in [`.github/workflows/cd.yml:166-168`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/.github/workflows/cd.yml#L166-L168).
  * **Action:** Replace shell regex parsing with `jq -r '.data.result[0].value[1]'` and add explicit fail-fast exit codes.
* **Task 2.4: Fix Docker Compose Kafka Health Check**
  * **Traceability:** Backlog `P1-2`, Audit Verified `#15`, PRR Section 8.
  * **Source Evidence:** Hardcoded binary path in [`docker-compose.yml:52-57`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docker-compose.yml#L52-L57).
  * **Action:** Replace path-dependent binary execution with robust TCP socket health check (`nc -z localhost 9092`).
* **Task 2.5: Add Retention Policy Threshold to Helm ConfigMap**
  * **Traceability:** Backlog `P1-3`, Audit Verified `#16`, PRR Section 11.
  * **Source Evidence:** `RETENTION_PURGE_DAYS_THRESHOLD` documented in [`database/README.md:31-34`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/database/README.md#L31-L34) but absent from [`infrastructure/helm/easychat/templates/configmap.yaml:1-19`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/helm/easychat/templates/configmap.yaml#L1-L19).
  * **Action:** Expose `RETENTION_PURGE_DAYS_THRESHOLD` in `values.yaml` and inject into `configmap.yaml`.
* **Task 2.6: Implement WebSocket Outbound Buffer Backpressure**
  * **Traceability:** Backlog `P1-4`, Audit Verified `#13`, PRR Section 2.
  * **Source Evidence:** Soft cap at 500 items with `removeAt(0)` dropping packets in [`apps/frontend/lib/core/network/websocket_client.dart:92-99`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/lib/core/network/websocket_client.dart#L92-L99).
  * **Action:** Add backpressure callback signaling and queue depth monitoring to prevent silent packet drops.

### 4. Files Expected to Change
* [`apps/backend/services/gateway/cmd/gateway/main.go`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/gateway/cmd/gateway/main.go)
* [`apps/backend/services/gateway/internal/transport/http/router.go`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/gateway/internal/transport/http/router.go)
* [`docker-compose.yml`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docker-compose.yml)
* [`.github/workflows/cd.yml`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/.github/workflows/cd.yml)
* [`infrastructure/helm/easychat/templates/configmap.yaml`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/helm/easychat/templates/configmap.yaml)
* [`infrastructure/helm/easychat/values.yaml`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/helm/easychat/values.yaml)
* [`apps/frontend/lib/core/network/websocket_client.dart`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/lib/core/network/websocket_client.dart)

### 5. Estimated Engineering Hours
* Task 2.1: 3.0 hours
* Task 2.2: 4.0 hours
* Task 2.3: 1.0 hour
* Task 2.4: 0.5 hours
* Task 2.5: 1.0 hour
* Task 2.6: 1.0 hour
* **Phase 2 Total:** 10.5 Engineering Hours

### 6. Dependencies
* Phase 1 validation gate must pass.
* PgBouncer deployment (Task 2.2) requires updating DB connection parameters in Helm.

### 7. Risks
* JWKS key retrieval failure could block external user authentication if Keycloak endpoint is unreachable.
* Incorrect PgBouncer transaction pooling mode might interfere with named prepared statements.

### 8. Mitigation Strategy
* Configure fallback cached JWKS keys in Gateway router with 15-minute TTL ([`router.go:215`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/gateway/internal/transport/http/router.go#L215)).
* Set PgBouncer pooling mode to `session` or `transaction` with binary protocol prepared statement support.

### 9. Rollback Strategy
* Revert Helm deployment values to direct database connections; restore symmetric JWT verification flags in staging.

### 10. Testing Strategy
* **Unit Testing:** JWKS token validation tests in `router_test.go`.
* **Integration Testing:** Local environment launch via `make up` to verify Kafka container health.
* **Contract Testing:** Verify JWT claims header injection in downstream services (`X-User-Id`, `X-User-Role`).
* **Load Testing:** Buffer stress testing in Flutter test suite.
* **Security Testing:** Gosec security scan.
* **Chaos Testing:** N/A.

### 11. Validation Gate
* **Gate 1:** `make up` successfully launches all containers with 100% healthy statuses.
* **Gate 2:** Gateway rejects non-RS256 tokens when algorithm policy is active.
* **Gate 3:** Canary parsing test correctly detects simulated 2% HTTP error rate and triggers rollback.

### 12. Deliverables
* Asymmetric RS256 token validation engine.
* PgBouncer Helm template.
* `jq`-based canary metric evaluation script.
* Updated `docker-compose.yml` and `configmap.yaml`.

### 13. Exit Criteria
* All Phase 2 tasks deployed to Staging and validated against security and deployment criteria.

---

## Phase 3 – Scalability & Performance (P1 / P2)

### 1. Objective
Verify and optimize end-to-end performance under load, conduct feature verification audits for BLE scanning, read receipt state machines, and presence Redis TTLs, and automate load testing.

### 2. Scope
Audit BLE scanning data pipeline, verify end-to-end read receipt state transitions (SENT $\rightarrow$ DELIVERED $\rightarrow$ READ), implement Redis TTL expiration on presence heartbeats, and automate k6 performance regression benchmarking in CI/CD.

### 3. Tasks
* **Task 3.1: Verify BLE Scanning Data Flow & Provider Integration**
  * **Traceability:** Backlog `P2-1`, Audit Uninspected `#1`, PRR Section 4.
  * **Source Evidence:** Mock data in [`apps/frontend/lib/features/nearby/domain/proximity_user.dart:22-46`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/lib/features/nearby/domain/proximity_user.dart#L22-L46); `BatteryOptimizer` BLE triggers in [`apps/frontend/lib/main.dart:100`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/lib/main.dart#L100).
  * **Action:** Trace BLE scan results to `proximityUsersProvider` and verify server-side H3 grid query execution.
* **Task 3.2: Verify Read Receipt End-to-End State Machine**
  * **Traceability:** Backlog `P2-2`, Audit Uninspected `#2`, PRR Section 2.
  * **Source Evidence:** `sendReadReceipt()` in [`apps/frontend/lib/features/chat/data/chat_repository.dart:137`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/lib/features/chat/data/chat_repository.dart#L137); receipt packet processing in [`apps/backend/services/chat/internal/transport/websocket/server.go:345`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/chat/internal/transport/websocket/server.go#L345).
  * **Action:** Validate SENT $\rightarrow$ DELIVERED $\rightarrow$ READ transitions across WebSocket clients and database persistence.
* **Task 3.3: Enforce Redis TTL Expiration on Presence Keys**
  * **Traceability:** Backlog `P2-3`, Audit Uninspected `#3`, PRR Section 9.
  * **Source Evidence:** Heartbeat handling accepts updates in [`apps/backend/services/presence/cmd/presence/main.go:73-104`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/presence/cmd/presence/main.go#L73-L104); verify Redis key TTL settings in repository.
  * **Action:** Enforce 60-second Redis TTL (`EXPIRE`) on device presence keys to prevent stale data accumulation.
* **Task 3.4: Automate k6 Load Testing in CI/CD Pipeline**
  * **Traceability:** PRR Action Item Matrix `P2`, PRR Section 5.
  * **Source Evidence:** Existing k6 load test script [`tests/load/load_test.js:1`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/tests/load/load_test.js#L1).
  * **Action:** Add automated k6 performance regression step in `cd.yml` for staging deployment runs.

### 4. Files Expected to Change
* [`apps/frontend/lib/features/nearby/presentation/nearby_screen.dart`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/lib/features/nearby/presentation/nearby_screen.dart)
* [`apps/backend/services/presence/internal/infrastructure/cache/redis.go`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/presence/internal/infrastructure/cache/redis.go)
* [`.github/workflows/cd.yml`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/.github/workflows/cd.yml)

### 5. Estimated Engineering Hours
* Task 3.1: 4.0 hours
* Task 3.2: 4.0 hours
* Task 3.3: 2.0 hours
* Task 3.4: 2.0 hours
* **Phase 3 Total:** 12.0 Engineering Hours

### 6. Dependencies
* Phase 2 validation gate must pass.
* k6 load test requires active Staging environment with PgBouncer.

### 7. Risks
* High-frequency presence TTL expirations could increase Redis CPU load if key counts scale rapidly.

### 8. Mitigation Strategy
* Use efficient Redis hashes (`presence:{userID}`) with active sliding expiration windows.

### 9. Rollback Strategy
* Disable automated k6 step in workflow if staging cluster capacity causes false build failures.

### 10. Testing Strategy
* **Unit Testing:** Redis TTL expiration unit tests.
* **Integration Testing:** End-to-end WebSocket receipt delivery verification.
* **Contract Testing:** Validate `StreamPacket` delivery receipt protobuf mapping.
* **Load Testing:** k6 simulation (10,000 virtual users, $p_{95} < 100\text{ms}$).
* **Security Testing:** N/A.
* **Chaos Testing:** N/A.

### 11. Validation Gate
* **Gate 1:** k6 load test executes with 0% error rate and $p_{95}$ latency $< 100\text{ms}$.
* **Gate 2:** Stale presence keys automatically expire after 60 seconds without updates.
* **Gate 3:** Read receipt delivery ACK round-trip verified under end-to-end integration test.

### 12. Deliverables
* Verified presence Redis TTL expiration logic.
* Automated k6 performance regression CI job step.
* Audit report for BLE scanning integration.

### 13. Exit Criteria
* System meets all performance and responsiveness targets under simulated 10k user load.

---

## Phase 4 – Operations & Platform Hardening (P2 / P3)

### 1. Objective
Harden platform maintainability, refactor complex gateway god files, eliminate presentation-layer architecture violations in Flutter, generate Protobuf API documentation, and compile comprehensive SRE operational runbooks.

### 2. Scope
Refactor [`router.go`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/gateway/internal/transport/http/router.go#L1) into modular handlers, route Flutter `NearbyScreen` actions through `ChatController`, update [`scripts/generate_proto.sh`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/scripts/generate_proto.sh#L1) to generate Protobuf Markdown docs, and write SRE runbooks for failover, partition expansion, and incident handling.

### 3. Tasks
* **Task 4.1: Refactor Gateway Router God Package**
  * **Traceability:** PRR Action Item Matrix `P2`, PRR Section 19.
  * **Source Evidence:** 698-line god file in [`apps/backend/services/gateway/internal/transport/http/router.go:1-698`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/gateway/internal/transport/http/router.go#L1-L698).
  * **Action:** Decompose `router.go` into `rate_limiter.go`, `circuit_breaker.go`, `jwt_validator.go`, and `proxy_handler.go`.
* **Task 4.2: Fix Flutter Presentation-to-Repository Layer Violation**
  * **Traceability:** PRR Action Item Matrix `P2`, PRR Section 3.
  * **Source Evidence:** Direct invocation of `chatRepositoryProvider` inside `NearbyScreen` widget ([`apps/frontend/lib/features/nearby/presentation/nearby_screen.dart:156`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/lib/features/nearby/presentation/nearby_screen.dart#L156)).
  * **Action:** Encapsulate room creation logic within `ChatController` / Application usecase.
* **Task 4.3: Generate Protobuf API Documentation**
  * **Traceability:** Backlog `P3-1`, Audit Section 9.
  * **Source Evidence:** Lack of formatted reference docs for 8 proto files in [`proto/nearby/v1/*.proto`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/proto/nearby/v1/nearby.proto#L1).
  * **Action:** Add `protoc-gen-doc` plugin execution step to [`scripts/generate_proto.sh`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/scripts/generate_proto.sh#L54) to generate `docs/api/protobuf.md`.
* **Task 4.4: Compile SRE Runbooks and Operational Playbooks**
  * **Traceability:** Backlog `P3-2`, Audit Section 9.
  * **Source Evidence:** Absence of procedural runbooks in repository.
  * **Action:** Write playbooks for DB partition expansion, Postgres replica promotion, Redis Sentinel failover, canary rollback, and pod scaling in `docs/sre/runbooks.md`.

### 4. Files Expected to Change
* [`apps/backend/services/gateway/internal/transport/http/router.go`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/gateway/internal/transport/http/router.go)
* [`apps/frontend/lib/features/nearby/presentation/nearby_screen.dart`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/lib/features/nearby/presentation/nearby_screen.dart)
* [`scripts/generate_proto.sh`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/scripts/generate_proto.sh)
* [`docs/sre/runbooks.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/sre/runbooks.md)

### 5. Estimated Engineering Hours
* Task 4.1: 3.0 hours
* Task 4.2: 1.0 hour
* Task 4.3: 2.0 hours
* Task 4.4: 4.0 hours
* **Phase 4 Total:** 10.0 Engineering Hours

### 6. Dependencies
* Phase 3 validation gate must pass.

### 7. Risks
* Refactoring `router.go` could introduce regressions in middleware chaining order if not thoroughly covered by tests.

### 8. Mitigation Strategy
* Execute existing router unit and adversarial tests (`router_test.go`, `adversarial_validation_test.go`) before and after refactoring.

### 9. Rollback Strategy
* Revert modular refactoring commits if regression tests fail.

### 10. Testing Strategy
* **Unit Testing:** `go test -v ./apps/backend/services/gateway/...`.
* **Integration Testing:** Full Gateway reverse proxy integration test.
* **Contract Testing:** Protobuf documentation syntax validation.
* **Load Testing:** N/A.
* **Security Testing:** Gosec static analysis.
* **Chaos Testing:** Chaos Mesh network partition simulation (`tests/chaos/network_chaos.yaml`).

### 11. Validation Gate
* **Gate 1:** All Gateway middleware tests pass with 0 regressions.
* **Gate 2:** `scripts/generate_proto.sh` successfully outputs `docs/api/protobuf.md`.
* **Gate 3:** SRE runbooks validated via dry-run simulation.

### 12. Deliverables
* Modular Gateway router package structure.
* Clean Architecture compliant Flutter `NearbyScreen`.
* Generated Protobuf API documentation.
* Operational SRE runbooks.

### 13. Exit Criteria
* Code refactoring complete, tests green, and documentation published.

---

## Phase 5 – Verification & Production Readiness

### 1. Objective
Execute final production certification, validate multi-region Disaster Recovery failover drills, confirm full GDPR compliance operational readiness, and verify 100/100 PRR score.

### 2. Scope
Execute full end-to-end chaos engineering failover tests, conduct production certification audit, verify automated Canary release workflow, and finalize Production Go/No-Go decision.

### 3. Tasks
* **Task 5.1: Execute Automated Disaster Recovery Failover Drill**
  * **Traceability:** PRR Section 10, [`apps/backend/services/dr-controller/main.go:255`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/dr-controller/main.go#L255).
  * **Source Evidence:** DR Controller operator failover logic and fencing tokens ([`main.go:95`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/dr-controller/main.go#L95)).
  * **Action:** Trigger simulated primary region outage using `SIMULATE_FAILOVER=true` and verify RTO $\le$ 5m, RPO $\le$ 30s SLA compliance.
* **Task 5.2: Execute End-to-End GDPR Data Erasure & Export Certification**
  * **Traceability:** PRR Section 11, [`apps/backend/services/compliance/compliance.go:329`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/compliance/compliance.go#L329).
  * **Source Evidence:** Compliance service Art.17 erasure and Art.20 export handlers.
  * **Action:** Run automated integration test verifying complete data cascade deletion and tamper-evident audit log hashing.
* **Task 5.3: Final PRR Audit & Go/No-Go Signoff**
  * **Traceability:** PRR Section 20.
  * **Action:** Validate all P0, P1, P2, and P3 action items closed; verify score reaches 100/100.

### 4. Files Expected to Change
* [`docs/reports/production-readiness-gap.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/production-readiness-gap.md) (Update final status)
* [`docs/production_certification_report.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/production_certification_report.md)

### 5. Estimated Engineering Hours
* Task 5.1: 2.0 hours
* Task 5.2: 2.0 hours
* Task 5.3: 1.0 hour
* **Phase 5 Total:** 5.0 Engineering Hours

### 6. Dependencies
* Phases 1 through 4 completed and validated.

### 7. Risks
* Simulated failover drill could cause temporary test cluster instability if fencing tokens do not clear.

### 8. Mitigation Strategy
* Execute drill against dedicated staging environment using `resetToHealthyPrimary()` reset helpers ([`main.go:312`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/dr-controller/main.go#L312)).

### 9. Rollback Strategy
* Re-arm primary region DR lease lock via `DRController.resetToHealthyPrimary()`.

### 10. Testing Strategy
* **Unit Testing:** N/A.
* **Integration Testing:** GDPR compliance export/erasure validation.
* **Contract Testing:** Full API contract sweep.
* **Load Testing:** Concurrent load during DR failover drill.
* **Security Testing:** Final Trivy & Cosign verification.
* **Chaos Testing:** Pod failure chaos ([`pod_failure_chaos.yaml`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/tests/chaos/pod_failure_chaos.yaml#L1)).

### 11. Validation Gate
* **Gate 1:** DR Failover SLA verified: RTO $\le$ 5 minutes, RPO $\le$ 30 seconds.
* **Gate 2:** 100% of P0, P1, and P2 action items verified closed.
* **Gate 3:** Signed Production Certification Report generated.

### 12. Deliverables
* Validated DR Failover execution report.
* GDPR compliance verification log.
* Final Production Readiness Review Signoff.

### 13. Exit Criteria
* Production Readiness Score reaches **100 / 100**; Production Recommendation updated to **FULL GO**.

---

## Implementation Timeline

```
Week 1 (Days 1–5):   [Phase 1: Critical Production Blockers] (12.0h)
                     [Phase 2: Security & Reliability]      (10.5h)
-------------------------------------------------------------------
Week 2 (Days 6–10):  [Phase 3: Scalability & Performance]    (12.0h)
                     [Phase 4: Operations & Hardening]       (10.0h)
-------------------------------------------------------------------
Week 3 (Days 11–12): [Phase 5: Final Readiness & Verification] (5.0h)
```

---

## Engineering Resource Plan

| Role | Responsibilities | Assigned Phases | Total Allocated Hours |
| :--- | :--- | :--- | :--- |
| **Backend Tech Lead** | Go version alignment, RS256 JWT, E2E Encryption, Gateway Refactoring | Phase 1, 2, 4 | 16.5 Hours |
| **Frontend Engineer** | Widget test fixes, E2E Encryption, WS Backpressure, Layer fixes | Phase 1, 2, 3, 4 | 14.5 Hours |
| **DevOps / SRE Lead** | Helm secret externalization, PgBouncer, Canary `jq`, DR Drill | Phase 1, 2, 3, 5 | 14.5 Hours |
| **Security / Compliance Specialist** | Cryptographic review, GDPR verification, PRR Signoff | Phase 2, 5 | 4.0 Hours |
| **Total Engineering Allocation** | | | **49.5 Hours** |

---

## Critical Path Analysis

The critical path spans 5 dependent milestones that dictate minimum time-to-production:

```
[Task 1.1: Fix Flutter Test Types] 
        │
        v
[Task 1.3: End-to-End Encryption] 
        │
        v
[Task 2.1: Asymmetric RS256 JWT] 
        │
        v
[Task 2.2: PgBouncer Connection Proxy] 
        │
        v
[Task 3.4: Automated k6 Load Testing] 
        │
        v
[Task 5.1: Disaster Recovery Failover Drill] ──> [PRODUCTION GO SIGNOFF]
```

---

## Risk Register

| Risk ID | Risk Description | Severity | Impact Area | Mitigation Strategy | Owner |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **RSK-01** | Encryption key exchange failure under offline network conditions | HIGH | Chat Feature | Implement local key caching in Isar DB with fallback retry | Frontend Lead |
| **RSK-02** | PostgreSQL connection starvation during HPA pod autoscaling spikes | HIGH | System Availability | Deploy PgBouncer sidecars (Task 2.2) before scaling limits | DevOps Lead |
| **RSK-03** | Keycloak JWKS endpoint network timeout during Gateway startup | MEDIUM | Authentication | Gateway caches public keys locally with 15m TTL fallback | Backend Lead |
| **RSK-04** | Prometheus metric format drift breaking canary verification | LOW | Deployment | Parse responses using `jq` with explicit schema checks | SRE Lead |

---

## Release Strategy

1. **GitOps Strategy:** Declarative Helm deployment updates managed via GitHub Actions CD (`.github/workflows/cd.yml`).
2. **Environment Progression:** `development` $\rightarrow$ `qa` $\rightarrow$ `staging` (Blue/Green) $\rightarrow$ `production` (Canary).
3. **Staging Promotion:** Deploy to Green standby environment; execute smoke tests; swap active ingress selector.
4. **Production Deployment:**
   * Deploy 10% Canary release weight ([`cd.yml:146`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/.github/workflows/cd.yml#L146)).
   * Poll Prometheus HTTP 5xx error rate for 5 minutes via `jq`.
   * Automatically execute `helm rollback` if error rate $> 1.0\%$.
   * Promote to 100% traffic weight upon clean metric verification.

---

## Production Go/No-Go Checklist

* [ ] **P0-1:** Flutter test widget type mismatches resolved (`flutter test` passes).
* [ ] **P0-2:** Hardcoded secrets removed from Helm manifests and rotated.
* [ ] **P0-3:** End-to-end payload encryption implemented and verified.
* [ ] **P0-4:** Go workspace compiler versions aligned to Go 1.22 LTS.
* [ ] **P0-5:** `DATABASE_URL` Helm template constructs complete connection string.
* [ ] **P1-1:** Prometheus canary metric parsing converted to `jq` with fail-fast validation.
* [ ] **P1-2:** Docker Compose Kafka health check updated to TCP socket check.
* [ ] **P1-3:** `RETENTION_PURGE_DAYS_THRESHOLD` injected into Helm ConfigMap.
* [ ] **P1-4:** WebSocket outbound buffer backpressure callbacks implemented.
* [ ] **P2-1:** RS256 JWKS asymmetric token validation enforced in Gateway.
* [ ] **P2-2:** PgBouncer connection proxy deployed in Helm templates.
* [ ] **P3-1:** Automated DR failover drill executed with RTO $\le 5\text{m}$, RPO $\le 30\text{s}$.
* [ ] **P3-2:** Final PRR score verified at 100/100.

---

## Overall Estimated Effort

| Phase | Description | Total Hours |
| :--- | :--- | :--- |
| **Phase 1** | Critical Production Blockers (P0) | 12.0 Hours |
| **Phase 2** | Security & Reliability (P0 / P1) | 10.5 Hours |
| **Phase 3** | Scalability & Performance (P1 / P2) | 12.0 Hours |
| **Phase 4** | Operations & Platform Hardening (P2 / P3) | 10.0 Hours |
| **Phase 5** | Verification & Production Readiness | 5.0 Hours |
| **TOTAL** | **Full Implementation Roadmap Effort** | **49.5 Engineering Hours** |

---

## Expected Production Readiness Score After Completion

# 100 / 100

### Production Recommendation Post-Completion: **FULL GO**

Upon completion of all 5 roadmap phases and verification against the exit criteria, all production blockers and risks will be closed, elevating the repository to 100% compliance with Google Production Engineering Standards.
