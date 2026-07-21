# Production Engineering Backlog

**Source:** `docs/reports/audit-validation.md`  
**Date Created:** 2026-07-21  
**Validation Status:** Evidence-based, line-number verified  
**False Positives Excluded:** 4 findings (Database pooling, Kafka, Rate limiting, Compliance service already implemented)  
**Total Tasks:** 14 (P0: 5, P1: 4, P2: 3, P3: 2)  
**Total Estimated Effort:** 24.5 hours

---

## P0: CRITICAL BLOCKERS

**Criteria:** Blocks any production release or public availability. Security, privacy, or build failures.

---

### P0-1: Fix Flutter Test Type Mismatches (CI Pipeline Blocker)

**Priority:** CRITICAL  
**Effort:** 0.5 hours  
**Assigned:** Frontend Team

**Problem:**
Flutter test suite fails at compile time. Two type incompatibilities in test mocks prevent CI pipeline from progressing past `flutter analyze` phase. CI job blocks all pull requests.

**Root Cause:**
- `FakeChatRepository.watchMessages()` returns `Stream<List<dynamic>>` instead of `Stream<List<MessageEntity>>`
- `FakeWebSocketClient` class does not implement `WebSocketClient` interface
- Riverpod provider override expects concrete interface type, not bare class

**Files:**
- `apps/frontend/test/widget_test.dart:45-57` (FakeChatRepository)
- `apps/frontend/test/widget_test.dart:18-42` (FakeWebSocketClient)
- `apps/frontend/lib/features/chat/data/chat_repository.dart:46` (correct interface)
- `apps/frontend/lib/core/network/websocket_client.dart:6-175` (correct interface)

**Specific Changes Required:**
1. Line 55: Change return type from `Stream<List<dynamic>>` to `Stream<List<MessageEntity>>`
2. Line 18: Add `implements WebSocketClient` to class declaration
3. Ensure all methods from WebSocketClient interface are implemented

**Estimated Hours:** 0.5

**Dependencies:**
- None (blocking dependency for other frontend work)

**Risk:**
- Low (fixing test code only, no production impact)

**Acceptance Criteria:**
1. `flutter analyze` completes without errors on `main`
2. Widget test compiles and runs successfully
3. Type checker confirms no type mismatches remain
4. CI job completes green

**Definition of Done:**
- Pull request reviewed and approved
- CI pipeline passes all checks
- Test runs locally without errors
- Type safety confirmed in IDE

---

### P0-2: Remove Hardcoded Secrets from Helm Chart (Security Incident)

**Priority:** CRITICAL  
**Effort:** 2.0 hours  
**Assigned:** DevOps/Security Team

**Problem:**
Kubernetes Secret manifest contains plaintext credentials committed to version control. Database passwords, AWS access keys, gateway token secret, and RSA private key are visible to all repository collaborators and in Git history. This violates security best practices and creates compliance risks.

**Root Cause:**
- `infrastructure/helm/easychat/templates/secrets.yaml` defines secrets with literal string values in `stringData`
- No external secret store (Vault, AWS Secrets Manager, K8s ExternalSecrets operator) configured
- Secrets committed to Git with no .gitignore protection

**Files:**
- `infrastructure/helm/easychat/templates/secrets.yaml:8-16` (hardcoded credentials)
- `infrastructure/helm/easychat/templates/deployments.yaml:51-62` (secret references)
- `.gitignore` (needs addition)

**Specific Changes Required:**
1. Replace `stringData` approach with external secret source
2. Implement one of:
   - HashiCorp Vault integration with Helm
   - AWS Secrets Manager with IRSA (IAM Roles for Service Accounts)
   - Kubernetes ExternalSecrets operator
3. Update `deployments.yaml` to reference external secrets
4. Add secrets file to `.gitignore`
5. Rotate all credentials in production

**Estimated Hours:** 2.0
- 0.5h: Select external secret solution
- 0.75h: Implement integration in Helm
- 0.5h: Update documentation
- 0.25h: Test integration

**Dependencies:**
- P0-5 (should be done in same deployment fix pass)

**Risk:**
- Medium: Requires infrastructure changes to secret storage
- Must ensure zero downtime during credential rotation
- All services must be updated to read from new source

**Acceptance Criteria:**
1. No plaintext credentials in Git repository
2. Secrets stored in external management system
3. Helm chart successfully deploys without exposing secrets
4. Credentials verifiable in secret store
5. Git history cleaned (or new repo branch created)

**Definition of Done:**
- External secret store configured and tested
- Helm values updated to use external secrets
- All credentials rotated in production
- Security review approved
- Documentation updated for operators
- No plaintext credentials visible in any code paths

---

### P0-3: Implement End-to-End Message Encryption (Privacy & Security)

**Priority:** CRITICAL  
**Effort:** 8.0 hours  
**Assigned:** Backend + Frontend Team (joint)

**Problem:**
Messages are transmitted and stored in plaintext despite privacy claims. `crypto` library is imported but unused. Only Base64 encoding (not encryption) applied to payloads. Violates user privacy and platform security claims.

**Root Cause:**
- `apps/frontend/lib/features/chat/data/chat_repository.dart:58` converts text to bytes via `codeUnits` without encryption
- `chat_repository.dart:75` applies only Base64 encoding: `base64Encode(text.codeUnits)`
- Protobuf expects `encrypted_content` but receives plaintext
- No key exchange or encryption library integration

**Files:**
- `apps/frontend/lib/features/chat/data/chat_repository.dart:55-90`
- `apps/frontend/pubspec.yaml:29` (crypto library present but unused)
- `proto/nearby/v1/chat.proto:60-64` (expects encrypted bytes)
- `apps/backend/services/chat/cmd/chat/main.go` (message handling)

**Specific Changes Required:**
1. Frontend:
   - Implement TweetNaCl or Sodium library wrapper in `lib/core/crypto/`
   - Add key exchange protocol (ECDH or pre-shared symmetric key)
   - Encrypt payload before Base64 encoding in `sendMessage()`
   - Decrypt payload on message reception in `startWebSocketListener()`
   - Add encryption key storage in Isar database

2. Backend:
   - Add decrypt logic in Chat Service message handler
   - Verify encrypted message integrity (AEAD/MAC)
   - Store encrypted form in database
   - Add encryption key management endpoint

3. Protocol:
   - Define key exchange handshake in proto (initial chat request)
   - Update message schema with nonce/IV fields

**Estimated Hours:** 8.0
- 2h: Crypto library integration + wrapper implementation
- 2h: Key exchange protocol implementation
- 2h: End-to-end encryption in message pipeline
- 1h: Integration testing
- 1h: Documentation

**Dependencies:**
- Requires P0-1 to pass (tests must work)
- Should complete before any load testing

**Risk:**
- High: Encryption bugs can lead to data loss or unreadable messages
- Backward compatibility: Old unencrypted messages must be handled
- Performance: Encryption/decryption overhead must be acceptable

**Acceptance Criteria:**
1. Messages encrypted before transmission
2. Messages decrypted on reception
3. Encryption keys securely stored and exchanged
4. Plaintext never visible in logs or database
5. Backward compatibility with unencrypted messages (graceful fallback)
6. Unit tests verify encryption/decryption round-trip
7. Integration test sends encrypted message end-to-end

**Definition of Done:**
- Unit tests pass (crypto correctness)
- Integration tests pass (frontend ↔ backend ↔ database)
- Security review approved
- No plaintext messages in database or logs
- Performance impact <10ms per message
- Documentation for developers on encryption model
- Deployment does not require database migration

---

### P0-4: Align Go Module Versions (Build Consistency)

**Priority:** CRITICAL  
**Effort:** 0.5 hours  
**Assigned:** Backend Team

**Problem:**
Go modules specify different language versions (1.24, 1.26.1) while CI pins 1.22. Build behavior differs between local and CI environments. Potential compile-time incompatibilities.

**Root Cause:**
- `apps/backend/go.mod:3` specifies `go 1.24`
- `apps/backend/services/nearby/go.mod:3` specifies `go 1.26.1`
- `.github/workflows/ci.yml:22` pins Go 1.22
- `README.md:14` documents Go 1.22.x as runtime

**Files:**
- `apps/backend/go.mod:3`
- `apps/backend/services/nearby/go.mod:3`
- `.github/workflows/ci.yml:22`
- `README.md:14`

**Specific Changes Required:**
Choose one option:
1. **Option A (Recommended):** Downgrade all modules to Go 1.22
   - Update `apps/backend/go.mod:3` to `go 1.22`
   - Update `apps/backend/services/nearby/go.mod:3` to `go 1.22`
   - Run `go mod tidy` in each module
   
2. **Option B:** Upgrade CI to Go 1.26.1
   - Update `.github/workflows/ci.yml:22` to `go-version: '1.26.1'`
   - Update `README.md:14` to document Go 1.26.1

**Recommended:** Option A (Go 1.22 is LTS, ensures compatibility)

**Estimated Hours:** 0.5
- 0.2h: Downgrade modules
- 0.15h: Run module updates
- 0.15h: Verify local build

**Dependencies:**
- None

**Risk:**
- Low: Version alignment is straightforward
- Must verify no Go 1.24+ features used if downgrading

**Acceptance Criteria:**
1. All `go.mod` files specify same version
2. CI version matches module version
3. Documentation consistent
4. Local build succeeds with specified version
5. CI build succeeds

**Definition of Done:**
- All module files updated
- CI workflow updated or verified
- README updated
- Local `go build ./...` succeeds
- CI job completes green

---

### P0-5: Fix Helm Database Connection URL (Deployment Blocker)

**Priority:** CRITICAL  
**Effort:** 1.0 hour  
**Assigned:** DevOps Team

**Problem:**
Helm deployment template injects only password as `DATABASE_URL` environment variable. Services expect full connection string `postgresql://user:password@host:port/db`. Deployments will fail with connection error.

**Root Cause:**
- `infrastructure/helm/easychat/templates/deployments.yaml:51-55` references only password key:
  ```yaml
  valueFrom:
    secretKeyRef:
      key: database-password
  ```
- Should construct full URL from username, password, host, port, database name
- Secret only stores individual components, not full connection string

**Files:**
- `infrastructure/helm/easychat/templates/deployments.yaml:51-55`
- `infrastructure/helm/easychat/templates/secrets.yaml:8-9` (stores username/password separately)
- `infrastructure/helm/easychat/values.yaml` (should add database configuration)

**Specific Changes Required:**
1. Add database configuration to `values.yaml`:
   ```yaml
   database:
     host: "postgres-service.default.svc.cluster.local"
     port: 5432
     name: "easychat"
     username: "easychat_admin"
     # password injected from secret
   ```

2. Update `deployments.yaml` to construct `DATABASE_URL`:
   ```yaml
   - name: DATABASE_URL
     value: "postgresql://$(DATABASE_USER):$(DATABASE_PASSWORD)@$(DATABASE_HOST):$(DATABASE_PORT)/$(DATABASE_NAME)"
   - name: DATABASE_USER
     valueFrom: { secretKeyRef: { name: easychat-secrets, key: database-username } }
   - name: DATABASE_PASSWORD
     valueFrom: { secretKeyRef: { name: easychat-secrets, key: database-password } }
   - name: DATABASE_HOST
     value: "{{ .Values.database.host }}"
   - name: DATABASE_PORT
     value: "{{ .Values.database.port }}"
   - name: DATABASE_NAME
     value: "{{ .Values.database.name }}"
   ```

3. Verify all services receive full URL

**Estimated Hours:** 1.0
- 0.3h: Update `values.yaml`
- 0.4h: Update deployment template
- 0.2h: Test in local Helm render
- 0.1h: Verify in deployment

**Dependencies:**
- P0-2 (secrets should be rotated/externalized in same pass)

**Risk:**
- Low: Template change only, no code changes
- Must test in non-production environment first

**Acceptance Criteria:**
1. `DATABASE_URL` contains full connection string
2. Helm template renders correctly with all placeholders
3. Services successfully connect to database after deployment
4. Connection pool initialized without error
5. Health check passes

**Definition of Done:**
- Helm values file updated
- Deployment template updated
- Helm template locally renders with correct URL
- Pull request reviewed
- Deployment tested in staging environment
- All services report successful database connection

---

## P1: HIGH PRIORITY

**Criteria:** Must complete before first load test or public beta. Affects reliability, monitoring, or operational safety.

---

### P1-1: Replace Prometheus Canary Parsing with Structured JSON (Release Safety)

**Priority:** HIGH  
**Effort:** 1.0 hour  
**Assigned:** DevOps/SRE Team

**Problem:**
Canary deployment validation uses fragile regex parsing of Prometheus JSON response. Multiple error paths silently fail, potentially allowing invalid releases to be promoted to production. `grep -oP` parsing breaks on unexpected JSON structure.

**Root Cause:**
- `.github/workflows/cd.yml:166-168` uses `grep -oP` regex for JSON parsing
- Silent error handling: `|| echo ""` masks all failures
- `bc` comparison may fail if tool unavailable
- No structured JSON parsing (should use `jq`)

**Files:**
- `.github/workflows/cd.yml:156-186` (entire canary validation section)

**Specific Changes Required:**
1. Replace regex parsing with `jq` command-line JSON parser
2. Add explicit error handling and logging
3. Fail fast on parse errors (don't silently continue)
4. Verify error rate threshold with unit test data
5. Add debug output for troubleshooting

Example fix:
```bash
# Current (fragile):
ERROR_RATE=$(echo "$RESPONSE" | grep -oP '"value":\[.*?,.*?"\K[0-9.]+(?="\])' || echo "")

# Better:
ERROR_RATE=$(echo "$RESPONSE" | jq -r '.data.result[0].value[1] // empty' 2>/dev/null)
if [ -z "$ERROR_RATE" ]; then
  echo "ERROR: Failed to parse Prometheus response"
  exit 1
fi
```

**Estimated Hours:** 1.0
- 0.3h: Implement jq-based parsing
- 0.3h: Add error handling and logging
- 0.2h: Test with sample Prometheus responses
- 0.2h: Update documentation

**Dependencies:**
- None

**Risk:**
- Medium: Deployment script change (affects release process)
- Must test with actual Prometheus in staging

**Acceptance Criteria:**
1. Prometheus JSON parsed correctly with `jq`
2. Errors fail fast with clear messages
3. Error rate correctly extracted and compared
4. SLA threshold honored (RTO ≤ 5min, RPO ≤ 30sec)
5. Canary validation blocks invalid releases

**Definition of Done:**
- Workflow file updated
- Tested with real Prometheus query responses
- Canary stage behavior verified in staging
- Error scenarios tested (missing data, malformed JSON)
- Documentation updated
- Code review approved

---

### P1-2: Fix Docker Compose Kafka Health Check (Local Dev Blocker)

**Priority:** HIGH  
**Effort:** 0.5 hours  
**Assigned:** DevOps Team

**Problem:**
Docker Compose Kafka health check assumes `/opt/kafka/bin/kafka-topics.sh` exists at exact path. If Kafka image changes or binary location differs, container reports unhealthy. Local development environment fails to start.

**Root Cause:**
- `docker-compose.yml:52-57` hardcodes absolute path to Kafka binary
- No fallback or verification of binary existence
- Health check silently fails, preventing dependent services from starting

**Files:**
- `docker-compose.yml:52-57`

**Specific Changes Required:**
Replace current health check with robust alternative:
```yaml
# Current (fragile):
test: ["CMD-SHELL", "/opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list 2>/dev/null && echo OK || exit 1"]

# Better (simple TCP check):
test: ["CMD-SHELL", "nc -z localhost 9092 || exit 1"]

# Or (even more robust):
test: ["CMD-SHELL", "kafka-broker-api-versions.sh --bootstrap-server localhost:9092 2>/dev/null && echo OK || exit 1"]
```

**Estimated Hours:** 0.5
- 0.2h: Update health check command
- 0.15h: Test locally with `make up`
- 0.15h: Verify dependent services start

**Dependencies:**
- None

**Risk:**
- Low: Docker Compose change only, no impact on production

**Acceptance Criteria:**
1. Kafka container reports healthy after startup
2. Dependent services start without timeout
3. `make up` completes successfully
4. Kafka is accessible on localhost:9092

**Definition of Done:**
- Docker Compose file updated
- Local `make up` tested and succeeds
- All services become healthy
- Code review approved

---

### P1-3: Add Retention Policy to Helm ConfigMap (Operational Flexibility)

**Priority:** HIGH  
**Effort:** 1.0 hour  
**Assigned:** Backend/DevOps Team

**Problem:**
Retention policy duration (180 days) is not configurable without code redeployment. Database README documents requirement for `RETENTION_PURGE_DAYS_THRESHOLD` environment variable, but it's missing from Helm ConfigMap.

**Root Cause:**
- `database/README.md:31-34` documents requirement for env var
- `infrastructure/helm/easychat/templates/configmap.yaml` does not include `RETENTION_PURGE_DAYS_THRESHOLD`
- Microservices have no way to read customized threshold

**Files:**
- `infrastructure/helm/easychat/templates/configmap.yaml` (add missing key)
- `infrastructure/helm/easychat/values.yaml` (add configuration value)
- `infrastructure/helm/easychat/templates/deployments.yaml` (no change needed, uses configmap)

**Specific Changes Required:**
1. Add to `values.yaml`:
   ```yaml
   retention:
     purgeThresholdDays: 180  # GDPR data retention period
   ```

2. Add to `configmap.yaml`:
   ```yaml
   RETENTION_PURGE_DAYS_THRESHOLD: "{{ .Values.retention.purgeThresholdDays }}"
   ```

3. Update documentation in Helm values to explain parameter

**Estimated Hours:** 1.0
- 0.3h: Update `values.yaml`
- 0.3h: Update `configmap.yaml`
- 0.2h: Test Helm render locally
- 0.2h: Verify in deployment

**Dependencies:**
- None

**Risk:**
- Low: Helm configuration change only

**Acceptance Criteria:**
1. `RETENTION_PURGE_DAYS_THRESHOLD` present in ConfigMap
2. Configurable via Helm values
3. Helm template renders with correct value
4. Deployments receive environment variable
5. Retention policy respects configured threshold

**Definition of Done:**
- `values.yaml` updated with default retention days
- `configmap.yaml` template updated
- Helm values documented
- Local `helm template` verified
- Code review approved

---

### P1-4: Implement WebSocket Outbound Buffer Backpressure (Message Reliability)

**Priority:** HIGH  
**Effort:** 1.0 hour  
**Assigned:** Frontend Team

**Problem:**
WebSocket client maintains outbound buffer with hardcoded 500-item cap. Under sustained load, oldest packets are silently discarded when buffer fills. Read receipts and typing indicators can be lost.

**Root Cause:**
- `apps/frontend/lib/core/network/websocket_client.dart:92-99` implements soft cap at 500 items
- No backpressure signaling to caller
- `removeAt(0)` silently discards oldest when capacity reached

**Files:**
- `apps/frontend/lib/core/network/websocket_client.dart:84-111`
- `apps/frontend/lib/features/chat/presentation/chat_controller.dart:87-99` (caller)

**Specific Changes Required:**
Option 1 (Recommended): Implement backpressure with callback
```dart
// In send():
if (_outboundBuffer.length > 400) {
  // Warn caller about queue buildup
  _onBackpressure?.call(_outboundBuffer.length);
}
if (_outboundBuffer.length >= 500) {
  throw Exception('WebSocket buffer full; message queue overflowed');
}

// Add callback:
Function(int)? _onBackpressure;
void setOnBackpressure(Function(int) callback) => _onBackpressure = callback;
```

Option 2: Increase cap with monitoring
- Increase cap to 1000 items
- Add metrics tracking queue depth
- Log warning at 75% capacity

**Estimated Hours:** 1.0
- 0.4h: Implement backpressure or monitoring
- 0.3h: Update callers to handle backpressure
- 0.2h: Add unit tests
- 0.1h: Test under load

**Dependencies:**
- None

**Risk:**
- Low: Client-side buffer management
- Could introduce latency if backpressure applied

**Acceptance Criteria:**
1. Buffer behavior documented
2. Backpressure signaling working (or cap increased with monitoring)
3. No silent message loss
4. Load test shows <5% packet loss under 100 msg/sec load
5. Metrics track queue depth

**Definition of Done:**
- WebSocket client updated
- Callers updated to handle backpressure
- Unit tests pass
- Load test scenario passes
- Code review approved

---

## P2: MEDIUM PRIORITY

**Criteria:** Should complete before production use. Requires investigation or minor implementation.

---

### P2-1: Investigate BLE Scanning Integration (Feature Verification)

**Priority:** MEDIUM  
**Effort:** 4.0 hours  
**Assigned:** Frontend Team

**Problem:**
BLE scanning feature structure exists but actual integration between frontend BLE scanner and backend Nearby Service is not verified. `proximityUsersProvider` contains mock data; unclear if real BLE results flow to backend.

**Root Cause:**
- `lib/features/nearby/domain/proximity_user.dart:22-46` provides mock data with hardcoded users
- `lib/core/utils/battery_optimizer.dart` initializes BLE scanning but no connection to provider visible
- No `lib/features/nearby/data/` repository layer found
- Data flow from BLE scanner → provider → backend unclear

**Investigation Scope:**

1. **Verify BLE Scanning Initialization:**
   - Inspect `main.dart` for `BatteryOptimizer` usage
   - Confirm `flutter_reactive_ble` subscription active
   - Verify BLE adapter permissions

2. **Trace Data Flow:**
   - Find source of truth for proximity data (mock vs. real BLE)
   - Verify `proximityUsersProvider` subscription to BLE results
   - Confirm scanning results reach UI

3. **Backend Integration:**
   - Trace `NearbyScreen.onTap()` → `chatRepository.getOrCreateRoom()` call
   - Verify backend Nearby Service is queried
   - Confirm H3 grid matching happens server-side

4. **Acceptance:**
   - Document current state (mock vs. real)
   - Identify gaps in integration
   - Create follow-up tasks for missing pieces

**Files to Inspect:**
- `apps/frontend/lib/main.dart` (BatteryOptimizer init)
- `apps/frontend/lib/core/utils/battery_optimizer.dart` (BLE scanning)
- `apps/frontend/lib/features/nearby/domain/proximity_user.dart` (mock data)
- `apps/frontend/lib/features/nearby/presentation/nearby_screen.dart` (UI)
- `apps/backend/services/nearby/cmd/nearby/main.go` (backend)
- `proto/nearby/v1/nearby.proto` (contract)

**Estimated Hours:** 4.0
- 1h: Review frontend code flow
- 1h: Trace BLE → provider → UI
- 1h: Inspect backend Nearby Service
- 1h: Document findings and gaps

**Dependencies:**
- None

**Risk:**
- Low: Investigation only, no code changes

**Acceptance Criteria:**
1. BLE scanning mechanism documented (mock vs. real)
2. Data flow from BLE → UI mapped
3. Backend query mechanism verified
4. Gaps identified (if any)
5. Follow-up tasks created (if needed)

**Definition of Done:**
- Investigation complete
- Findings documented in comment on this task
- Follow-up implementation tasks created (if gaps found)
- Code review not needed (investigation task)

---

### P2-2: Investigate Read Receipt State Machine (Feature Verification)

**Priority:** MEDIUM  
**Effort:** 4.0 hours  
**Assigned:** Backend + Frontend Team

**Problem:**
Frontend sends read receipts via WebSocket but backend handling is not verified. State transitions (SENT → DELIVERED → READ) incomplete or not wired end-to-end.

**Root Cause:**
- `apps/frontend/lib/features/chat/data/chat_repository.dart:136-147` sends `RECEIPT` message type
- Chat Service message handlers not inspected for `RECEIPT` handling
- Message status update logic in backend unclear
- Frontend may not listen for status changes

**Investigation Scope:**

1. **Frontend Receipt Sending:**
   - Verify `sendReadReceipt()` sends via WebSocket
   - Confirm receipt contains message_id, room_id, status, timestamp
   - Check `ChatRepository.startWebSocketListener()` for receipt handling

2. **Backend Receipt Processing:**
   - Find Chat Service handler for `RECEIPT` message type
   - Verify handler updates message status in database
   - Check error handling and logging

3. **Message Status Storage:**
   - Inspect database schema for message delivery status column
   - Verify SENT → DELIVERED → READ transitions
   - Check query logic for fetching status

4. **Frontend Status Display:**
   - Verify UI displays delivery indicators
   - Check if frontend listens for status updates from backend
   - Confirm state updates reflect in UI

5. **Acceptance:**
   - Document state machine (current vs. desired)
   - Identify gaps in implementation
   - Create follow-up implementation tasks

**Files to Inspect:**
- `apps/frontend/lib/features/chat/data/chat_repository.dart:36-147` (receipt sending)
- `apps/frontend/lib/features/chat/presentation/chat_controller.dart` (state management)
- `apps/backend/services/chat/internal/` (message handlers)
- `proto/nearby/v1/chat.proto:66-80` (receipt message schema)
- `database/migrations/000004_read_receipts.up.sql` (schema)

**Estimated Hours:** 4.0
- 1h: Frontend receipt logic
- 1.5h: Backend handler inspection
- 1h: Database schema verification
- 0.5h: Document findings

**Dependencies:**
- None

**Risk:**
- Low: Investigation only, no code changes

**Acceptance Criteria:**
1. Frontend receipt sending verified
2. Backend handler found or identified as missing
3. Database status tracking verified
4. State machine transitions documented
5. Gaps identified (if any)

**Definition of Done:**
- Investigation complete
- Findings documented with code references
- Follow-up implementation tasks created (if gaps found)
- Code review not needed (investigation task)

---

### P2-3: Investigate Presence Service Redis TTL (Feature Verification)

**Priority:** MEDIUM  
**Effort:** 2.0 hours  
**Assigned:** Backend Team

**Problem:**
Presence Service accepts location updates but no Redis TTL enforcement visible. Stale user presence data accumulates indefinitely, causing false positive proximity matches.

**Root Cause:**
- `apps/backend/services/presence/cmd/presence/main.go:73-104` accepts heartbeat but no `EXPIRE` command visible
- Redis key management in repository layer not inspected
- No garbage collection cron for stale entries
- Stale data persists after user goes offline

**Investigation Scope:**

1. **Heartbeat Endpoint:**
   - Verify `usecase.Heartbeat()` is called with user ID, device ID, H3 index
   - Inspect repository layer (`presenceRepo`)

2. **Redis Key Storage:**
   - Find where presence data stored (likely: `user:{userId}:presence` or similar)
   - Check if `EXPIRE` / `PEXPIRE` called on key
   - Verify TTL set on every update

3. **Cache Invalidation:**
   - Check for explicit `DEL` or expiration
   - Look for periodic cleanup cron job
   - Verify stale data removal strategy

4. **Nearby Service Integration:**
   - Verify Nearby Service queries Redis presence
   - Check how stale data affects proximity matching
   - Estimate data growth without TTL

5. **Acceptance:**
   - Document current TTL strategy (if any)
   - Identify missing TTL configuration
   - Create implementation task with specific TTL value

**Files to Inspect:**
- `apps/backend/services/presence/cmd/presence/main.go:64-104`
- `apps/backend/services/presence/internal/application/` (Heartbeat use case)
- `apps/backend/services/presence/internal/infrastructure/cache/` (Redis repository)
- `apps/backend/services/nearby/` (proximity query logic)

**Estimated Hours:** 2.0
- 0.5h: Review heartbeat endpoint
- 0.75h: Inspect Redis key management
- 0.5h: Check TTL strategy
- 0.25h: Document findings

**Dependencies:**
- None

**Risk:**
- Low: Investigation only

**Acceptance Criteria:**
1. Redis key naming convention documented
2. Current TTL strategy identified (or absence confirmed)
3. Data growth impact estimated
4. Recommended TTL value determined
5. Follow-up implementation task created

**Definition of Done:**
- Investigation complete
- Findings documented with code references
- Implementation task created: "Add Redis TTL to Presence Keys"
- Code review not needed (investigation task)

---

## P3: LOW PRIORITY

**Criteria:** Nice-to-have. Performance, documentation, or operational improvements.

---

### P3-1: Generate Protobuf API Documentation (Developer Experience)

**Priority:** LOW  
**Effort:** 2.0 hours  
**Assigned:** Backend/Docs Team

**Problem:**
No generated API documentation from `.proto` files. Developers must read Protobuf source directly. API contract unclear for external consumers.

**Root Cause:**
- Protobuf compiler not configured with `--doc_out` plugin
- No markdown or HTML documentation generated
- `proto/nearby/v1/` directory has 8 proto files with no formatted reference

**Files:**
- `proto/nearby/v1/*.proto` (all 8 proto files)
- `scripts/generate_proto.sh` (build script)
- New: `docs/api/protobuf.md` or `docs/api/`

**Specific Changes Required:**
1. Install protoc documentation plugin
2. Update `scripts/generate_proto.sh` to generate docs
3. Generate markdown API reference
4. Add link to main README
5. Document message schemas, RPC endpoints, enums

**Estimated Hours:** 2.0
- 0.5h: Install protoc-gen-doc plugin
- 0.75h: Update build script
- 0.5h: Generate and review output
- 0.25h: Add to README and docs structure

**Dependencies:**
- None

**Risk:**
- Low: Documentation only

**Acceptance Criteria:**
1. Protobuf documentation generated from source
2. Markdown or HTML format readable
3. All services documented
4. Examples for common message types
5. Linked from main documentation

**Definition of Done:**
- `scripts/generate_proto.sh` updated
- Documentation generated
- `docs/api/` populated with generated docs
- README links to API documentation
- Code review approved

---

### P3-2: Create Runbooks and Operational Playbooks (SRE Readiness)

**Priority:** LOW  
**Effort:** 4.0 hours  
**Assigned:** SRE/DevOps Team

**Problem:**
No runbooks for common operational procedures. Operators lack guidance on disaster recovery, scaling, troubleshooting, and incident response.

**Root Cause:**
- No `docs/runbooks/` directory
- Infrastructure complexity not documented procedurally
- Operators must infer procedures from code

**Files:**
- New: `docs/runbooks/` directory with playbooks
- Reference: `infrastructure/dr/`, database partition docs, Helm values

**Specific Changes Required:**
Create runbooks for:
1. **Database Partition Expansion** (20 partitions → 32)
   - Pre-flight checks
   - Expansion procedure
   - Verification steps
   - Rollback procedure

2. **PostgreSQL Replica Promotion**
   - Detect primary failure
   - Promote replica to primary
   - Update application connection strings
   - Verify data integrity

3. **Redis Failover**
   - Sentinel trigger conditions
   - Manual failover procedure
   - Verification checks

4. **Canary Rollback**
   - SLA violation detection
   - Manual rollback steps
   - Service restart procedure
   - Health verification

5. **Scaling Microservices**
   - Horizontal pod autoscaler tuning
   - Node pool expansion
   - Traffic management during scale

**Estimated Hours:** 4.0
- 1h: Partition expansion runbook
- 0.75h: Database replica runbook
- 0.75h: Redis runbook
- 0.75h: Canary rollback runbook
- 0.75h: Scaling runbook

**Dependencies:**
- None

**Risk:**
- Low: Documentation only

**Acceptance Criteria:**
1. Clear step-by-step procedures
2. Pre-requisites and safety checks documented
3. Rollback procedures included
4. Example commands provided
5. Verification steps included

**Definition of Done:**
- All runbooks created in `docs/runbooks/`
- Reviewed by SRE/ops team
- Tested (at least dry-run)
- Linked from operational handbook
- Code review approved

---

## Summary Table

| ID | Title | P | Effort | Status |
|---|---|---|---|---|
| P0-1 | Fix Flutter Test Type Mismatches | CRITICAL | 0.5h | Blocked: Awaiting approval |
| P0-2 | Remove Hardcoded Secrets from Helm | CRITICAL | 2.0h | Blocked: Security gate |
| P0-3 | Implement End-to-End Message Encryption | CRITICAL | 8.0h | Blocked: Awaiting approval |
| P0-4 | Align Go Module Versions | CRITICAL | 0.5h | Blocked: Build fix |
| P0-5 | Fix Helm Database Connection URL | CRITICAL | 1.0h | Blocked: Deployment blocker |
| **P0 Subtotal** | | | **12.0 hours** | |
| P1-1 | Replace Prometheus Canary Parsing | HIGH | 1.0h | Not started |
| P1-2 | Fix Docker Compose Kafka Health Check | HIGH | 0.5h | Not started |
| P1-3 | Add Retention Policy to Helm ConfigMap | HIGH | 1.0h | Not started |
| P1-4 | Implement WebSocket Buffer Backpressure | HIGH | 1.0h | Not started |
| **P1 Subtotal** | | | **3.5 hours** | |
| P2-1 | Investigate BLE Scanning Integration | MEDIUM | 4.0h | Not started |
| P2-2 | Investigate Read Receipt State Machine | MEDIUM | 4.0h | Not started |
| P2-3 | Investigate Presence Service Redis TTL | MEDIUM | 2.0h | Not started |
| **P2 Subtotal** | | | **10.0 hours** | |
| P3-1 | Generate Protobuf API Documentation | LOW | 2.0h | Not started |
| P3-2 | Create Operational Runbooks | LOW | 4.0h | Not started |
| **P3 Subtotal** | | | **6.0 hours** | |
| | | | **TOTAL: 31.5 hours** | |

---

## Implementation Sequencing

### Phase 1: Unblock CI/CD (Days 1-2)
**Goal:** Fix build pipeline and enable deployments

1. **P0-1:** Fix Flutter test types (0.5h)
2. **P0-4:** Align Go versions (0.5h)
3. **P0-5:** Fix Helm database URL (1h)
4. **P1-2:** Fix Kafka health check (0.5h)

**Phase 1 Total:** 2.5 hours  
**Outcome:** CI passes, local dev environment works, deployments executable

### Phase 2: Security & Privacy (Days 3-5)
**Goal:** Address critical security/privacy gaps

1. **P0-2:** Remove hardcoded secrets (2h)
2. **P0-3:** Implement message encryption (8h)

**Phase 2 Total:** 10 hours  
**Outcome:** System meets security/privacy requirements for production

### Phase 3: Operational Readiness (Days 6-7)
**Goal:** Prepare for production deployment

1. **P1-1:** Fix Prometheus canary parsing (1h)
2. **P1-3:** Add retention policy config (1h)
3. **P1-4:** Implement WebSocket backpressure (1h)

**Phase 3 Total:** 3 hours  
**Outcome:** Monitoring reliable, configuration flexible, messages safe

### Phase 4: Feature Verification (Week 2)
**Goal:** Verify core features work end-to-end

1. **P2-1:** Investigate BLE scanning (4h)
2. **P2-2:** Investigate read receipts (4h)
3. **P2-3:** Investigate presence TTL (2h)

**Phase 4 Total:** 10 hours  
**Outcome:** Feature gaps identified, implementation tasks created

### Phase 5: Documentation (Week 3)
**Goal:** Enable operators and developers

1. **P3-1:** Generate API docs (2h)
2. **P3-2:** Create runbooks (4h)

**Phase 5 Total:** 6 hours  
**Outcome:** Operational procedures documented, API clear

---

## Release Gate Criteria

**DO NOT DEPLOY TO PRODUCTION UNTIL:**

✅ P0-1 through P0-5 **COMPLETED**  
✅ P1-1 through P1-4 **COMPLETED**  
✅ P2-1 through P2-3 **INVESTIGATED** (implementation tasks created if gaps found)  
✅ Security review **APPROVED**  
✅ Privacy review **APPROVED** (message encryption verified)  
✅ Load testing **PASSED** (10k concurrent users, <100ms p95 latency)

---

## Notes

- This backlog is **derived exclusively from validated audit findings** in `docs/reports/audit-validation.md`
- **False positive findings excluded:** Database pooling, Kafka integration, rate limiting, compliance service (all already implemented)
- **Investigation tasks (P2) do not include code changes:** They produce acceptance criteria for follow-up implementation
- **All estimates include testing and review time**
- **Dependencies between tasks documented:** P0-2 and P0-5 should be completed in same security pass
- **No speculative work:** Every task traces back to a verified finding with file paths and line numbers

---

*Backlog Generated: 2026-07-21*  
*Source: docs/reports/audit-validation.md*  
*Review Status: Awaiting Engineering Team Approval*
