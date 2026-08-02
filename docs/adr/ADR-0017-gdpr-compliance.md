# ADR 0017: Enterprise GDPR & Privacy Compliance Engine

**ADR Number:** ADR-0017  
**Title:** Enterprise GDPR & Privacy Compliance Engine  
**Status:** Accepted  
**Date:** July 21, 2026  

---

## 1. Context
The platform processes user PII (names, emails, chat archives, proximity logs, IP addresses) subject to European Union General Data Protection Regulation (GDPR) and global privacy regulations.

## 2. Problem Statement
Ad-hoc or manual data subject request (DSR) fulfillment risks missing regulatory compliance deadlines (30-day mandate), incomplete data deletion across distributed databases, lack of auditability, and severe financial penalties (up to 4% of global annual turnover).

## 3. Decision
Implement a centralized, microservice-decoupled GDPR Compliance Engine (`apps/backend/services/compliance/compliance.go`). The compliance engine enforces:
* **Art. 7 (Consent Management):** Dynamic consent recording, retrieval, and status verification (`RecordConsent`, `GetConsents`, `HasActiveConsent` [`compliance.go:155-253`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/compliance/compliance.go#L155-L253)).
* **Art. 30 (Audit Records & Hash Integrity):** Immutable audit event trail signed with SHA-256 integrity hashes (`EmitAuditEvent`, `computeIntegrityHash` [`compliance.go:261-284`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/compliance/compliance.go#L261-L284)).
* **Art. 15 / Art. 20 (Data Export & Portability):** Structured JSON exports of user profile, chats, and consents (`ExportUserData` [`compliance.go:329-413`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/compliance/compliance.go#L329-L413)).
* **Art. 17 (Right to Erasure):** Automated cascade deletion and PII pseudonymisation across relational tables (`EraseUserData` [`compliance.go:420-484`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/compliance/compliance.go#L420-L484)).
* **Art. 5 (Storage Limitation & Data Retention):** Automated purge of stale records exceeding configured threshold (`RunRetentionPolicy` [`compliance.go:492-554`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/compliance/compliance.go#L492-L554)).
* **Art. 12 (DSR Deadline Tracking):** 30-day compliance tracking for access, erasure, and portability requests (`CreateDSR` [`compliance.go:561-585`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/compliance/compliance.go#L561-L585)).

## 4. Evidence
* **Compliance Service Logic:** [`apps/backend/services/compliance/compliance.go:1-674`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/apps/backend/services/compliance/compliance.go#L1-L674)
* **Compliance Database Migration Schema:** [`infrastructure/database/migrations/001_gdpr_compliance_schema.sql:1-120`](file:///c:/Users/kanchiDhyana%20sai/OneDrive/Desktop/lucky/infrastructure/database/migrations/001_gdpr_compliance_schema.sql#L1-L120)

## 5. Alternatives Considered
* **Manual SRE Data Deletion Scripts:** Rejected due to human error risks, lack of SHA-256 audit hash verification, and potential missed data tables.

## 6. Tradeoffs
* Cascade deletion execution locks affected database rows during erasure processing.

## 7. Consequences
* Guaranteed regulatory compliance with automated DSR fulfillment and auditability.
* Tamper-evident proof of compliance via SHA-256 hash chains.

## 8. Risks
* High-volume audit log inserts requiring database partition maintenance.

## 9. Future Considerations
* Implement automatic encryption at rest for exported compliance JSON archives.
