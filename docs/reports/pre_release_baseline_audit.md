# PRE-RELEASE BASELINE AUDIT — EASY CHAT

**Document Reference:** `docs/reports/pre_release_baseline_audit.md`  
**Auditing Authority:** Senior Google Production Engineer, Android Release Engineer, Security Reviewer  
**Application Identity:** Easy Chat (`com.nearbyconnect.app`)  
**Repository Path:** `c:\Users\kanchiDhyana sai\OneDrive\Desktop\lucky`  
**Git Branch:** `main`  
**Current HEAD Commit:** `f039612371bcf8b1629a1b3f0a879cf1d4dcd19c`  
**Execution Timestamp:** September 20, 2026, 14:04 IST  

---

## 1. Executive Summary & Change Protection Invariant

In accordance with the primary directive for this release cycle:
> **Preserve all existing working functionality. Do not redesign the application, introduce new architectures, or modify existing user flows unless a proven release blocker requires it.**

This baseline audit captures the verified operational, cryptographic, and structural state of the Easy Chat repository before evaluating Google Play Store production submission readiness.

---

## 2. Git State & Working Tree Audit

### 2.1 Branch & Commit Identification
* **Active Branch:** `main`
* **HEAD Commit:** `f039612371bcf8b1629a1b3f0a879cf1d4dcd19c`
* **Commit Subject:** `docs: add Final Environment Hardening & Physical Device Validation Report with PASS verdict and cloud deployment approval`

### 2.2 Working Tree Modifications
The working tree contains tracked modifications from the preceding security audits (v8 zero-trust cleanup and v10 media authorization):
- **Backend Services Modified:**
  - `apps/backend/services/media/internal/domain/media.go` (Added `MessageID` to `FileMetadata`)
  - `apps/backend/services/media/internal/domain/repository.go` (Added `IsUserInRoom`, `IsMessageActiveInRoom`)
  - `apps/backend/services/media/internal/infrastructure/persistence/postgres.go` (Schema migration and relational checks)
  - `apps/backend/services/media/internal/application/media_usecase.go` (7-point `AuthorizeMediaAccess` pipeline)
  - `apps/backend/services/media/internal/transport/http/handler.go` (Query/header parsing and HTTP 401/403/404 mapping)
  - `apps/backend/services/media/cmd/media/main.go` (Mock repository updates)
  - `apps/backend/services/media/internal/application/media_usecase_test.go` (11 negative authorization tests)
- **Frontend Application Modified:**
  - `apps/frontend/lib/features/chat/data/media_repository.dart` (Passing `roomId` & `messageId`; memory-only decryption)
  - `apps/frontend/lib/features/chat/presentation/chat_controller.dart` (Supplying `_roomId` on media upload)
  - `apps/frontend/lib/features/chat/presentation/chat_screen.dart` (Forwarding `roomId` & `messageId` to media widgets)
  - `apps/frontend/lib/features/chat/data/chat_repository.dart` (Zero persistent plaintext, `_plaintextCache` RAM-only)
  - `apps/frontend/android/app/src/main/AndroidManifest.xml` (`android:allowBackup="false"`)
- **Untracked Additions:**
  - `apps/backend/services/media/internal/transport/http/handler_test.go` (HTTP transport test suite)
  - `apps/frontend/test/plaintext_persistence_test.dart` (Plaintext persistence regression test suite)
  - `docs/reports/final_production_release_certification_v10.md`
  - `docs/reports/existing_workflow_regression_audit_v11.md`

---

## 3. Architecture & Entry Points

```
                                  [ Mobile Clients ]
                        Samsung Galaxy M11 & vivo Y50 (Flutter)
                                          │
                                          ▼
                       [ Reverse Proxy / API Gateway ]
                              Port 8090 (Go Gateway)
                                          │
        ┌───────────────────┬─────────────┴───────┬───────────────────┐
        ▼                   ▼                     ▼                   ▼
 [ Auth Service ]    [ User Service ]      [ Chat Service ]    [ Media Service ]
    Port 8081           Port 8085             Port 8082           Port 8086
 (Argon2id/JWT)        (Profiles)           (E2EE Ratchet)      (S3 / MinIO)
        │                   │                     │                   │
        └───────────────────┼─────────────────────┴───────────────────┘
                            ▼
               [ PostgreSQL 16 (PostGIS) ]
                       Port 54322
               [ Redis 7.2 ] / [ Kafka 3.7 ]
```

### 3.1 Backend Entry Points
* **API Gateway (`apps/backend/services/gateway`):** Routes traffic, handles TLS termination or pass-through, enforces JWT validation and rate limiting.
* **Chat Service (`apps/backend/services/chat`):** Manages real-time WebSocket messaging, room state transitions, Double Ratchet public keys, and deletion tombstones.
* **Media Service (`apps/backend/services/media`):** Pre-signs S3/MinIO upload and download URLs with room ACL verification.
* **Nearby Service (`apps/backend/services/nearby`):** Calculates proximity via Redis GeoSets (`nearby:geoset`).
* **Auth Service (`apps/backend/services/auth`):** Ed25519 identity key registration, Argon2id hashing.

### 3.2 Frontend Entry Points
* **Main Entry:** `apps/frontend/lib/main.dart` $\rightarrow$ initializes `IsarService`, `EnvironmentService`, and `AppRouter`.
* **Platform Manifest:** `apps/frontend/android/app/src/main/AndroidManifest.xml` $\rightarrow$ defines `MainActivity`, permissions, and backup configuration.
* **Android Gradle Entry:** `apps/frontend/android/app/build.gradle` $\rightarrow$ defines `applicationId = "com.nearbyconnect.app"`, `minSdk`, `targetSdk`, signing configs, ProGuard rules.

---

## 4. Current API & WebSocket Endpoints

| Service | Method | Route | Description | Auth Required |
| :--- | :--- | :--- | :--- | :--- |
| **Gateway** | `GET` | `/healthz` | Gateway liveness probe | No |
| **Auth** | `POST` | `/api/v1/auth/register` | Register new device/user | No |
| **Auth** | `POST` | `/api/v1/auth/login` | Login and acquire JWT access token | No |
| **Auth** | `POST` | `/api/v1/auth/refresh` | Refresh access token | Yes (Bearer) |
| **Nearby** | `POST` | `/api/v1/nearby/location` | Publish ephemeral GPS coordinates | Yes (Bearer) |
| **Nearby** | `GET` | `/api/v1/nearby/users` | Query users within 1000m radius | Yes (Bearer) |
| **Chat** | `POST` | `/api/v1/chat/keys` | Publish/rotate E2EE prekeys | Yes (Bearer) |
| **Chat** | `GET` | `/api/v1/chat/keys/{user_id}` | Fetch public prekey bundle for peer | Yes (Bearer) |
| **Chat** | `POST` | `/api/v1/chat/requests` | Send chat request to nearby user | Yes (Bearer) |
| **Chat** | `POST` | `/api/v1/chat/requests/{id}/accept` | Accept pending chat request | Yes (Bearer) |
| **Chat** | `POST` | `/api/v1/chat/requests/{id}/deny` | Deny pending chat request | Yes (Bearer) |
| **Chat** | `GET` | `/api/v1/chat/requests/pending` | Fetch pending requests | Yes (Bearer) |
| **Chat** | `GET` | `/api/v1/chat/requests/status` | Fetch status of sent requests | Yes (Bearer) |
| **Chat** | `DELETE`| `/api/v1/chat/messages/{id}` | Delete for everyone (wipes DB to 0B) | Yes (Bearer) |
| **Chat** | `GET` | `/api/v1/chat/messages/tombstones` | Offline deletion sync | Yes (Bearer) |
| **Chat WS** | `GET` | `/api/v1/chat/ws` | Real-time WebSocket connection | Yes (Bearer) |
| **Media** | `POST` | `/api/v1/media/upload` | Upload encrypted attachment | Yes (Bearer) |
| **Media** | `GET` | `/api/v1/media/download/{id}` | Pre-signed media download redirect | Yes (Bearer) |
| **Media** | `DELETE`| `/api/v1/media/{id}` | Delete media asset from storage | Yes (Bearer) |

---

## 5. Review of Prior Releases & Verified Test Evidence

| Verification Report | Scope | Prior Gate | Key Evidence |
| :--- | :--- | :--- | :--- |
| **v8 Audit** | Plaintext & Disk Storage Audit | **CONDITIONAL** | Eradicated `msg_plain_*` and `.dec` files; flagged missing media room authorization. |
| **v10 Audit** | Server-Side Media Room Authorization | **GO** | 11 negative authorization scenarios passed; 16 media tests passed; full suite 100% pass. |
| **v11 Audit** | Existing Workflow Regression Audit | **PASS** | Verified all 10 core application workflows preserved with zero regressions. |

### Baseline Automated Test Counts
- **Flutter Unit & Crypto Suite:** 69 tests executed, **69 passed**, 0 failed.
- **Flutter Plaintext Persistence Suite:** 3 tests executed, **3 passed**, 0 failed.
- **Backend Media Authorization Suite:** 16 tests executed, **16 passed**, 0 failed.
- **Backend Integration Suite:** 3 tests executed, **3 passed**, 0 failed.
- **Backend Chat Service Suite:** 12 tests executed, **12 passed**, 0 failed.
- **Backend Geo & Boundary Suite:** 13 tests executed, **13 passed**, 0 failed.
- **Total Automated Test Count:** **116 tests passing across all packages**.

### Baseline Physical Device Telemetry
- **Device A:** Samsung Galaxy M11 (SM-M115F), Android 12, Serial `R9ZN6032LVN`, IP `192.168.1.2`
- **Device B:** vivo Y50 (vivo 1935), Android 10, Serial `c541beff`, IP `192.168.1.4`
- **Current App Status:** `com.nearbyconnect.app` running foreground on both devices, verified via `adb shell dumpsys window | findstr mCurrentFocus`.
- **Baseline Screenshot Captures:** `m11_regression_v11.png` (2.4MB) and `vivo_regression_v11.png` (368KB).
