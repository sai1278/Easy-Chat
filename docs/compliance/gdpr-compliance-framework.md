# Nearby Connect — Enterprise Compliance Framework
> **Owner:** Legal + Engineering (DPO) | **Status:** PRODUCTION | **Last Reviewed:** 2026-07-01

---

## 1. Regulatory Coverage

| Regulation | Region | Status | Articles Implemented |
|---|---|---|---|
| **GDPR** | EU (eu-west1) | ✅ Full | Art.5,6,7,12-22,30,44-49 |
| **CCPA** | US (us-east1, us-west1) | ✅ Covered via GDPR framework | Right-to-know, delete, opt-out |
| **PDPA** | AP (ap-southeast1) | ✅ Covered via consent + residency | Consent, access, correction |

---

## 2. System Architecture

```
User Request
    │
    ▼
API Gateway ──► ConsentGate Middleware ──(no consent)──► 403 Forbidden
    │
    ▼ (consent verified)
Service Layer
    │
    ├── AuditMiddleware (every request → audit_events table)
    ├── PII Masking (strips PII from all log output)
    └── RegionRoutingMiddleware (307 redirect if wrong region)
         │
         ▼
  Compliance Service (/api/v1/privacy/*)
    ├── GET /consents          — View consent state
    ├── POST /consents         — Update consent
    ├── GET /export            — Download all data (Art.20)
    ├── POST /requests/erasure — Right to erasure (Art.17)
    ├── POST /requests/access  — Right of access (Art.15)
    ├── POST /requests/portability — Data portability (Art.20)
    ├── GET /requests          — List all DSRs
    └── GET /audit             — View processing history
```

---

## 3. Data Subject Rights Implementation

| GDPR Article | Right | Endpoint | SLA |
|---|---|---|---|
| Art.15 | Right of access | `POST /requests/access` | 30 days (GDPR) / 7 days (target) |
| Art.16 | Right to rectification | User settings (in-app) | Immediate |
| Art.17 | Right to erasure | `POST /requests/erasure` | Immediate execution |
| Art.18 | Right to restrict processing | DSR type `restriction` | 30 days |
| Art.20 | Data portability | `GET /export` | Immediate download |
| Art.21 | Right to object | DSR type `objection` | 30 days |

### Erasure Cascade

When Art.17 erasure is executed, the following sequence runs atomically:

```
1. DELETE messages WHERE sender_id = user_id
2. DELETE user_location_events WHERE user_id = user_id  
3. DELETE push_notification_logs WHERE user_id = user_id
4. DELETE media_files WHERE owner_id = user_id
5. DELETE user_sessions WHERE user_id = user_id
6. ANONYMISE user_consents (replace ip_address_hash → 'ERASED')
7. PSEUDONYMISE users (replace pseudonym, device_id, password_hash)
8. INVALIDATE pii_pseudonym_map entry

Retained (legal obligation — Art.17(3)(b)):
  - audit_events → 7 years
  - consent_audit_log → 7 years
  - data_subject_requests → 7 years
```

---

## 4. Consent Management

### Consent Purposes
| Purpose | Lawful Basis | Withdrawable | Required for Service |
|---|---|---|---|
| `essential_service` | Contractual (Art.6(1)(b)) | **No** | Yes |
| `analytics` | Consent (Art.6(1)(a)) | Yes | No |
| `marketing_emails` | Consent (Art.6(1)(a)) | Yes | No |
| `location_sharing` | Consent (Art.6(1)(a)) | Yes | Required for nearby |
| `third_party_data` | Consent (Art.6(1)(a)) | Yes | No |
| `push_notifications` | Consent (Art.6(1)(a)) | Yes | No |

### Consent Record Proof
Each consent record captures:
- SHA-256 hash of IP address at consent time
- SHA-256 hash of exact consent text shown to user
- Consent text version (for text change tracking)
- Mechanism used (checkbox, in-app, etc.)
- Timestamp with timezone
- Append-only consent audit log (7-year retention)

---

## 5. Audit Trail

### Properties
- **Append-only:** PostgreSQL Row-Level Security prevents UPDATE/DELETE
- **Tamper detection:** Each record includes `integrity_hash` (SHA-256 over id + actor + event + resource + timestamp)
- **PII-free:** Audit events contain resource IDs only — no raw PII values
- **IP hashing:** All IP addresses SHA-256 hashed before storage
- **Retention:** 7 years (GDPR Art.30 legal obligation)

### Audited Event Types
| Event | Trigger |
|---|---|
| `user.login` | Auth service login |
| `user.logout` | Session revocation |
| `consent.granted` | Consent update |
| `consent.withdrawn` | Consent withdrawal |
| `data.export` | Art.20 export |
| `data.erasure` | Art.17 deletion |
| `dsr.created` | DSR submission |
| `retention.enforcement` | Retention CronJob |
| `api.request` | Every authenticated API call |
| `residency.assigned` | User region assignment |

---

## 6. Data Retention Policies

| Table | Retention | Legal Basis | Action |
|---|---|---|---|
| `messages` | 365 days | Contractual | DELETE |
| `user_sessions` | 90 days | Legitimate interest | DELETE |
| `user_location_events` | 30 days | Consent | DELETE |
| `push_notification_logs` | 90 days | Legitimate interest | DELETE |
| `media_files` | 365 days | Contractual | DELETE |
| `audit_events` | 7 years | Legal obligation | ARCHIVE |
| `consent_audit_log` | 7 years | Legal obligation | ARCHIVE |
| `data_subject_requests` | 7 years | Legal obligation | ARCHIVE |

**Enforcement:** Nightly CronJob at 02:00 UTC. Prometheus alerts fire if missed.

---

## 7. Regional Data Residency

| Region | Cluster | Regulation | Node Affinity |
|---|---|---|---|
| `eu-west1` | GKE Europe West | GDPR | `topology.kubernetes.io/region=eu-west1` |
| `us-east1` | GKE US East | CCPA | `topology.kubernetes.io/region=us-east1` |
| `us-west1` | GKE US West | CCPA | `topology.kubernetes.io/region=us-west1` |
| `ap-southeast1` | GKE Singapore | PDPA | `topology.kubernetes.io/region=ap-southeast1` |

**Region assignment:** At account creation, user's IP geolocation determines region. EU users are assigned `eu-west1`.

**Cross-border protection:** RegionRoutingMiddleware issues HTTP 307 if a user's request lands in the wrong region. PostgreSQL node affinity prevents EU data from persisting to non-EU storage.

**Storage encryption:** Each region uses Cloud KMS CMEK with region-specific keys.

---

## 8. Encryption Compliance

| Layer | Standard | Key Management |
|---|---|---|
| At rest | AES-256-GCM | Cloud KMS CMEK (90-day rotation) |
| In transit | TLS 1.3 | Let's Encrypt + SPIFFE |
| Service mesh | mTLS STRICT (Istio) | SPIRE auto-rotate |
| Database field | pgcrypto AES-256-GCM | KMS per-table DEKs |
| Backups | AES-256-GCM | KMS per-region |
| Redis | TLS 1.3 + AUTH | External Secrets Operator (30-day rotation) |
| Kafka | SASL/SCRAM-SHA-512 + TLS 1.3 | External Secrets Operator (90-day rotation) |

---

## 9. Compliance Monitoring

### Prometheus Alert Coverage
| Alert | Condition | Severity |
|---|---|---|
| `GDPRDataSubjectRequestDeadlineApproaching` | DSR < 72h to breach | Critical |
| `GDPRDataSubjectRequestDeadlineBreached` | DSR overdue | Critical |
| `GDPRRetentionJobFailed` | CronJob failed | Critical |
| `GDPRRetentionJobMissedSchedule` | No run in 26h | Critical |
| `GDPRConsentWithdrawalSpike` | > 100 withdrawals/hour | Warning |
| `GDPRProcessingWithoutConsent` | Any processing without consent | Critical |
| `TLSCertificateExpiryCritical` | Cert < 7 days | Critical |
| `KMSKeyRotationOverdue` | Key > 95 days old | Critical |
| `AuditLogTamperingDetected` | Integrity hash mismatch | Critical |
| `GDPRCrossRegionDataAccessDetected` | EU data outside EU | Critical |

---

## 10. Files Index

| File | Purpose |
|---|---|
| [001_gdpr_compliance_schema.sql](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/Easy%20Chat/infrastructure/database/migrations/001_gdpr_compliance_schema.sql) | PostgreSQL GDPR schema |
| [compliance.go](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/Easy%20Chat/apps/backend/services/compliance/compliance.go) | Core GDPR service |
| [handler.go](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/Easy%20Chat/apps/backend/services/compliance/handler.go) | Privacy API handlers |
| [middleware.go](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/Easy%20Chat/apps/backend/services/compliance/middleware.go) | PII masking + consent gate + region routing |
| [compliance_test.go](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/Easy%20Chat/apps/backend/services/compliance/compliance_test.go) | Unit tests |
| [compliance-manifests.yaml](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/Easy%20Chat/infrastructure/kubernetes/compliance/compliance-manifests.yaml) | Kubernetes resources |
| [data-residency.yaml](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/Easy%20Chat/infrastructure/kubernetes/compliance/data-residency.yaml) | Regional affinity + storage |
| [encryption-compliance.yaml](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/Easy%20Chat/infrastructure/kubernetes/compliance/encryption-compliance.yaml) | TLS/mTLS/CMEK config |
| [compliance-alerts.yml](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/Easy%20Chat/infrastructure/observability/prometheus/compliance-alerts.yml) | GDPR Prometheus alerts |
