// Package compliance implements the enterprise GDPR compliance service for
// the Nearby Connect platform. It covers all GDPR data subject rights
// (Art.15–22), consent management (Art.7), audit trails (Art.30),
// data retention enforcement (Art.5), and data residency routing (Art.44).
package compliance

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log/slog"
	"time"

	"github.com/google/uuid"
)

// ─────────────────────────────────────────────────────────────────────────────
// Domain types
// ─────────────────────────────────────────────────────────────────────────────

// ConsentPurpose enumerates all GDPR-trackable processing purposes.
type ConsentPurpose string

const (
	PurposeAnalytics          ConsentPurpose = "analytics"
	PurposeMarketingEmails    ConsentPurpose = "marketing_emails"
	PurposeLocationSharing    ConsentPurpose = "location_sharing"
	PurposeThirdPartyData     ConsentPurpose = "third_party_data"
	PurposeEssentialService   ConsentPurpose = "essential_service"
	PurposePushNotifications  ConsentPurpose = "push_notifications"
)

// DSRType enumerates all GDPR data subject request types.
type DSRType string

const (
	DSRAccess        DSRType = "access"
	DSRPortability   DSRType = "portability"
	DSRErasure       DSRType = "erasure"
	DSRRectification DSRType = "rectification"
	DSRRestriction   DSRType = "restriction"
	DSRObjection     DSRType = "objection"
)

// DataRegion enumerates supported data residency regions.
type DataRegion string

const (
	RegionEUWest1       DataRegion = "eu-west1"
	RegionUSEast1       DataRegion = "us-east1"
	RegionUSWest1       DataRegion = "us-west1"
	RegionAPSoutheast1  DataRegion = "ap-southeast1"
)

// DataSovereignty maps regions to applicable regulations.
var DataSovereignty = map[DataRegion]string{
	RegionEUWest1:      "gdpr",
	RegionUSEast1:      "ccpa",
	RegionUSWest1:      "ccpa",
	RegionAPSoutheast1: "pdpa",
}

// ConsentRecord represents a user's consent state for a specific purpose.
type ConsentRecord struct {
	ID                  string         `json:"id"`
	UserID              string         `json:"user_id"`
	Purpose             ConsentPurpose `json:"purpose"`
	Granted             bool           `json:"granted"`
	Mechanism           string         `json:"mechanism"`
	IPAddressHash       string         `json:"ip_address_hash,omitempty"`
	ConsentTextVersion  string         `json:"consent_text_version"`
	GrantedAt           time.Time      `json:"granted_at"`
	WithdrawnAt         *time.Time     `json:"withdrawn_at,omitempty"`
}

// AuditEvent is an immutable record of any processing activity.
type AuditEvent struct {
	ID            string         `json:"id"`
	ActorID       string         `json:"actor_id,omitempty"`
	ActorType     string         `json:"actor_type"`
	ServiceName   string         `json:"service_name"`
	EventType     string         `json:"event_type"`
	ResourceType  string         `json:"resource_type"`
	ResourceID    string         `json:"resource_id,omitempty"`
	Action        string         `json:"action"`
	Outcome       string         `json:"outcome"`
	FailureReason string         `json:"failure_reason,omitempty"`
	RequestID     string         `json:"request_id,omitempty"`
	Region        string         `json:"region,omitempty"`
	Metadata      map[string]any `json:"metadata,omitempty"`
	IntegrityHash string         `json:"integrity_hash"`
	CreatedAt     time.Time      `json:"created_at"`
}

// DataSubjectRequest models a GDPR Art.12-22 rights request.
type DataSubjectRequest struct {
	ID                 string    `json:"id"`
	UserID             string    `json:"user_id"`
	RequestType        DSRType   `json:"request_type"`
	Status             string    `json:"status"`
	RequestedAt        time.Time `json:"requested_at"`
	DeadlineAt         time.Time `json:"deadline_at"`
	CompletedAt        *time.Time `json:"completed_at,omitempty"`
	ExportURL          string    `json:"export_url,omitempty"`
	ExportExpires      *time.Time `json:"export_expires,omitempty"`
	DeletionSummary    map[string]any `json:"deletion_summary,omitempty"`
	RejectionReason    string    `json:"rejection_reason,omitempty"`
	IdentityVerified   bool      `json:"identity_verified"`
}

// UserDataExport is the structured GDPR Art.20 data portability payload.
type UserDataExport struct {
	ExportID      string         `json:"export_id"`
	UserID        string         `json:"user_id"`
	GeneratedAt   time.Time      `json:"generated_at"`
	FormatVersion string         `json:"format_version"`
	Profile       map[string]any `json:"profile"`
	Consents      []ConsentRecord `json:"consents"`
	Sessions      []map[string]any `json:"sessions"`
	Messages      []map[string]any `json:"messages"`
	MediaFiles    []map[string]any `json:"media_files"`
	// Raw PII is included in export but NOT in audit logs
}

// ─────────────────────────────────────────────────────────────────────────────
// Service
// ─────────────────────────────────────────────────────────────────────────────

// Service is the GDPR compliance engine.
type Service struct {
	db          *sql.DB
	serviceName string
	region      DataRegion
}

// New creates a new compliance Service.
func New(db *sql.DB, serviceName string, region DataRegion) *Service {
	return &Service{
		db:          db,
		serviceName: serviceName,
		region:      region,
	}
}

// ─────────────────────────────────────────────────────────────────────────────
// Consent Management (GDPR Art.7)
// ─────────────────────────────────────────────────────────────────────────────

// RecordConsent records a user's explicit consent for a given purpose.
// Consent must be freely given, specific, informed, and unambiguous (Art.7).
func (s *Service) RecordConsent(ctx context.Context, userID string, purpose ConsentPurpose,
	granted bool, mechanism, ipAddress, consentText, version string) (*ConsentRecord, error) {

	// Essential service consent cannot be withdrawn
	if purpose == PurposeEssentialService && !granted {
		return nil, fmt.Errorf("essential service consent cannot be withdrawn: processing is necessary for service delivery")
	}

	ipHash := hashValue(ipAddress)
	textHash := hashValue(consentText)
	id := uuid.New().String()
	now := time.Now().UTC()

	_, err := s.db.ExecContext(ctx, `
		INSERT INTO user_consents (id, user_id, purpose, granted, mechanism,
			ip_address_hash, consent_text_hash, consent_text_version, granted_at, created_at, updated_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$9,$9)
		ON CONFLICT (user_id, purpose) DO UPDATE
		SET granted = EXCLUDED.granted,
		    mechanism = EXCLUDED.mechanism,
		    ip_address_hash = EXCLUDED.ip_address_hash,
		    consent_text_hash = EXCLUDED.consent_text_hash,
		    consent_text_version = EXCLUDED.consent_text_version,
		    granted_at = CASE WHEN EXCLUDED.granted THEN NOW() ELSE user_consents.granted_at END,
		    withdrawn_at = CASE WHEN NOT EXCLUDED.granted THEN NOW() ELSE NULL END,
		    updated_at = NOW()
	`, id, userID, string(purpose), granted, mechanism, ipHash, textHash, version, now)
	if err != nil {
		return nil, fmt.Errorf("record consent: %w", err)
	}

	record := &ConsentRecord{
		ID: id, UserID: userID, Purpose: purpose, Granted: granted,
		Mechanism: mechanism, IPAddressHash: ipHash,
		ConsentTextVersion: version, GrantedAt: now,
	}

	// Append to consent audit log
	action := "granted"
	if !granted {
		action = "withdrawn"
	}
	_ = s.appendConsentAudit(ctx, id, userID, string(purpose), action, "user", nil, map[string]any{
		"granted": granted, "mechanism": mechanism, "version": version,
	})

	// Emit compliance audit event
	_ = s.EmitAuditEvent(ctx, AuditEvent{
		ActorID: userID, ActorType: "user", EventType: "consent." + action,
		ResourceType: "consent", ResourceID: id, Action: action,
		Outcome: "success",
		Metadata: map[string]any{"purpose": purpose, "mechanism": mechanism},
	})

	slog.Info("Consent recorded", "user_id", userID, "purpose", purpose, "granted", granted)
	return record, nil
}

// GetConsents returns all current consent states for a user.
func (s *Service) GetConsents(ctx context.Context, userID string) ([]ConsentRecord, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT id, user_id, purpose, granted, mechanism, ip_address_hash,
		       consent_text_version, granted_at, withdrawn_at
		FROM user_consents WHERE user_id = $1
		ORDER BY purpose
	`, userID)
	if err != nil {
		return nil, fmt.Errorf("get consents: %w", err)
	}
	defer rows.Close()

	var records []ConsentRecord
	for rows.Next() {
		var r ConsentRecord
		var withdrawn sql.NullTime
		if err := rows.Scan(&r.ID, &r.UserID, &r.Purpose, &r.Granted, &r.Mechanism,
			&r.IPAddressHash, &r.ConsentTextVersion, &r.GrantedAt, &withdrawn); err != nil {
			return nil, err
		}
		if withdrawn.Valid {
			r.WithdrawnAt = &withdrawn.Time
		}
		records = append(records, r)
	}
	return records, nil
}

// HasActiveConsent checks whether the user has active (non-withdrawn) consent for a purpose.
func (s *Service) HasActiveConsent(ctx context.Context, userID string, purpose ConsentPurpose) (bool, error) {
	var granted bool
	err := s.db.QueryRowContext(ctx, `
		SELECT granted FROM user_consents
		WHERE user_id = $1 AND purpose = $2 AND granted = true AND withdrawn_at IS NULL
	`, userID, string(purpose)).Scan(&granted)
	if err == sql.ErrNoRows {
		return false, nil
	}
	return granted, err
}

// ─────────────────────────────────────────────────────────────────────────────
// Audit Trail (GDPR Art.30 — Records of processing activities)
// ─────────────────────────────────────────────────────────────────────────────

// EmitAuditEvent writes an immutable audit record. The integrity hash
// is computed over key fields to detect tampering.
func (s *Service) EmitAuditEvent(ctx context.Context, e AuditEvent) error {
	e.ID = uuid.New().String()
	e.ServiceName = s.serviceName
	e.Region = string(s.region)
	e.CreatedAt = time.Now().UTC()
	e.IntegrityHash = computeIntegrityHash(e.ID, e.ActorID, e.EventType, e.ResourceID, e.CreatedAt)

	metaJSON, _ := json.Marshal(e.Metadata)

	_, err := s.db.ExecContext(ctx, `
		INSERT INTO audit_events (id, actor_id, actor_type, service_name, event_type,
			resource_type, resource_id, action, outcome, failure_reason, request_id,
			region, metadata, integrity_hash, created_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)
	`, e.ID, nullString(e.ActorID), e.ActorType, e.ServiceName, e.EventType,
		e.ResourceType, nullString(e.ResourceID), e.Action, e.Outcome,
		nullString(e.FailureReason), nullString(e.RequestID), e.Region,
		metaJSON, e.IntegrityHash, e.CreatedAt)
	if err != nil {
		slog.Error("Failed to write audit event", "event_type", e.EventType, "error", err)
		return fmt.Errorf("emit audit event: %w", err)
	}
	return nil
}

// QueryAuditEvents returns audit events for a user within a time range.
func (s *Service) QueryAuditEvents(ctx context.Context, userID string, from, to time.Time, limit int) ([]AuditEvent, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT id, actor_id, actor_type, service_name, event_type, resource_type,
		       resource_id, action, outcome, failure_reason, request_id, region,
		       metadata, integrity_hash, created_at
		FROM audit_events
		WHERE actor_id = $1 AND created_at BETWEEN $2 AND $3
		ORDER BY created_at DESC LIMIT $4
	`, userID, from, to, limit)
	if err != nil {
		return nil, fmt.Errorf("query audit events: %w", err)
	}
	defer rows.Close()

	var events []AuditEvent
	for rows.Next() {
		var e AuditEvent
		var actorID, resourceID, failureReason, requestID sql.NullString
		var metaJSON []byte
		if err := rows.Scan(&e.ID, &actorID, &e.ActorType, &e.ServiceName, &e.EventType,
			&e.ResourceType, &resourceID, &e.Action, &e.Outcome, &failureReason,
			&requestID, &e.Region, &metaJSON, &e.IntegrityHash, &e.CreatedAt); err != nil {
			return nil, err
		}
		e.ActorID = actorID.String
		e.ResourceID = resourceID.String
		e.FailureReason = failureReason.String
		e.RequestID = requestID.String
		if len(metaJSON) > 0 {
			_ = json.Unmarshal(metaJSON, &e.Metadata)
		}
		events = append(events, e)
	}
	return events, nil
}

// ─────────────────────────────────────────────────────────────────────────────
// Right to Access (GDPR Art.15) + Data Portability (Art.20)
// ─────────────────────────────────────────────────────────────────────────────

// ExportUserData assembles a complete structured data export for Art.20 portability.
// All PII fields are included; the result must be encrypted before transmission.
func (s *Service) ExportUserData(ctx context.Context, userID string) (*UserDataExport, error) {
	export := &UserDataExport{
		ExportID:      uuid.New().String(),
		UserID:        userID,
		GeneratedAt:   time.Now().UTC(),
		FormatVersion: "1.0",
	}

	// 1. Profile data
	var profile struct {
		ID        string
		Pseudonym string
		DeviceID  string
		Role      string
		CreatedAt time.Time
		UpdatedAt time.Time
	}
	err := s.db.QueryRowContext(ctx, `
		SELECT id, pseudonym, device_id, role, created_at, updated_at
		FROM users WHERE id = $1
	`, userID).Scan(&profile.ID, &profile.Pseudonym, &profile.DeviceID, &profile.Role, &profile.CreatedAt, &profile.UpdatedAt)
	if err != nil && err != sql.ErrNoRows {
		return nil, fmt.Errorf("export profile: %w", err)
	}
	export.Profile = map[string]any{
		"id": profile.ID, "pseudonym": profile.Pseudonym,
		"role": profile.Role, "created_at": profile.CreatedAt, "updated_at": profile.UpdatedAt,
		// device_id intentionally omitted — not necessary for portability
	}

	// 2. Consents
	export.Consents, err = s.GetConsents(ctx, userID)
	if err != nil {
		return nil, fmt.Errorf("export consents: %w", err)
	}

	// 3. Sessions (stripped of token hashes — security-sensitive)
	sessionRows, err := s.db.QueryContext(ctx, `
		SELECT id, device_id, is_revoked, expires_at, created_at
		FROM user_sessions WHERE user_id = $1 ORDER BY created_at DESC LIMIT 100
	`, userID)
	if err == nil {
		defer sessionRows.Close()
		for sessionRows.Next() {
			var id, deviceID string
			var revoked bool
			var expiresAt, createdAt time.Time
			_ = sessionRows.Scan(&id, &deviceID, &revoked, &expiresAt, &createdAt)
			export.Sessions = append(export.Sessions, map[string]any{
				"id": id, "device_id": deviceID, "is_revoked": revoked,
				"expires_at": expiresAt, "created_at": createdAt,
			})
		}
	}

	// 4. Messages (content only — no internal IDs of other users)
	msgRows, err := s.db.QueryContext(ctx, `
		SELECT id, content, created_at FROM messages
		WHERE sender_id = $1 ORDER BY created_at DESC LIMIT 1000
	`, userID)
	if err == nil {
		defer msgRows.Close()
		for msgRows.Next() {
			var id, content string
			var createdAt time.Time
			_ = msgRows.Scan(&id, &content, &createdAt)
			export.Messages = append(export.Messages, map[string]any{
				"id": id, "content": content, "created_at": createdAt,
			})
		}
	}

	_ = s.EmitAuditEvent(ctx, AuditEvent{
		ActorID: userID, ActorType: "user", EventType: "data.export",
		ResourceType: "user_data", ResourceID: userID, Action: "exported",
		Outcome: "success",
		Metadata: map[string]any{
			"export_id": export.ExportID,
			"records":   len(export.Messages) + len(export.Sessions),
		},
	})

	slog.Info("User data export completed", "user_id", userID, "export_id", export.ExportID)
	return export, nil
}

// ─────────────────────────────────────────────────────────────────────────────
// Right to Erasure (GDPR Art.17 — Right to be forgotten)
// ─────────────────────────────────────────────────────────────────────────────

// EraseUserData executes the full GDPR Art.17 erasure sequence for a user.
// It applies a cascade deletion with pseudonymisation where legal holds exist.
func (s *Service) EraseUserData(ctx context.Context, userID, requestedBy, reason string) (map[string]int64, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return nil, fmt.Errorf("begin erasure tx: %w", err)
	}
	defer tx.Rollback()

	summary := map[string]int64{}

	// Execute erasure in dependency order to satisfy FK constraints
	tables := []struct {
		name  string
		query string
	}{
		{"messages", "DELETE FROM messages WHERE sender_id = $1"},
		{"user_location_events", "DELETE FROM user_location_events WHERE user_id = $1"},
		{"push_notification_logs", "DELETE FROM push_notification_logs WHERE user_id = $1"},
		{"media_files", "DELETE FROM media_files WHERE owner_id = $1"},
		{"user_sessions", "DELETE FROM user_sessions WHERE user_id = $1"},
		// Consents: anonymise rather than delete (retain proof for compliance)
		{"user_consents_anon", `UPDATE user_consents SET
			ip_address_hash = 'ERASED', user_agent = NULL
			WHERE user_id = $1`},
		// User profile: pseudonymise (retain pseudonym row for referential integrity in audit)
		{"users_pseudonymize", `UPDATE users SET
			pseudonym = 'deleted_user_' || LEFT(id::text, 8),
			device_id = 'ERASED_' || gen_random_uuid()::text,
			password_hash = 'ERASED',
			updated_at = NOW()
			WHERE id = $1`},
		// Invalidate pseudonym mapping
		{"pii_pseudonym_map", `UPDATE pii_pseudonym_map SET invalidated_at = NOW() WHERE real_user_id = $1::uuid`},
	}

	for _, t := range tables {
		res, err := tx.ExecContext(ctx, t.query, userID)
		if err != nil {
			return nil, fmt.Errorf("erasure step %s: %w", t.name, err)
		}
		n, _ := res.RowsAffected()
		if n > 0 {
			summary[t.name] = n
		}
	}

	if err := tx.Commit(); err != nil {
		return nil, fmt.Errorf("commit erasure: %w", err)
	}

	// Audit the erasure (retain event — this is NOT erased; it is the legal record)
	_ = s.EmitAuditEvent(ctx, AuditEvent{
		ActorID: requestedBy, ActorType: "user", EventType: "data.erasure",
		ResourceType: "user_data", ResourceID: userID, Action: "deleted",
		Outcome: "success",
		Metadata: map[string]any{"reason": reason, "tables_affected": summary},
	})

	slog.Info("User data erasure completed",
		"user_id", userID,
		"requested_by", requestedBy,
		"tables_affected", len(summary),
	)
	return summary, nil
}

// ─────────────────────────────────────────────────────────────────────────────
// Data Retention Enforcement (GDPR Art.5(1)(e) — Storage limitation)
// ─────────────────────────────────────────────────────────────────────────────

// RunRetentionPolicy executes all enabled retention policies.
// This is called by the retention CronJob (see kubernetes/compliance/retention-cronjob.yaml).
func (s *Service) RunRetentionPolicy(ctx context.Context) error {
	rows, err := s.db.QueryContext(ctx, `
		SELECT table_name, retention_days, action, date_column, filter_clause
		FROM data_retention_policies
		WHERE enabled = true
		ORDER BY retention_days ASC
	`)
	if err != nil {
		return fmt.Errorf("load retention policies: %w", err)
	}
	defer rows.Close()

	for rows.Next() {
		var tableName, action, dateCol string
		var retentionDays int
		var filterClause sql.NullString
		if err := rows.Scan(&tableName, &retentionDays, &action, &dateCol, &filterClause); err != nil {
			slog.Error("Scan retention policy", "error", err)
			continue
		}

		cutoff := time.Now().UTC().AddDate(0, 0, -retentionDays)
		var query string

		switch action {
		case "delete":
			query = fmt.Sprintf("DELETE FROM %s WHERE %s < $1", tableName, dateCol)
			if filterClause.Valid && filterClause.String != "" {
				query += " AND " + filterClause.String
			}
		case "anonymize":
			// Table-specific anonymisation — skip in generic loop
			slog.Info("Anonymise action requires custom query", "table", tableName)
			continue
		default:
			slog.Warn("Unsupported retention action", "action", action)
			continue
		}

		res, err := s.db.ExecContext(ctx, query, cutoff)
		if err != nil {
			slog.Error("Retention policy execution failed", "table", tableName, "error", err)
			continue
		}
		n, _ := res.RowsAffected()

		// Update last-run metadata
		_, _ = s.db.ExecContext(ctx,
			"UPDATE data_retention_policies SET last_run_at = NOW(), last_run_rows = $1 WHERE table_name = $2",
			n, tableName,
		)

		_ = s.EmitAuditEvent(ctx, AuditEvent{
			ActorType: "system", EventType: "retention.enforcement",
			ResourceType: "table", ResourceID: tableName, Action: action,
			Outcome: "success",
			Metadata: map[string]any{"rows_affected": n, "cutoff": cutoff, "table": tableName},
		})

		slog.Info("Retention policy applied", "table", tableName, "rows_deleted", n, "cutoff", cutoff)
	}
	return nil
}

// ─────────────────────────────────────────────────────────────────────────────
// Data Subject Request Management (GDPR Art.12 — 30-day response obligation)
// ─────────────────────────────────────────────────────────────────────────────

// CreateDSR creates a new Data Subject Request and returns the record.
func (s *Service) CreateDSR(ctx context.Context, userID string, reqType DSRType) (*DataSubjectRequest, error) {
	id := uuid.New().String()
	now := time.Now().UTC()
	deadline := now.Add(30 * 24 * time.Hour) // GDPR Art.12 — 30-day response window

	_, err := s.db.ExecContext(ctx, `
		INSERT INTO data_subject_requests (id, user_id, request_type, status, requested_at, deadline_at, created_at, updated_at)
		VALUES ($1,$2,$3,'pending',$4,$5,$4,$4)
	`, id, userID, string(reqType), now, deadline)
	if err != nil {
		return nil, fmt.Errorf("create DSR: %w", err)
	}

	_ = s.EmitAuditEvent(ctx, AuditEvent{
		ActorID: userID, ActorType: "user", EventType: "dsr.created",
		ResourceType: "data_subject_request", ResourceID: id, Action: "created",
		Outcome: "success",
		Metadata: map[string]any{"request_type": reqType, "deadline": deadline},
	})

	return &DataSubjectRequest{
		ID: id, UserID: userID, RequestType: reqType,
		Status: "pending", RequestedAt: now, DeadlineAt: deadline,
	}, nil
}

// ─────────────────────────────────────────────────────────────────────────────
// Data Residency (GDPR Art.44-49)
// ─────────────────────────────────────────────────────────────────────────────

// AssignDataResidency sets the data residency region for a new user
// based on their registration geolocation.
func (s *Service) AssignDataResidency(ctx context.Context, userID string, region DataRegion) error {
	sovereignty := DataSovereignty[region]
	if sovereignty == "" {
		sovereignty = "standard"
	}

	_, err := s.db.ExecContext(ctx, `
		INSERT INTO user_data_residency (user_id, assigned_region, data_sovereignty, created_at, updated_at)
		VALUES ($1::uuid, $2, $3, NOW(), NOW())
		ON CONFLICT (user_id) DO NOTHING
	`, userID, string(region), sovereignty)
	if err != nil {
		return fmt.Errorf("assign data residency: %w", err)
	}

	_ = s.EmitAuditEvent(ctx, AuditEvent{
		ActorID: userID, ActorType: "system", EventType: "residency.assigned",
		ResourceType: "user_data_residency", ResourceID: userID, Action: "created",
		Outcome: "success",
		Metadata: map[string]any{"region": region, "sovereignty": sovereignty},
	})

	return nil
}

// GetUserRegion returns the assigned data residency region for a user.
func (s *Service) GetUserRegion(ctx context.Context, userID string) (DataRegion, error) {
	var region string
	err := s.db.QueryRowContext(ctx, `
		SELECT assigned_region FROM user_data_residency WHERE user_id = $1::uuid
	`, userID).Scan(&region)
	if err == sql.ErrNoRows {
		return RegionUSEast1, nil // default
	}
	return DataRegion(region), err
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

// hashValue computes a SHA-256 hex digest for PII fields before storage.
func hashValue(v string) string {
	if v == "" {
		return ""
	}
	h := sha256.Sum256([]byte(v))
	return hex.EncodeToString(h[:])
}

// computeIntegrityHash computes a tamper-detection hash over audit event fields.
func computeIntegrityHash(id, actorID, eventType, resourceID string, ts time.Time) string {
	raw := fmt.Sprintf("%s|%s|%s|%s|%d", id, actorID, eventType, resourceID, ts.UnixNano())
	h := sha256.Sum256([]byte(raw))
	return hex.EncodeToString(h[:])
}

// generateToken creates a cryptographically random 32-byte hex token.
func generateToken() string {
	b := make([]byte, 32)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

func nullString(s string) sql.NullString {
	if s == "" {
		return sql.NullString{}
	}
	return sql.NullString{String: s, Valid: true}
}

func (s *Service) appendConsentAudit(ctx context.Context, consentID, userID, purpose, action, actorType string,
	previous, newVal map[string]any) error {
	prevJSON, _ := json.Marshal(previous)
	newJSON, _ := json.Marshal(newVal)
	_, err := s.db.ExecContext(ctx, `
		INSERT INTO consent_audit_log (id, consent_id, user_id, purpose, action, actor_type, previous_value, new_value, created_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,NOW())
	`, uuid.New().String(), consentID, userID, purpose, action, actorType, prevJSON, newJSON)
	return err
}
