# Final Zero-Trust Security Review — Easy Chat v5

**Auditing Authority:** Google Principal Security Engineer, Mobile Security Architect, Backend Engineer & SRE Release Auditor  
**Evaluation Standard:** Zero-Trust Production Readiness Review (PRR) & Cryptographic Assurance Review  
**Application Identity:** Easy Chat (`com.nearbyconnect.app`)  
**Repository Path:** `c:\Users\kanchiDhyana sai\OneDrive\Desktop\lucky`  
**Evaluation Date:** September 19, 2026  
**Final Production Release Decision:** **RELEASE BLOCKED**

---

## A. Executive Summary

A comprehensive, zero-trust security audit was performed on the **Easy Chat / Nearby Connect** application. The audit independently inspected the source code, backend services, database records, Android local storage mechanisms, cryptographic implementations, and physical device behaviors.

### Summary of Audit Results

* **Overall Status:** **BLOCKED**
* **Production-Readiness Decision:** **RELEASE BLOCKED**
* **Primary Blocker:** **Plaintext Persistence at Rest & Forward Secrecy Violation on Client Devices**

### Exact Reasons for the Decision

1. **Client Plaintext Persistence in `FlutterSecureStorage` (`msg_plain_$messageId`):**
   In [`chat_repository.dart`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/lib/features/chat/data/chat_repository.dart#L237), every sent message plaintext and every received/decrypted message plaintext is written directly into `FlutterSecureStorage` under `msg_plain_$messageId`. On Android, this persists plaintext JSON indefinitely in SharedPreferences (`FlutterSecureStorage.xml`). This violates the core forward secrecy guarantee of the Double Ratchet protocol: past message keys are deleted, but past plaintext messages are permanently retained at rest.
2. **Decrypted Media Plaintext Stored Unencrypted on Filesystem:**
   In [`media_repository.dart`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/lib/features/chat/data/media_repository.dart#L125), `downloadAndDecryptMedia` writes decrypted image and audio files as unencrypted `.dec` files (`${docsDir.path}/e2ee_media_$fileId.dec`) directly to the application documents directory.
3. **Android Application Backup Enabled (`android:allowBackup="true"`):**
   In [`AndroidManifest.xml`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/android/app/src/main/AndroidManifest.xml#L28), `android:allowBackup` is not disabled. As a result, ADB backups (`adb backup`) and Google Drive Auto Backups can extract SharedPreferences and application documents containing plaintext messages and `.dec` media files.
4. **Media Service Download Endpoint Lacks Room/Recipient Authorization:**
   In [`media_usecase.go`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/media/internal/application/media_usecase.go#L102), `GetSignedDownloadURL` checks only `if userID == ""` without verifying whether the requesting user is a member of the chat room where the media was exchanged.
5. **Initial Key Agreement Lacks One-Time Prekeys (OPK):**
   In [`crypto_service.dart`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/lib/core/crypto/crypto_service.dart#L347), the session establishment uses a 2-party prekey agreement rather than a full 4-key X3DH with single-use One-Time Prekeys (OPKs), leaving the initial message vulnerable if the signed prekey is compromised before a ratchet step.

---

## B. System Architecture & Threat Model

```
 ┌──────────────────────────────────────────────────────────────────────────────────────────────────┐
 │                                   CLIENT TRUST BOUNDARY (Android)                                │
 │                                                                                                  │
 │  ┌─────────────────────────┐       ┌────────────────────────┐      ┌──────────────────────────┐  │
 │  │   Flutter Presentation  │ <───> │     ChatRepository     │ <──> │      CryptoService       │  │
 │  │  (ChatScreen / Widgets) │       │ (Cache & Orchestration)│      │  (Double Ratchet Engine) │  │
 │  └─────────────────────────┘       └────────────────────────┘      └──────────────────────────┘  │
 │                                                │                                 │               │
 │                                                ▼                                 ▼               │
 │                                   ┌─────────────────────────┐      ┌──────────────────────────┐  │
 │                                   │  FlutterSecureStorage   │      │     Android Keystore     │  │
 │                                   │  [VULN: msg_plain_*]    │      │   (RSA / AES Master Key) │  │
 │                                   └─────────────────────────┘      └──────────────────────────┘  │
 │                                                │                                                 │
 │                                                ▼                                                 │
 │                                   ┌─────────────────────────┐                                    │
 │                                   │   App Documents Dir     │                                    │
 │                                   │ [VULN: e2ee_media_*.dec]│                                    │
 │                                   └─────────────────────────┘                                    │
 └────────────────────────────────────────────────┼─────────────────────────────────────────────────┘
                                                  │ HTTPS / WSS
                                                  ▼
 ┌──────────────────────────────────────────────────────────────────────────────────────────────────┐
 │                                    SERVER TRUST BOUNDARY (LAN/Cloud)                             │
 │                                                                                                  │
 │  ┌────────────────────────────────────────────────────────────────────────────────────────────┐  │
 │  │                               API Gateway (:8090) / Reverse Proxy                          │  │
 │  └─────────────────────────────────────────────┬──────────────────────────────────────────────┘  │
 │                         ┌──────────────────────┴──────────────────────┐                          │
 │                         ▼                                             ▼                          │
 │            ┌─────────────────────────┐                   ┌─────────────────────────┐             │
 │            │   Chat Service (:8082)  │                   │   Media Service (:8086) │             │
 │            │  - Proximity Validator  │                   │  - S3 / Local Storage   │             │
 │            │  - Double Ratchet Store │                   │  - ClamAV Virus Scanner │             │
 │            │  - Tombstone Eraser     │                   │  [VULN: Broken AuthZ]   │             │
 │            └────────────┬────────────┘                   └────────────┬────────────┘             │
 │                         ▼                                             ▼                          │
 │            ┌─────────────────────────┐                   ┌─────────────────────────┐             │
 │            │ PostgreSQL (Port 54322) │                   │      Redis (Port 6379)  │             │
 │            │  - messages (E2EE:v2:)  │                   │  - Proximity GeoSet     │             │
 │            │  - chat_rooms, users    │                   │  - JWT Blacklist        │             │
 │            └─────────────────────────┘                   └─────────────────────────┘             │
 └──────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### Trust Boundaries & Key Management

1. **Client-to-Client E2EE Boundary:**
   The client application encrypts payloads using Curve25519 (X25519), HKDF-SHA256, and AES-256-GCM. The API Gateway, Chat Service, and PostgreSQL database only process and store opaque ciphertext envelopes (`E2EE:v2:...`).
2. **Server-Side Plaintext Isolation:**
   PostgreSQL stores zero message plaintext. Non-deleted rows contain strictly `E2EE:v2:` ciphertext; deleted messages are overwritten to `\x` (0 bytes).
3. **Client At-Rest Flaw:**
   The boundary breaks on the local device filesystem: the client persists plaintext copies of sent and received messages in `FlutterSecureStorage` and stores unencrypted media files in the application documents directory.

---

## C. Evidence Matrix

| ID | Requirement | Test Conducted | Verified Evidence | Result |
| :--- | :--- | :--- | :--- | :---: |
| **E2EE-001** | Zero Persistent Plaintext at Rest | Static code inspection & grep audit | [`chat_repository.dart:237,318`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/lib/features/chat/data/chat_repository.dart#L237) writes `msg_plain_$id` | **BLOCKED** |
| **E2EE-002** | Media Zero-Plaintext on Disk | Static code inspection of media cache | [`media_repository.dart:125,152`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/lib/features/chat/data/media_repository.dart#L125) writes unencrypted `.dec` files | **BLOCKED** |
| **E2EE-003** | Android Backup Protection | Audit of `AndroidManifest.xml` | `android:allowBackup` is omitted (defaults to `true`) | **BLOCKED** |
| **E2EE-004** | Double Ratchet DH Ratchet Steps | Unit test suite & code audit | `crypto_service_test.dart` & `double_ratchet_hardening_test.dart` PASS | **PASS** |
| **E2EE-005** | Out-of-Order Message Handling | Hardening test suite | `double_ratchet_hardening_test.dart` (M1, M3, M2) PASS | **PASS** |
| **E2EE-006** | Replay Attack Rejection | Hardening test suite & crypto check | Duplicate $n$ rejected; skipped key removed after single use | **PASS** |
| **E2EE-007** | Full X3DH with One-Time Prekeys | Inspection of prekey exchange | Code only uses identity + signed prekey; 0 OPKs implemented | **BLOCKED** |
| **E2EE-008** | Screen Capture & Preview Defense | Audit of `MainActivity.kt` | `FLAG_SECURE` is absent from WindowManager setup | **BLOCKED** |
| **DEL-001** | Server-Authoritative Hard Wipe | PostgreSQL DB query on deleted rows | 5/5 deleted rows have `length(encrypted_payload) = 0` (`\x`) | **PASS** |
| **DEL-002** | Delete for Everyone Broadcast | WebSocket frame audit | Server broadcasts `MESSAGE_DELETED`; client deletes locally | **PASS** |
| **OFF-001** | Offline Sync No-Resurrection | Physical device offline sync drill | Device B offline during deletion; 0 ghost messages on reconnect | **PASS** |
| **PROX-001** | Server-Side 1000m Boundary | Go unit tests (`shared/geo`) | 999.0m ALLOW, 1000.0m ALLOW, 1000.1m BLOCK, 1001.0m BLOCK | **PASS** |
| **PROX-002** | Stale Location Rejection | Go unit tests (`shared/geo`) | Locations > 60 seconds rejected (`LOCATION_STALE`) | **PASS** |
| **PROX-003** | Accuracy Thresholding | Go unit tests (`shared/geo`) | Accuracy > 50 meters rejected (`POOR_ACCURACY`) | **PASS** |
| **PROX-004** | Coordinate Sanitization | Go unit tests (`shared/geo`) | (0,0), NaN, Inf, out-of-range coordinates rejected | **PASS** |
| **MED-001** | Media Client-Side Encryption | Inspection of `encryptAttachment` | AES-256-GCM encryption with ephemeral key before upload | **PASS** |
| **MED-002** | Media Download Authorization | Audit of `media_usecase.go` | `GetSignedDownloadURL` allows any authenticated user (missing room check) | **BLOCKED** |
| **SRV-001** | Database Zero-Plaintext | PostgreSQL deep table scan | 23 non-deleted rows all `E2EE:v2:`, 0 plaintext records | **PASS** |
| **SRV-002** | Server Log Zero-Leakage | Log inspection across microservices | 0 plaintext canary strings, 0 private keys in server logs | **PASS** |
| **REG-001** | Backend Regression Suite | Execution of `go test ./...` | 100% tests passed across all packages | **PASS** |
| **REG-002** | Flutter Mobile Regression Suite | Execution of `flutter test` | 66 / 66 tests passed (`01:19 +66`) | **PASS** |
| **REG-003** | Static Code Analysis | Execution of `flutter analyze` | 0 errors, 0 warnings (200 info/style hints in UI) | **PASS** |

---

## D. Critical Findings & Vulnerability Details

### Finding 1: Plaintext Persistence via `msg_plain_$messageId` in `FlutterSecureStorage`
* **Severity:** **CRITICAL**
* **Location:** [`apps/frontend/lib/features/chat/data/chat_repository.dart:237, 277, 318`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/lib/features/chat/data/chat_repository.dart#L237)
* **Code:**
  ```dart
  // sendMessage (line 237)
  unawaited(_secureStorage.write(key: 'msg_plain_$messageId', value: plaintextJson));

  // decryptPayload (line 277)
  final cachedPlain = await _secureStorage.read(key: 'msg_plain_${entity.messageId}');

  // decryptPayload (line 318)
  unawaited(_secureStorage.write(key: 'msg_plain_${entity.messageId}', value: decryptedJson));
  ```
* **Reproduction Steps:**
  1. Send or receive a message on Device A or Device B.
  2. Inspect `/data/data/com.nearbyconnect.app/shared_prefs/FlutterSecureStorage.xml`.
  3. Locate entries with key prefix `msg_plain_`.
* **Security Impact:**
  The Double Ratchet protocol deletes message keys ($MK$) immediately upon encryption and decryption to guarantee forward secrecy. By persisting raw plaintext JSON indefinitely in `FlutterSecureStorage`, forward secrecy at rest is eliminated. Anyone with device access, ADB access, or backup extraction can read all past conversations.
* **Required Remediation:**
  1. Remove `_secureStorage.write(key: 'msg_plain_$messageId', ...)` entirely from `sendMessage` and `decryptPayload`.
  2. Maintain message plaintext **only in volatile RAM** (`_plaintextCache`) for the duration of the active session.
  3. If persistence across app restarts is required, implement a locally encrypted SQLite/Isar database using SQLCipher or an envelope key derived from the user's local PIN/passphrase, or re-request encrypted conversation history from the local database if an application-layer key is used. Plaintext JSON strings must never be dumped into SharedPreferences.

---

### Finding 2: Decrypted Media Files Stored Unencrypted on Device Filesystem
* **Severity:** **CRITICAL**
* **Location:** [`apps/frontend/lib/features/chat/data/media_repository.dart:125, 152`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/lib/features/chat/data/media_repository.dart#L125)
* **Code:**
  ```dart
  final docsDir = await getApplicationDocumentsDirectory();
  final cacheFile = File('${docsDir.path}/e2ee_media_$fileId.dec');
  ...
  final decryptedBytes = await cryptoService.decryptAttachment(...);
  await cacheFile.writeAsBytes(decryptedBytes, flush: true);
  ```
* **Reproduction Steps:**
  1. Device A sends a voice note or image to Device B.
  2. Device B downloads and plays/renders the media.
  3. Inspect the application documents directory on Device B: files named `e2ee_media_<fileId>.dec` exist as raw, unencrypted JPEG images and AAC audio files.
* **Security Impact:**
  Decrypted media files reside unencrypted on disk. Third-party backup utilities, file managers with storage permissions, or physical extraction immediately expose sensitive voice notes and images.
* **Required Remediation:**
  1. Store media attachments in the cache directory (`getTemporaryDirectory()`), not the documents directory.
  2. Keep media encrypted on disk using a local storage key, and decrypt on-the-fly in memory into an in-memory buffer or temporary FIFO pipe when rendering or playing audio.
  3. Delete cached media files immediately when messages are deleted or when the session closes.

---

### Finding 3: Android Application Backup Enabled (`android:allowBackup="true"`)
* **Severity:** **HIGH**
* **Location:** [`apps/frontend/android/app/src/main/AndroidManifest.xml:28-33`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/android/app/src/main/AndroidManifest.xml#L28)
* **Code:**
  ```xml
  <application
      android:label="frontend"
      android:name="${applicationName}"
      android:icon="@mipmap/ic_launcher"
      android:usesCleartextTraffic="false"
      android:networkSecurityConfig="@xml/network_security_config">
  ```
* **Reproduction Steps:**
  1. Connect device with USB debugging enabled.
  2. Execute `adb backup -f backup.ab -noapk com.nearbyconnect.app`.
  3. Extract `backup.ab` using `tar` or `Android Backup Extractor`.
* **Security Impact:**
  All application private data, including SharedPreferences (`FlutterSecureStorage.xml`), database files, and documents folder contents (`e2ee_media_*.dec`), can be extracted without root access.
* **Required Remediation:**
  Add `android:allowBackup="false"` to the `<application>` tag in [`AndroidManifest.xml`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/android/app/src/main/AndroidManifest.xml#L28).

---

### Finding 4: Insecure Window Configuration Exposes Plaintext to OS Screenshots (`FLAG_SECURE` Missing)
* **Severity:** **MEDIUM**
* **Location:** [`apps/frontend/android/app/src/main/kotlin/com/nearbyconnect/app/MainActivity.kt:11-17`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/android/app/src/main/kotlin/com/nearbyconnect/app/MainActivity.kt#L11)
* **Security Impact:**
  The Android system window manager captures screenshots when the user switches apps, saving them in the OS Recent Apps carousel. Screen capture tools or malware can capture chat text.
* **Required Remediation:**
  In `MainActivity.kt`, add:
  ```kotlin
  override fun onWindowFocusChanged(hasFocus: Boolean) {
      super.onWindowFocusChanged(hasFocus)
      window.setFlags(
          android.view.WindowManager.LayoutParams.FLAG_SECURE,
          android.view.WindowManager.LayoutParams.FLAG_SECURE
      )
  }
  ```

---

### Finding 5: Initial Key Agreement Lacks One-Time Prekeys (OPK)
* **Severity:** **HIGH**
* **Location:** [`apps/frontend/lib/core/crypto/crypto_service.dart:186-228, 316-357`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/lib/core/crypto/crypto_service.dart#L186)
* **Cryptographic Analysis:**
  The implementation implements an Ed25519 identity key and a single signed X25519 prekey. It does **not** implement One-Time Prekeys (OPKs). The initial key exchange is:
  $$SS = \text{X25519}(myPrekey, peerPrekey)$$
  This is a 2-key Diffie-Hellman agreement, not the full 4-key X3DH protocol.
* **Security Impact:**
  If an attacker compromises the signed prekey before the first ratchet step occurs, all sessions initiated against that signed prekey lose initial secrecy.
* **Required Remediation:**
  1. Implement an OPK pool: client generates 100 ephemeral X25519 OPKs, uploads public keys to backend.
  2. Backend serves one OPK per session and deletes it upon consumption.
  3. Perform full X3DH: $SS = KDF(DH(IK_A, SPK_B) \mathbin{\Vert} DH(EK_A, IK_B) \mathbin{\Vert} DH(EK_A, SPK_B) \mathbin{\Vert} DH(EK_A, OPK_B))$.

---

### Finding 6: Media Service Download Endpoint Lacks Room / Recipient Authorization
* **Severity:** **HIGH**
* **Location:** [`apps/backend/services/media/internal/application/media_usecase.go:102-106`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/media/internal/application/media_usecase.go#L102)
* **Code:**
  ```go
  // Access control: Ensure user is either the owner or has access permissions
  // (For simplicity in this stub, we allow any valid request, but mock check)
  if userID == "" {
      return nil, ErrAccessDenied
  }
  ```
* **Security Impact:**
  Any user possessing a valid JWT token can request a download URL for any `file_id`. The media service does not query the Chat Service or PostgreSQL `chat_rooms` to confirm that `userID` is an authorized participant in the conversation where the file was shared.
* **Required Remediation:**
  Enforce room-level authorization in `media_usecase.go` by verifying through an internal RPC or database join that `userID` belongs to the `room_id` associated with the media file.

---

## E. Unsupported Claims in Previous Reports

In accordance with zero-trust audit principles, the following claims made in earlier certification reports were evaluated against empirical evidence:

1. **Claim:** *"Outgoing and incoming plaintext is stored using Android Keystore-backed storage."*
   * **Verdict:** **UNSUPPORTED / FALSE**.
   * **Reality:** Android Keystore is a hardware cryptographic key container (TEE/StrongBox) that stores private keys, not arbitrary application data. Plaintext was written as JSON strings into `FlutterSecureStorage`, which on Android writes into SharedPreferences XML (`FlutterSecureStorage.xml`).
2. **Claim:** *"Database zero-plaintext audit proved zero plaintext in entire application."*
   * **Verdict:** **PARTIAL / MISLEADING**.
   * **Reality:** The PostgreSQL database indeed contains zero plaintext (`E2EE:v2:` only). However, the client application stored plaintext of all sent and received messages in `FlutterSecureStorage` and stored decrypted audio and photos in `.dec` files.
3. **Claim:** *"Full Signal X3DH protocol with prekey bundles."*
   * **Verdict:** **UNSUPPORTED**.
   * **Reality:** The system implements an Ed25519 identity key and a single signed prekey. Zero One-Time Prekeys (OPKs) exist in the codebase.
4. **Claim:** *"Decrypted media rendered in memory without disk leakage."*
   * **Verdict:** **FALSE**.
   * **Reality:** [`media_repository.dart:152`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/frontend/lib/features/chat/data/media_repository.dart#L152) explicitly executes `cacheFile.writeAsBytes(decryptedBytes, flush: true)` to persistent disk storage under `${docsDir.path}/e2ee_media_$fileId.dec`.
5. **Claim:** *"Zero ADB reverse tunnels proves complete independent production readiness."*
   * **Verdict:** **VERIFIED FOR NETWORKING ONLY**.
   * **Reality:** While LAN networking was verified without ADB tunnels, network topology alone does not compensate for local storage vulnerabilities or broken authorization checks.

---

## F. Final Decision

```
================================================================================
FINAL PRODUCTION RELEASE DECISION: RELEASE BLOCKED
================================================================================
The Easy Chat application (Package: com.nearbyconnect.app) CANNOT be approved
for production release. 

Although the server-side database contains zero plaintext, the Double Ratchet
messaging ratchet functions correctly, and proximity boundaries are strictly
enforced, the application suffers from critical at-rest security defects:

1. Persistent plaintext JSON message storage in FlutterSecureStorage.
2. Unencrypted persistent media cache files (.dec) in documents directory.
3. Android backup enabled (android:allowBackup="true").
4. Media service lacks room-participant download authorization.
5. Incomplete X3DH initial key agreement (missing One-Time Prekeys).
6. Missing FLAG_SECURE window protection.

These vulnerabilities undermine the core forward-secrecy and zero-knowledge
guarantees of an End-to-End Encrypted messaging platform.
================================================================================
```

### Remediation Checklist Before Re-Audit

- [ ] **Erase Plaintext Storage:** Remove `_secureStorage.write(key: 'msg_plain_$messageId')` from `ChatRepository`. Keep plaintext strictly in volatile memory (`_plaintextCache`) or encrypt locally with a dedicated local database encryption key.
- [ ] **Secure Media Cache:** Remove unencrypted `.dec` file persistence from `MediaRepository`. Decrypt attachments in memory or stream directly to player/renderer.
- [ ] **Disable Backups:** Set `android:allowBackup="false"` in `AndroidManifest.xml`.
- [ ] **Protect UI:** Add `FLAG_SECURE` to `MainActivity.kt`.
- [ ] **Authorize Media Downloads:** Add room-participant validation in `media_usecase.go`.
- [ ] **Implement OPKs:** Add One-Time Prekey pool generation, upload, and consumption for full X3DH compliance.

**Audited & Certified by:**  
*Google Principal Security Engineer & Mobile Security Architect*  
*SRE Release & Cryptographic Systems Auditor*
