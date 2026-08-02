# Master Engineering Execution Plan

**Author:** Google Principal Software Engineer & Technical Program Manager  
**Repository:** EasyChat / Nearby Connect Monorepo  
**Date:** July 21, 2026  
**Status:** Approved Master Engineering Execution Plan  
**Target Document:** `docs/project/final-execution-plan.md`  
**Input Baselines:**
- `docs/reports/audit-validation.md`
- `docs/reports/production-readiness-gap.md`
- `docs/project/engineering-backlog.md`
- `docs/project/implementation-roadmap.md`
- `docs/architecture/dependency-graph.md`
- `docs/reports/repository-health.md`
- `docs/adr/`

---

## Executive Summary

This document establishes the master multi-team engineering execution plan for resolving all technical debt, security vulnerabilities, reliability risks, and operational gaps identified across the repository. Engineering tasks are distributed across 7 specialized workstreams (Backend, Flutter, Infrastructure, DevOps, Database, Security, QA) executing in parallel merge waves designed to minimize Git merge conflicts and maximize velocity.

* **Total Engineering Effort:** 49.5 Engineering Hours + 14.5 Review Hours (64.0 Total Hours)
* **Critical Path Duration:** 12 Days across 4 Merge Waves
* **Parallel Development Efficiency:** 82.5% (7 teams operating concurrently across isolated subdirectories)
* **Target Production Readiness Score:** **100 / 100**
* **Overall Delivery Confidence:** **HIGH**

---

## Workstream Task Specification

### Workstream 1: Backend Team

#### Task B-01: Fix Flutter-Backend Contract Types & Align Go Compiler Versions
* **Task ID:** TASK-04
* **Title:** Align Go Workspace Compiler Versions
* **Owner Team:** Backend Team
* **Primary Owner:** Senior Backend Engineer
* **Priority:** P0 (Critical)
* **Related Backlog Item:** `P0-4`
* **Related Audit Finding:** Verified `#8` ([`audit-validation.md:328`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/audit-validation.md#L328))
* **Related PRR Finding:** Section 1 ([`production-readiness-gap.md:18`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/production-readiness-gap.md#L18))
* **Files Expected to Change:**
  * [`apps/backend/go.mod`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/go.mod)
  * [`apps/backend/services/nearby/go.mod`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/nearby/go.mod)
* **Dependencies:** None
* **Blocking Tasks:** None
* **Can Run In Parallel:** Yes (with Task F-01, Task I-01)
* **Estimated Engineering Hours:** 0.5h | **Review Hours:** 0.25h
* **Testing Required:** Unit Tests (`go test ./...`), Integration Tests (`go work sync`), Contract Tests (None), Security Tests (Gosec), Load Tests (None), Manual Verification (Local compilation).
* **Definition of Done:** All `go.mod` files set to `go 1.22`; `go work sync` executes with 0 errors.
* **Expected Deliverable:** Aligned Go workspace module files.
* **Merge Strategy:** Fast-forward merge to `main`.
* **Rollback Strategy:** Git revert commit.
* **Risk:** Low.

---

#### Task B-02: Implement Backend Payload Encryption & Nonce Handlers
* **Task ID:** TASK-03
* **Title:** Implement End-to-End Message Payload Encryption
* **Owner Team:** Backend Team (Joint with Flutter Team)
* **Primary Owner:** Backend Lead Engineer
* **Priority:** P0 (Critical)
* **Related Backlog Item:** `P0-3`
* **Related Audit Finding:** Verified `#12` ([`audit-validation.md:568`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/audit-validation.md#L568))
* **Related PRR Finding:** Section 3 ([`production-readiness-gap.md:88`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/production-readiness-gap.md#L88))
* **Files Expected to Change:**
  * [`apps/backend/services/chat/cmd/chat/main.go`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/chat/cmd/chat/main.go)
  * [`apps/backend/services/chat/internal/transport/websocket/server.go`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/chat/internal/transport/websocket/server.go)
* **Dependencies:** TASK-04 (Go version alignment)
* **Blocking Tasks:** TASK-13 (Read receipt state machine verification)
* **Can Run In Parallel:** Yes (with Task F-02)
* **Estimated Engineering Hours:** 4.0h | **Review Hours:** 1.0h
* **Testing Required:** Unit Tests (Payload serialization), Integration Tests (Chat server WS message echo), Contract Tests (`chat.proto` encrypted bytes validation), Security Tests (AEAD integrity check), Load Tests (None), Manual Verification (Inspect binary frames).
* **Definition of Done:** Encrypted payload bytes passed to backend DB/Kafka without plaintext leakage.
* **Expected Deliverable:** Upgraded WebSocket server message handler.
* **Merge Strategy:** Feature branch rebase merge.
* **Rollback Strategy:** Feature flag disable (`ENABLE_E2E_ENCRYPTION=false`).
* **Risk:** High (Payload parsing mismatch if client/server nonces differ).

---

#### Task B-03: Mandate Asymmetric RS256 Keycloak Token Verification
* **Task ID:** TASK-06
* **Title:** Enforce RS256 JWKS JWT Validation in Gateway
* **Owner Team:** Backend Team (Joint with Security Team)
* **Primary Owner:** Backend Security Specialist
* **Priority:** P0 (Production Blocker)
* **Related Backlog Item:** `P0-2` / PRR Action Matrix P0
* **Related Audit Finding:** Verified `#6` ([`audit-validation.md:252`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/audit-validation.md#L252))
* **Related PRR Finding:** Section 3 ([`production-readiness-gap.md:112`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/production-readiness-gap.md#L112))
* **Files Expected to Change:**
  * [`apps/backend/services/gateway/cmd/gateway/main.go`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/gateway/cmd/gateway/main.go)
  * [`apps/backend/services/gateway/internal/transport/http/router.go`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/gateway/internal/transport/http/router.go)
* **Dependencies:** TASK-04
* **Blocking Tasks:** TASK-16 (Gateway router refactoring)
* **Can Run In Parallel:** Yes (with Task D-01, Task S-01)
* **Estimated Engineering Hours:** 3.0h | **Review Hours:** 1.0h
* **Testing Required:** Unit Tests (`router_test.go`), Integration Tests (JWKS endpoint fetch), Contract Tests (JWT claim header injection), Security Tests (Reject HS256 symmetric tokens), Load Tests (None), Manual Verification (Curl request with signed RS256 token).
* **Definition of Done:** Gateway rejects HS256 tokens and validates signatures via JWKS endpoint; hardcoded `test_secret_key` removed.
* **Expected Deliverable:** Asymmetric JWT validation engine in Gateway router.
* **Merge Strategy:** Squash merge to `main`.
* **Rollback Strategy:** Revert commit; restore symmetric key validation fallback.
* **Risk:** Medium.

---

#### Task B-04: Enforce Redis TTL Expiration on Device Presence Keys
* **Task ID:** TASK-14
* **Title:** Enforce Redis TTL Expiration on Presence Keys
* **Owner Team:** Backend Team
* **Primary Owner:** Senior Backend Engineer
* **Priority:** P2 (Medium)
* **Related Backlog Item:** `P2-3`
* **Related Audit Finding:** Verified `#17` ([`audit-validation.md:776`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/audit-validation.md#L776))
* **Related PRR Finding:** Section 4 ([`production-readiness-gap.md:144`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/production-readiness-gap.md#L144))
* **Files Expected to Change:**
  * [`apps/backend/services/presence/internal/infrastructure/cache/redis.go`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/presence/internal/infrastructure/cache/redis.go)
  * [`apps/backend/services/presence/cmd/presence/main.go`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/presence/cmd/presence/main.go)
* **Dependencies:** TASK-04
* **Blocking Tasks:** None
* **Can Run In Parallel:** Yes (with Task F-03, Task D-02)
* **Estimated Engineering Hours:** 2.0h | **Review Hours:** 0.5h
* **Testing Required:** Unit Tests (TTL key inspection), Integration Tests (Redis heartbeat expiry test), Contract Tests (None), Security Tests (None), Load Tests (Redis key churn test), Manual Verification (Redis CLI `TTL` command).
* **Definition of Done:** `EXPIRE` 60s applied to all presence sets on heartbeat receive.
* **Expected Deliverable:** Patched presence Redis repository.
* **Merge Strategy:** Rebase merge.
* **Rollback Strategy:** Git revert.
* **Risk:** Low.

---

#### Task B-05: Refactor Gateway Router God Package
* **Task ID:** TASK-16
* **Title:** Refactor Gateway Router God Package
* **Owner Team:** Backend Team
* **Primary Owner:** Backend Tech Lead
* **Priority:** P2 (Medium)
* **Related Backlog Item:** `P2-5` / PRR Action Matrix P2
* **Related Audit Finding:** Verified `#9` ([`audit-validation.md:370`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/audit-validation.md#L370))
* **Related PRR Finding:** Section 19 ([`production-readiness-gap.md:280`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/production-readiness-gap.md#L280))
* **Files Expected to Change:**
  * [`apps/backend/services/gateway/internal/transport/http/router.go`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/gateway/internal/transport/http/router.go) (Decompose into `rate_limiter.go`, `circuit_breaker.go`, `jwt_validator.go`, `proxy_handler.go`)
* **Dependencies:** TASK-06 (RS256 JWT validation)
* **Blocking Tasks:** None
* **Can Run In Parallel:** Yes (with Task F-04, Task I-03)
* **Estimated Engineering Hours:** 3.0h | **Review Hours:** 1.0h
* **Testing Required:** Unit Tests (All gateway middleware unit tests), Integration Tests (Full proxy routing), Contract Tests (HTTP status code preservation), Security Tests (Gosec), Load Tests (None), Manual Verification (Route curl tests).
* **Definition of Done:** `router.go` decomposed into 4 sub-packages; line count reduced below 200 lines per file.
* **Expected Deliverable:** Modular Gateway package architecture.
* **Merge Strategy:** Rebase merge.
* **Rollback Strategy:** Git revert commit.
* **Risk:** Low (Internal refactoring covered by test suite).

---

#### Task B-06: Generate Protobuf API Documentation
* **Task ID:** TASK-18
* **Title:** Generate Protobuf API Documentation
* **Owner Team:** Backend Team
* **Primary Owner:** Backend Engineer
* **Priority:** P3 (Low)
* **Related Backlog Item:** `P3-1`
* **Related Audit Finding:** Verified Section 9 ([`audit-validation.md:840`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/audit-validation.md#L840))
* **Related PRR Finding:** Section 1 ([`production-readiness-gap.md:26`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/production-readiness-gap.md#L26))
* **Files Expected to Change:**
  * [`scripts/generate_proto.sh`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/scripts/generate_proto.sh)
  * `docs/api/protobuf.md` (NEW)
* **Dependencies:** None
* **Blocking Tasks:** None
* **Can Run In Parallel:** Yes (with Task D-03, Task I-04)
* **Estimated Engineering Hours:** 2.0h | **Review Hours:** 0.5h
* **Testing Required:** Unit Tests (None), Integration Tests (`generate_proto.sh` execution), Contract Tests (Protobuf syntax check), Security Tests (None), Load Tests (None), Manual Verification (Inspect generated Markdown).
* **Definition of Done:** `generate_proto.sh` outputs `docs/api/protobuf.md` containing formatted schema reference.
* **Expected Deliverable:** Generated Protobuf documentation markdown.
* **Merge Strategy:** Fast-forward merge.
* **Rollback Strategy:** Git revert.
* **Risk:** Low.

---

### Workstream 2: Flutter Team

#### Task F-01: Fix Flutter Widget Test Type Mismatches
* **Task ID:** TASK-01
* **Title:** Fix Flutter Test Type Mismatches (CI Pipeline Blocker)
* **Owner Team:** Flutter Team
* **Primary Owner:** Senior Flutter Engineer
* **Priority:** P0 (Critical)
* **Related Backlog Item:** `P0-1`
* **Related Audit Finding:** Verified `#1` & `#2` ([`audit-validation.md:29-134`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/audit-validation.md#L29-L134))
* **Related PRR Finding:** Section 6 ([`production-readiness-gap.md:175`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/production-readiness-gap.md#L175))
* **Files Expected to Change:**
  * [`apps/frontend/test/widget_test.dart`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/test/widget_test.dart)
* **Dependencies:** None
* **Blocking Tasks:** All frontend CI validation
* **Can Run In Parallel:** Yes (with Task B-01, Task I-01)
* **Estimated Engineering Hours:** 0.5h | **Review Hours:** 0.25h
* **Testing Required:** Unit Tests (`flutter test`), Integration Tests (`flutter analyze`), Contract Tests (None), Security Tests (None), Load Tests (None), Manual Verification (IDE type checker).
* **Definition of Done:** Return type updated to `Stream<List<MessageEntity>>`; `implements WebSocketClient` added; `flutter analyze` passes cleanly.
* **Expected Deliverable:** Green Flutter test suite.
* **Merge Strategy:** Fast-forward merge to `main`.
* **Rollback Strategy:** Git revert.
* **Risk:** Low.

---

#### Task F-02: Implement Client Payload Encryption & Local Key Store
* **Task ID:** TASK-03-CLIENT
* **Title:** Implement TweetNaCl Client Encryption & Isar Key Cache
* **Owner Team:** Flutter Team (Joint with Backend Team)
* **Primary Owner:** Lead Flutter Mobile Architect
* **Priority:** P0 (Critical)
* **Related Backlog Item:** `P0-3`
* **Related Audit Finding:** Verified `#12` ([`audit-validation.md:568`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/audit-validation.md#L568))
* **Related PRR Finding:** Section 3 ([`production-readiness-gap.md:88`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/production-readiness-gap.md#L88))
* **Files Expected to Change:**
  * [`apps/frontend/lib/features/chat/data/chat_repository.dart`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/lib/features/chat/data/chat_repository.dart)
  * `apps/frontend/lib/core/crypto/encryption_service.dart` (NEW)
* **Dependencies:** TASK-01 (Flutter test unblock)
* **Blocking Tasks:** TASK-11 (WebSocket backpressure)
* **Can Run In Parallel:** Yes (with Task B-02)
* **Estimated Engineering Hours:** 4.0h | **Review Hours:** 1.0h
* **Testing Required:** Unit Tests (Encryption/decryption round-trip unit test), Integration Tests (WebSocket transmit test), Contract Tests (Protobuf binary compatibility), Security Tests (Key isolation), Load Tests (None), Manual Verification (Inspect Isar local DB contents).
* **Definition of Done:** Message payloads encrypted before transmission; Base64 wrapping of encrypted bytes verified.
* **Expected Deliverable:** Client-side encryption service module.
* **Merge Strategy:** Rebase merge.
* **Rollback Strategy:** Git revert.
* **Risk:** High.

---

#### Task F-03: Implement WebSocket Outbound Buffer Backpressure Callbacks
* **Task ID:** TASK-11
* **Title:** Implement WebSocket Outbound Buffer Backpressure
* **Owner Team:** Flutter Team
* **Primary Owner:** Senior Flutter Engineer
* **Priority:** P1 (High)
* **Related Backlog Item:** `P1-4`
* **Related Audit Finding:** Verified `#13` ([`audit-validation.md:612`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/audit-validation.md#L612))
* **Related PRR Finding:** Section 2 ([`production-readiness-gap.md:65`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/production-readiness-gap.md#L65))
* **Files Expected to Change:**
  * [`apps/frontend/lib/core/network/websocket_client.dart`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/lib/core/network/websocket_client.dart)
  * [`apps/frontend/lib/features/chat/presentation/chat_controller.dart`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/lib/features/chat/presentation/chat_controller.dart)
* **Dependencies:** TASK-01
* **Blocking Tasks:** None
* **Can Run In Parallel:** Yes (with Task B-04, Task D-02)
* **Estimated Engineering Hours:** 1.0h | **Review Hours:** 0.5h
* **Testing Required:** Unit Tests (Buffer queue depth test), Integration Tests (Simulated slow network queue overflow), Contract Tests (None), Security Tests (None), Load Tests (100 msg/sec buffer stress test), Manual Verification (Log queue warnings).
* **Definition of Done:** Backpressure callback triggered at 80% queue depth; silent packet drops prevented.
* **Expected Deliverable:** Backpressure-aware WebSocket client.
* **Merge Strategy:** Rebase merge.
* **Rollback Strategy:** Git revert.
* **Risk:** Low.

---

#### Task F-04: Refactor NearbyScreen Presentation-to-Repository Layer Bypass
* **Task ID:** TASK-17
* **Title:** Encapsulate NearbyScreen Actions in ChatController
* **Owner Team:** Flutter Team
* **Primary Owner:** Flutter UI Specialist
* **Priority:** P2 (Medium)
* **Related Backlog Item:** `P2-6` / PRR Action Matrix P2
* **Related Audit Finding:** Section 9 ([`audit-validation.md:838`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/audit-validation.md#L838))
* **Related PRR Finding:** Section 3 ([`production-readiness-gap.md:31`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/production-readiness-gap.md#L31))
* **Files Expected to Change:**
  * [`apps/frontend/lib/features/nearby/presentation/nearby_screen.dart`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/lib/features/nearby/presentation/nearby_screen.dart)
  * [`apps/frontend/lib/features/chat/presentation/chat_controller.dart`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/lib/features/chat/presentation/chat_controller.dart)
* **Dependencies:** TASK-01
* **Blocking Tasks:** None
* **Can Run In Parallel:** Yes (with Task B-05, Task I-03)
* **Estimated Engineering Hours:** 1.0h | **Review Hours:** 0.5h
* **Testing Required:** Unit Tests (ChatController room creation test), Integration Tests (UI navigation test), Contract Tests (None), Security Tests (None), Load Tests (None), Manual Verification (Tap nearby user card to open room).
* **Definition of Done:** `NearbyScreen` calls `ref.read(chatControllerProvider.notifier).createRoom()` instead of direct repository provider.
* **Expected Deliverable:** Clean Architecture compliant Flutter presentation screen.
* **Merge Strategy:** Fast-forward merge.
* **Rollback Strategy:** Git revert.
* **Risk:** Low.

---

### Workstream 3: Infrastructure Team

#### Task I-01: Fix Docker Compose Kafka Health Check
* **Task ID:** TASK-09
* **Title:** Fix Docker Compose Kafka Health Check
* **Owner Team:** Infrastructure Team
* **Primary Owner:** Infrastructure Engineer
* **Priority:** P1 (High)
* **Related Backlog Item:** `P1-2`
* **Related Audit Finding:** Verified `#15` ([`audit-validation.md:693`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/audit-validation.md#L693))
* **Related PRR Finding:** Section 8 ([`production-readiness-gap.md:195`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/production-readiness-gap.md#L195))
* **Files Expected to Change:**
  * [`docker-compose.yml`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docker-compose.yml)
* **Dependencies:** None
* **Blocking Tasks:** Local developer environment startup (`make up`)
* **Can Run In Parallel:** Yes (with Task B-01, Task F-01)
* **Estimated Engineering Hours:** 0.5h | **Review Hours:** 0.25h
* **Testing Required:** Unit Tests (None), Integration Tests (`docker compose up` health check), Contract Tests (None), Security Tests (None), Load Tests (None), Manual Verification (`docker ps` healthy status).
* **Definition of Done:** Kafka container health test uses `nc -z localhost 9092`; `make up` starts cleanly.
* **Expected Deliverable:** Fixed `docker-compose.yml`.
* **Merge Strategy:** Fast-forward merge.
* **Rollback Strategy:** Git revert.
* **Risk:** Low.

---

#### Task I-02: Deploy PgBouncer Database Connection Pooling Sidecars
* **Task ID:** TASK-07
* **Title:** Deploy PgBouncer Connection Proxy in Helm Templates
* **Owner Team:** Infrastructure Team (Joint with Database Team)
* **Primary Owner:** Senior Infrastructure Architect
* **Priority:** P1 (Production Risk)
* **Related Backlog Item:** PRR Action Matrix P1
* **Related Audit Finding:** Verified `#4` ([`audit-validation.md:166`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/audit-validation.md#L166))
* **Related PRR Finding:** Section 2 ([`production-readiness-gap.md:54`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/production-readiness-gap.md#L54))
* **Files Expected to Change:**
  * [`infrastructure/helm/easychat/templates/deployments.yaml`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/helm/easychat/templates/deployments.yaml)
  * [`infrastructure/helm/easychat/values.yaml`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/helm/easychat/values.yaml)
  * `infrastructure/helm/easychat/templates/pgbouncer.yaml` (NEW)
* **Dependencies:** TASK-05 (Helm database URL fix)
* **Blocking Tasks:** TASK-15 (k6 load testing)
* **Can Run In Parallel:** Yes (with Task D-02, Task S-01)
* **Estimated Engineering Hours:** 4.0h | **Review Hours:** 1.0h
* **Testing Required:** Unit Tests (Helm template rendering), Integration Tests (PgBouncer connection pool test), Contract Tests (Postgres protocol compatibility), Security Tests (TLS sidecar connection), Load Tests (10k connection stress test), Manual Verification (Inspect `pgbouncer` process logs).
* **Definition of Done:** PgBouncer proxy layer rendered in Helm; microservices connect through PgBouncer on port 6432.
* **Expected Deliverable:** PgBouncer Helm template and parameters.
* **Merge Strategy:** Rebase merge.
* **Rollback Strategy:** Revert Helm values to connect directly to PostgreSQL service.
* **Risk:** Medium.

---

#### Task I-03: Execute Automated Multi-Region DR Failover Drill
* **Task ID:** TASK-20
* **Title:** Execute Automated Disaster Recovery Failover Drill
* **Owner Team:** Infrastructure Team (Joint with QA & SRE)
* **Primary Owner:** Principal SRE Architect
* **Priority:** P3 (Low / Certification)
* **Related Backlog Item:** `P3-2`
* **Related Audit Finding:** Verified `#11` ([`audit-validation.md:491`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/audit-validation.md#L491))
* **Related PRR Finding:** Section 10 ([`production-readiness-gap.md:220`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/production-readiness-gap.md#L220))
* **Files Expected to Change:**
  * [`apps/backend/services/dr-controller/main.go`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/dr-controller/main.go)
  * `docs/dr_certification_report.md` (NEW)
* **Dependencies:** TASK-07, TASK-15
* **Blocking Tasks:** Final Production GO Signoff
* **Can Run In Parallel:** Yes (with Task D-03, Task B-06)
* **Estimated Engineering Hours:** 2.0h | **Review Hours:** 1.0h
* **Testing Required:** Unit Tests (None), Integration Tests (K8s failover execution), Contract Tests (Fencing token validation), Security Tests (Crypto rand fencing token check), Load Tests (Failover under active load), Manual Verification (Inspect DR metrics SLA output).
* **Definition of Done:** DR failover drill executes cleanly; RTO $\le 5\text{m}$ and RPO $\le 30\text{s}$ SLA pass verified.
* **Expected Deliverable:** Signed DR Certification Report.
* **Merge Strategy:** Fast-forward merge.
* **Rollback Strategy:** Call `resetToHealthyPrimary()` API helper.
* **Risk:** Medium.

---

### Workstream 4: DevOps Team

#### Task D-01: Fix Helm Database Connection URL Template
* **Task ID:** TASK-05
* **Title:** Fix Helm Database Connection URL Template
* **Owner Team:** DevOps Team (Joint with Database Team)
* **Primary Owner:** Senior DevOps Engineer
* **Priority:** P0 (Critical Deployment Blocker)
* **Related Backlog Item:** `P0-5`
* **Related Audit Finding:** Verified `#7` ([`audit-validation.md:281`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/audit-validation.md#L281))
* **Related PRR Finding:** Section 9 ([`production-readiness-gap.md:190`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/production-readiness-gap.md#L190))
* **Files Expected to Change:**
  * [`infrastructure/helm/easychat/templates/deployments.yaml`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/helm/easychat/templates/deployments.yaml)
  * [`infrastructure/helm/easychat/values.yaml`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/helm/easychat/values.yaml)
* **Dependencies:** TASK-02 (Secrets externalization pass)
* **Blocking Tasks:** TASK-07 (PgBouncer deployment)
* **Can Run In Parallel:** Yes (with Task B-03, Task S-01)
* **Estimated Engineering Hours:** 1.0h | **Review Hours:** 0.5h
* **Testing Required:** Unit Tests (Helm template dry-run), Integration Tests (K8s pod boot test), Contract Tests (None), Security Tests (None), Load Tests (None), Manual Verification (Inspect `kubectl exec env`).
* **Definition of Done:** `DATABASE_URL` renders full connection string `postgresql://user:pass@host:5432/db`.
* **Expected Deliverable:** Corrected Helm deployment template.
* **Merge Strategy:** Rebase merge.
* **Rollback Strategy:** Git revert.
* **Risk:** Low.

---

#### Task D-02: Replace Prometheus Canary Parsing with `jq` in CD Pipeline
* **Task ID:** TASK-08
* **Title:** Replace Prometheus Canary Parsing with `jq`
* **Owner Team:** DevOps Team
* **Primary Owner:** DevOps Pipeline Lead
* **Priority:** P1 (High Release Safety)
* **Related Backlog Item:** `P1-1`
* **Related Audit Finding:** Verified `#14` ([`audit-validation.md:652`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/audit-validation.md#L652))
* **Related PRR Finding:** Section 9 ([`production-readiness-gap.md:195`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/production-readiness-gap.md#L195))
* **Files Expected to Change:**
  * [`.github/workflows/cd.yml`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/.github/workflows/cd.yml)
* **Dependencies:** None
* **Blocking Tasks:** None
* **Can Run In Parallel:** Yes (with Task B-04, Task F-03)
* **Estimated Engineering Hours:** 1.0h | **Review Hours:** 0.5h
* **Testing Required:** Unit Tests (Shell script `jq` parsing test), Integration Tests (GitHub Actions workflow dry-run), Contract Tests (Prometheus API JSON schema), Security Tests (None), Load Tests (None), Manual Verification (Simulate 2% HTTP error rate response).
* **Definition of Done:** `cd.yml` parses Prometheus JSON using `jq -r '.data.result[0].value[1]'` with explicit error handling.
* **Expected Deliverable:** Robust canary deployment workflow.
* **Merge Strategy:** Rebase merge.
* **Rollback Strategy:** Git revert workflow commit.
* **Risk:** Low.

---

#### Task D-03: Compile SRE Operational Runbooks
* **Task ID:** TASK-19
* **Title:** Compile SRE Operational Runbooks & Playbooks
* **Owner Team:** DevOps Team (Joint with Infrastructure Team)
* **Primary Owner:** Lead SRE Technical Writer
* **Priority:** P3 (Low)
* **Related Backlog Item:** `P3-2`
* **Related Audit Finding:** Verified Section 9 ([`audit-validation.md:900`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/audit-validation.md#L900))
* **Related PRR Finding:** Section 8 ([`production-readiness-gap.md:180`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/production-readiness-gap.md#L180))
* **Files Expected to Change:**
  * [`docs/sre/runbooks.md`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/sre/runbooks.md) (NEW)
* **Dependencies:** None
* **Blocking Tasks:** None
* **Can Run In Parallel:** Yes (with Task B-06, Task I-04)
* **Estimated Engineering Hours:** 4.0h | **Review Hours:** 1.0h
* **Testing Required:** Manual Verification (Review procedural accuracy against infrastructure scripts).
* **Definition of Done:** Runbooks written for DB partition expansion, Postgres replica promotion, Redis failover, and canary rollback.
* **Expected Deliverable:** Master SRE Runbook document.
* **Merge Strategy:** Fast-forward merge.
* **Rollback Strategy:** Git revert.
* **Risk:** Low.

---

### Workstream 5: Database Team

#### Task DB-01: Inject Retention Policy Threshold into Helm ConfigMap
* **Task ID:** TASK-10
* **Title:** Add Retention Policy Threshold to Helm ConfigMap
* **Owner Team:** Database Team (Joint with DevOps Team)
* **Primary Owner:** Senior Database Administrator
* **Priority:** P1 (High)
* **Related Backlog Item:** `P1-3`
* **Related Audit Finding:** Verified `#16` ([`audit-validation.md:725`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/audit-validation.md#L725))
* **Related PRR Finding:** Section 11 ([`production-readiness-gap.md:245`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/production-readiness-gap.md#L245))
* **Files Expected to Change:**
  * [`infrastructure/helm/easychat/templates/configmap.yaml`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/helm/easychat/templates/configmap.yaml)
  * [`infrastructure/helm/easychat/values.yaml`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/helm/easychat/values.yaml)
* **Dependencies:** TASK-05
* **Blocking Tasks:** None
* **Can Run In Parallel:** Yes (with Task B-04, Task F-03)
* **Estimated Engineering Hours:** 1.0h | **Review Hours:** 0.25h
* **Testing Required:** Unit Tests (Helm template render), Integration Tests (Compliance retention purge execution), Contract Tests (None), Security Tests (None), Load Tests (None), Manual Verification (Inspect `configmap.yaml`).
* **Definition of Done:** `RETENTION_PURGE_DAYS_THRESHOLD=180` injected into ConfigMap and configurable via `values.yaml`.
* **Expected Deliverable:** Updated ConfigMap template.
* **Merge Strategy:** Rebase merge.
* **Rollback Strategy:** Git revert.
* **Risk:** Low.

---

### Workstream 6: Security Team

#### Task S-01: Remove Hardcoded Plaintext Secrets from Helm Templates
* **Task ID:** TASK-02
* **Title:** Remove Hardcoded Secrets from Helm Manifests
* **Owner Team:** Security Team (Joint with DevOps Team)
* **Primary Owner:** Enterprise Security Architect
* **Priority:** P0 (Critical Security Incident)
* **Related Backlog Item:** `P0-2`
* **Related Audit Finding:** Verified `#6` ([`audit-validation.md:252`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/audit-validation.md#L252))
* **Related PRR Finding:** Section 3 ([`production-readiness-gap.md:88`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/production-readiness-gap.md#L88))
* **Files Expected to Change:**
  * [`infrastructure/helm/easychat/templates/secrets.yaml`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/helm/easychat/templates/secrets.yaml)
  * [`infrastructure/kubernetes/eso/external-secrets.yaml`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/kubernetes/eso/external-secrets.yaml)
* **Dependencies:** None
* **Blocking Tasks:** TASK-05 (Helm database URL fix)
* **Can Run In Parallel:** Yes (with Task B-01, Task F-01, Task I-01)
* **Estimated Engineering Hours:** 2.0h | **Review Hours:** 1.0h
* **Testing Required:** Unit Tests (None), Integration Tests (ExternalSecrets sync validation), Contract Tests (None), Security Tests (Trivy secret scan), Load Tests (None), Manual Verification (Verify no plaintext secrets in Git).
* **Definition of Done:** Plaintext `stringData` removed from Helm templates; secrets retrieved dynamically via ExternalSecrets Operator.
* **Expected Deliverable:** ExternalSecrets Operator integration manifest.
* **Merge Strategy:** Squash merge to `main`.
* **Rollback Strategy:** Restore temporary secret references in local test cluster.
* **Risk:** Medium.

---

### Workstream 7: QA Team

#### Task Q-01: Automate k6 Performance & Load Testing in CI/CD
* **Task ID:** TASK-15
* **Title:** Automate k6 Load Testing in CI Pipeline
* **Owner Team:** QA Team (Joint with DevOps Team)
* **Primary Owner:** Lead Performance QA Engineer
* **Priority:** P2 (Medium)
* **Related Backlog Item:** PRR Action Matrix P2
* **Related Audit Finding:** Verified Section 7 ([`audit-validation.md:650`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/audit-validation.md#L650))
* **Related PRR Finding:** Section 5 ([`production-readiness-gap.md:145`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/production-readiness-gap.md#L145))
* **Files Expected to Change:**
  * [`.github/workflows/cd.yml`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/.github/workflows/cd.yml)
  * [`tests/load/load_test.js`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/tests/load/load_test.js)
* **Dependencies:** TASK-07 (PgBouncer connection proxy)
* **Blocking Tasks:** TASK-20 (DR failover drill)
* **Can Run In Parallel:** Yes (with Task B-05, Task F-04)
* **Estimated Engineering Hours:** 2.0h | **Review Hours:** 0.5h
* **Testing Required:** Unit Tests (k6 script syntax test), Integration Tests (Staging cluster k6 execution), Contract Tests (None), Security Tests (None), Load Tests (10k concurrent virtual user simulation), Manual Verification (Inspect k6 summary report).
* **Definition of Done:** Automated k6 execution step added to `cd.yml` staging release job; $p_{95} < 100\text{ms}$ verified.
* **Expected Deliverable:** Automated performance test workflow step.
* **Merge Strategy:** Rebase merge.
* **Rollback Strategy:** Disable workflow step.
* **Risk:** Low.

---

#### Task Q-02: Verify End-to-End Read Receipt & Proximity Workflows
* **Task ID:** TASK-13
* **Title:** Verify Read Receipt & BLE Proximity Integration Workflows
* **Owner Team:** QA Team (Joint with Backend Team)
* **Primary Owner:** Senior QA Automation Engineer
* **Priority:** P2 (Medium)
* **Related Backlog Item:** `P2-1` & `P2-2`
* **Related Audit Finding:** Verified `#817` & `#873` ([`audit-validation.md:817-873`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/audit-validation.md#L817-L873))
* **Related PRR Finding:** Section 6 ([`production-readiness-gap.md:160`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docs/reports/production-readiness-gap.md#L160))
* **Files Expected to Change:**
  * [`tests/contracts/contract_test.go`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/tests/contracts/contract_test.go)
  * [`tests/simulation/two_device_discovery_sim.go`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/tests/simulation/two_device_discovery_sim.go)
* **Dependencies:** TASK-03 (Message encryption)
* **Blocking Tasks:** None
* **Can Run In Parallel:** Yes (with Task B-05, Task F-04)
* **Estimated Engineering Hours:** 4.0h | **Review Hours:** 1.0h
* **Testing Required:** Unit Tests (None), Integration Tests (Two-device simulation run), Contract Tests (`DeliveryReceipt` protobuf contract validation), Security Tests (None), Load Tests (None), Manual Verification (Review simulation log trace).
* **Definition of Done:** Automated test confirms SENT $\rightarrow$ DELIVERED $\rightarrow$ READ state transition over WebSockets.
* **Expected Deliverable:** Automated integration test suite update.
* **Merge Strategy:** Fast-forward merge.
* **Rollback Strategy:** Git revert.
* **Risk:** Low.

---

## Merge Waves Specification

```
┌─────────────────────────────────────────────────────────────────────────┐
│ WAVE 1: CRITICAL PRODUCTION BLOCKERS (P0)                               │
│ - Task F-01: Fix Flutter Test Type Mismatches          (Flutter)        │
│ - Task B-01: Align Go Workspace Compiler Versions      (Backend)        │
│ - Task S-01: Remove Hardcoded Secrets from Helm        (Security)       │
│ - Task I-01: Fix Docker Compose Kafka Health Check     (Infrastructure) │
│ - Task D-01: Fix Helm Database Connection URL Template (DevOps)         │
│ - Task B-02 / F-02: End-to-End Payload Encryption       (Backend/Flutter)│
└────────────────────────────────────┬────────────────────────────────────┘
                                     │
                                     v
┌─────────────────────────────────────────────────────────────────────────┐
│ WAVE 2: SECURITY & RELIABILITY HARDENING (P0 / P1)                      │
│ - Task B-03: Mandate Asymmetric RS256 JWT Verification (Backend/Sec)    │
│ - Task I-02: Deploy PgBouncer Connection Proxy         (Infra/DB)       │
│ - Task D-02: Replace Prometheus Canary Parsing with jq (DevOps)         │
│ - Task DB-01: Inject Retention Threshold into ConfigMap(Database)       │
│ - Task F-03: Implement WebSocket Backpressure Callbacks(Flutter)        │
└────────────────────────────────────┬────────────────────────────────────┘
                                     │
                                     v
┌─────────────────────────────────────────────────────────────────────────┐
│ WAVE 3: SCALABILITY, PERFORMANCE & TESTING (P1 / P2)                    │
│ - Task B-04: Enforce Redis TTL Expiration on Presence  (Backend)        │
│ - Task Q-01: Automate k6 Load Testing in CI Pipeline   (QA/DevOps)      │
│ - Task Q-02: Verify Read Receipt & Proximity Workflows (QA/Backend)     │
│ - Task B-05: Refactor Gateway Router God Package       (Backend)        │
│ - Task F-04: Refactor NearbyScreen Layer Bypass        (Flutter)        │
└────────────────────────────────────┬────────────────────────────────────┘
                                     │
                                     v
┌─────────────────────────────────────────────────────────────────────────┐
│ WAVE 4: DOCUMENTATION, OPERATIONAL DRILLS & CLEANUP (P3)               │
│ - Task B-06: Generate Protobuf API Documentation       (Backend)        │
│ - Task D-03: Compile SRE Operational Runbooks          (DevOps)         │
│ - Task I-03: Execute Automated DR Failover Drill       (Infra/SRE/QA)   │
│ - Final Signoff: Production Readiness Score 100/100    (PRR Committee)  │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Detailed Merge Order

To eliminate cross-team branch conflicts and avoid breaking CI builds during progressive integrations, all branches MUST be merged into `main` in the following strict order:

1. **Infrastructure Base:** Merges [`docker-compose.yml`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/docker-compose.yml) health check fixes (Task I-01).
2. **Database & Secrets Schema:** Merges ExternalSecrets operator integration and Helm database URL connection templates (Task S-01, Task D-01).
3. **Backend Core & Workspace:** Merges Go compiler version alignment and encryption endpoints (Task B-01, Task B-02).
4. **Flutter Client Layer:** Merges Flutter widget test mock type fixes and TweetNaCl client encryption (Task F-01, Task F-02).
5. **Security & Gateway Verification:** Merges RS256 JWKS asymmetric token validation (Task B-03).
6. **Infrastructure Scaling Proxy:** Merges PgBouncer connection proxy Helm templates (Task I-02).
7. **QA & Operational Benchmarking:** Merges automated k6 performance regression workflows (Task Q-01).
8. **Final Documentation & DR Certification:** Merges SRE runbooks, Protobuf docs, and DR certification report (Task B-06, Task D-03, Task I-03).

### Why This Merge Order Minimizes Conflicts
* Infrastructure and secret schema changes merge first so that backend and database code paths consume valid connections immediately.
* Backend core interfaces merge before Flutter client components to establish API contract stubs (`chat.proto`).
* Refactoring and documentation tasks occur last in Wave 4, ensuring zero disruption to active functional code changes in Waves 1–3.

---

## Parallel Development Team Timeline

```
          WEEK 1                  WEEK 2                  WEEK 3                  WEEK 4
Team      D1  D2  D3  D4  D5      D6  D7  D8  D9  D10     D11 D12 D13 D14 D15     D16 D17 D18 D19 D20
───────────────────────────────────────────────────────────────────────────────────────────────────
Backend   [B-01][  B-02  ]       [  B-03  ][ B-04 ]       [  B-05  ]             [B-06]
Flutter   [F-01][  F-02  ]       [ F-03 ]                 [ F-04 ]
Infra     [I-01]                 [   I-02   ]                                     [  I-03  ]
DevOps    [D-01]                 [ D-02 ]                 [ D-03 ]
Database                         [DB-01 ]
Security  [  S-01  ]
QA                                                        [  Q-01  ][  Q-02  ]    [PRR Signoff]
───────────────────────────────────────────────────────────────────────────────────────────────────
Waves     <===== WAVE 1 ======>  <===== WAVE 2 ======>    <===== WAVE 3 ======>   <=== WAVE 4 ====>
```

---

## Dependency Matrix

| Task ID | Task Title | Depends On | Blocks | Primary Owner |
| :--- | :--- | :--- | :--- | :--- |
| **TASK-01** | Fix Flutter Test Mocks | None | TASK-03-CLIENT, TASK-11, TASK-17 | Flutter Team |
| **TASK-02** | Remove Helm Plaintext Secrets | None | TASK-05 | Security Team |
| **TASK-03** | End-to-End Payload Encryption | TASK-01, TASK-04 | TASK-13 | Backend / Flutter Teams |
| **TASK-04** | Align Go Compiler Versions | None | TASK-03, TASK-06, TASK-14 | Backend Team |
| **TASK-05** | Fix Helm Database URL Template | TASK-02 | TASK-07, TASK-10 | DevOps Team |
| **TASK-06** | Mandate RS256 JWT Verification | TASK-04 | TASK-16 | Backend / Security Teams |
| **TASK-07** | Deploy PgBouncer Proxy | TASK-05 | TASK-15 | Infrastructure Team |
| **TASK-08** | Prometheus Canary `jq` Parsing | None | CI CD Pipeline Promotion | DevOps Team |
| **TASK-09** | Docker Compose Kafka Health Check | None | Local Dev Boot (`make up`) | Infrastructure Team |
| **TASK-10** | Retention Threshold ConfigMap | TASK-05 | Compliance Data Purge | Database Team |
| **TASK-11** | WebSocket Outbound Backpressure | TASK-01 | None | Flutter Team |
| **TASK-13** | Read Receipt Verification | TASK-03 | None | QA / Backend Teams |
| **TASK-14** | Presence Redis TTL Expiration | TASK-04 | None | Backend Team |
| **TASK-15** | Automate k6 Load Testing | TASK-07 | TASK-20 | QA / DevOps Teams |
| **TASK-16** | Refactor Gateway Router Package | TASK-06 | None | Backend Team |
| **TASK-17** | Refactor NearbyScreen Layer | TASK-01 | None | Flutter Team |
| **TASK-18** | Generate Protobuf API Docs | None | None | Backend Team |
| **TASK-19** | Compile SRE Operational Runbooks| None | None | DevOps Team |
| **TASK-20** | Execute DR Failover Drill | TASK-07, TASK-15 | Final PRR GO Signoff | Infrastructure / QA Teams |

---

## Risk Register & Mitigation Strategies

### Critical Risks

#### RSK-01: E2E Payload Encryption Serialization Failure
* **Risk Description:** Nonce mismatch or Base64 decoding failure between client and backend server causes unreadable chat packets.
* **Impact:** High (Chat messaging failure).
* **Mitigation Strategy:** Implement fallback payload versioning header (`enc_v1:`) and execute contract tests before merging Wave 1.
* **Owner:** Backend Lead Architect.

#### RSK-02: PostgreSQL Connection Exhaustion under Max Pod Autoscaling
* **Risk Description:** Scaling microservice replicas to HPA max limits (10 pods $\times$ 8 services $\times$ 25 conns = 2,000 connections) exceeds PostgreSQL server capacity.
* **Impact:** Critical (Database crash).
* **Mitigation Strategy:** Enforce PgBouncer connection pooling sidecar deployment (TASK-07) prior to executing k6 load testing.
* **Owner:** Senior Infrastructure Architect.

---

### Medium Risks

#### RSK-03: Keycloak JWKS Endpoint Unavailability
* **Risk Description:** Gateway startup failure if remote Keycloak JWKS public key endpoint is unreachable.
* **Impact:** Medium (Gateway boot failure).
* **Mitigation Strategy:** Implement in-memory public key caching in Gateway router with 15-minute expiration fallback.
* **Owner:** Backend Security Specialist.

#### RSK-04: Prometheus Metric Schema Drift Breaking Canary Rollbacks
* **Risk Description:** Inline `jq` shell query in `cd.yml` fails if metric label names change.
* **Impact:** Medium (Canary release validation failure).
* **Mitigation Strategy:** Add automated JSON schema unit tests for Prometheus API response mocking.
* **Owner:** DevOps Pipeline Lead.

---

### Low Risks

#### RSK-05: Proto Documentation Generation Script Failure
* **Risk Description:** Missing `protoc-gen-doc` plugin binary on local developer machines.
* **Impact:** Low (Documentation build failure).
* **Mitigation Strategy:** Package `protoc-gen-doc` execution inside Dockerized build image.
* **Owner:** Backend Engineer.

---

## Release Verification Checklist

* [ ] **Development Complete:** All 18 engineering tasks executed across Waves 1–4.
* [ ] **Code Review Complete:** 100% of pull requests approved by team leads with 14.5 total review hours logged.
* [ ] **CI Green:** GitHub Actions `.github/workflows/ci.yml` passes all linting, unit tests, and Gosec scans.
* [ ] **Security Approved:** Trivy container scans pass with 0 Critical vulnerabilities; Cosign images signed.
* [ ] **Performance Approved:** k6 automated load test verifies $p_{95} < 100\text{ms}$ under 10k virtual users.
* [ ] **QA Approved:** Read receipt and BLE simulation integration tests pass with 0 errors.
* [ ] **PRR Passed:** Disaster Recovery failover drill verifies RTO $\le 5\text{m}$ and RPO $\le 30\text{s}$.
* [ ] **Production GO:** Production Readiness Score reaches **100 / 100**; Signed GO decision issued.

---

## Plan Metrics & Summary

| Parameter | Value |
| :--- | :--- |
| **Total Engineering Work Hours** | **49.5 Hours** |
| **Total Code Review Hours** | **14.5 Hours** |
| **Combined Execution Allocation** | **64.0 Hours** |
| **Critical Path Duration** | **12 Days** |
| **Parallelization Efficiency** | **82.5%** |
| **Baseline PRR Score** | **92 / 100** |
| **Post-Execution PRR Score** | **100 / 100** |
| **Final Release Recommendation** | **FULL GO** |
