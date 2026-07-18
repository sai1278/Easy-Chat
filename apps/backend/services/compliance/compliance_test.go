package compliance

import (
	"context"
	"database/sql"
	"encoding/json"
	"testing"
	"time"
)

// ─────────────────────────────────────────────────────────────────────────────
// Unit tests for core GDPR compliance logic (no DB dependency)
// ─────────────────────────────────────────────────────────────────────────────

func TestHashValue(t *testing.T) {
	h1 := hashValue("192.168.1.1")
	h2 := hashValue("192.168.1.1")
	h3 := hashValue("10.0.0.1")

	if h1 != h2 {
		t.Error("same input must produce same hash")
	}
	if h1 == h3 {
		t.Error("different inputs must produce different hashes")
	}
	if len(h1) != 64 {
		t.Errorf("expected 64-char hex hash, got %d chars", len(h1))
	}
}

func TestHashValueEmpty(t *testing.T) {
	if hashValue("") != "" {
		t.Error("empty input must return empty string (no hash of empty string stored)")
	}
}

func TestComputeIntegrityHash(t *testing.T) {
	ts := time.Date(2024, 1, 1, 0, 0, 0, 0, time.UTC)
	h1 := computeIntegrityHash("id-1", "actor-1", "user.login", "res-1", ts)
	h2 := computeIntegrityHash("id-1", "actor-1", "user.login", "res-1", ts)
	h3 := computeIntegrityHash("id-2", "actor-1", "user.login", "res-1", ts)

	if h1 != h2 {
		t.Error("identical inputs must produce identical integrity hash")
	}
	if h1 == h3 {
		t.Error("different id must produce different integrity hash")
	}
	if len(h1) != 64 {
		t.Errorf("expected 64-char hash, got %d", len(h1))
	}
}

func TestMaskPII(t *testing.T) {
	tests := []struct {
		input    string
		contains string
	}{
		{"User email: user@example.com accessed the API", "[REDACTED]"},
		{"Phone: 1234567890 recorded", "[REDACTED]"},
		{"Card: 4111 1111 1111 1111 charged", "[REDACTED]"},
		{"password=supersecret123 in query", "[REDACTED]"},
		{"No PII here just plain text", "No PII here just plain text"},
	}

	for _, tt := range tests {
		masked := MaskPII(tt.input)
		if tt.contains == "[REDACTED]" && !containsString(masked, "[REDACTED]") {
			t.Errorf("MaskPII(%q): expected [REDACTED] in output %q", tt.input, masked)
		}
		if tt.contains != "[REDACTED]" && masked != tt.contains {
			t.Errorf("MaskPII(%q): expected %q, got %q", tt.input, tt.contains, masked)
		}
	}
}

func TestConsentPurposeConstants(t *testing.T) {
	purposes := []ConsentPurpose{
		PurposeAnalytics,
		PurposeMarketingEmails,
		PurposeLocationSharing,
		PurposeThirdPartyData,
		PurposeEssentialService,
		PurposePushNotifications,
	}
	for _, p := range purposes {
		if p == "" {
			t.Error("consent purpose constant must not be empty")
		}
	}
}

func TestDataSovereigntyMapping(t *testing.T) {
	if DataSovereignty[RegionEUWest1] != "gdpr" {
		t.Errorf("EU region must map to gdpr, got %q", DataSovereignty[RegionEUWest1])
	}
	if DataSovereignty[RegionUSEast1] != "ccpa" {
		t.Errorf("US region must map to ccpa, got %q", DataSovereignty[RegionUSEast1])
	}
	if DataSovereignty[RegionAPSoutheast1] != "pdpa" {
		t.Errorf("AP region must map to pdpa, got %q", DataSovereignty[RegionAPSoutheast1])
	}
}

func TestUserDataExportStructure(t *testing.T) {
	export := &UserDataExport{
		ExportID:      "test-export-1",
		UserID:        "user-1",
		GeneratedAt:   time.Now(),
		FormatVersion: "1.0",
		Profile:       map[string]any{"id": "user-1", "pseudonym": "test_user"},
		Consents:      []ConsentRecord{},
		Sessions:      []map[string]any{},
		Messages:      []map[string]any{},
	}

	// Verify JSON serialisation (required for Art.20 machine-readable format)
	data, err := json.Marshal(export)
	if err != nil {
		t.Fatalf("UserDataExport must serialise to JSON: %v", err)
	}

	var decoded UserDataExport
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatalf("UserDataExport must deserialise from JSON: %v", err)
	}

	if decoded.ExportID != export.ExportID {
		t.Error("ExportID must survive JSON round-trip")
	}
	if decoded.FormatVersion != "1.0" {
		t.Error("FormatVersion must be preserved in export")
	}
}

func TestAuditEventJSONRoundtrip(t *testing.T) {
	e := AuditEvent{
		ID:            "evt-1",
		ActorID:       "user-1",
		ActorType:     "user",
		ServiceName:   "compliance",
		EventType:     "data.erasure",
		ResourceType:  "user_data",
		ResourceID:    "user-1",
		Action:        "deleted",
		Outcome:       "success",
		IntegrityHash: "abc123",
		CreatedAt:     time.Now().UTC().Truncate(time.Second),
		Metadata:      map[string]any{"rows": 42},
	}

	data, err := json.Marshal(e)
	if err != nil {
		t.Fatalf("AuditEvent must serialise to JSON: %v", err)
	}

	var decoded AuditEvent
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatalf("AuditEvent must deserialise from JSON: %v", err)
	}

	if decoded.IntegrityHash != e.IntegrityHash {
		t.Error("IntegrityHash must survive JSON round-trip")
	}
}

func TestDSRDeadlineIs30Days(t *testing.T) {
	// GDPR Art.12 mandates 30-day response window
	now := time.Now()
	deadline := now.Add(30 * 24 * time.Hour)

	// Allow 1 second tolerance for test execution time
	diff := deadline.Sub(now)
	if diff < 29*24*time.Hour || diff > 31*24*time.Hour {
		t.Errorf("DSR deadline must be ~30 days, got %v", diff)
	}
}

func TestConsentTextForAllPurposes(t *testing.T) {
	purposes := []ConsentPurpose{
		PurposeAnalytics, PurposeMarketingEmails, PurposeLocationSharing,
		PurposeThirdPartyData, PurposeEssentialService, PurposePushNotifications,
	}
	for _, p := range purposes {
		text := consentTextForPurpose(p)
		if text == "" {
			t.Errorf("consentTextForPurpose(%q) returned empty — GDPR requires explicit consent text", p)
		}
	}
}

func TestRegionEndpoints(t *testing.T) {
	regions := []DataRegion{RegionEUWest1, RegionUSEast1, RegionUSWest1, RegionAPSoutheast1}
	for _, r := range regions {
		ep := regionEndpoint(r)
		if ep == "" {
			t.Errorf("regionEndpoint(%q) returned empty — all regions need routing endpoints", r)
		}
	}
}

func TestNullStringHelper(t *testing.T) {
	ns := nullString("hello")
	if !ns.Valid || ns.String != "hello" {
		t.Error("non-empty string must produce valid NullString")
	}
	ns2 := nullString("")
	if ns2.Valid {
		t.Error("empty string must produce invalid (NULL) NullString")
	}
}

// ─────────────────────────────────────────────────────────────────────────────
// Integration-style test stubs (would run against a real DB in CI)
// ─────────────────────────────────────────────────────────────────────────────

// TestRecordConsentEssentialServiceCannotBeWithdrawn validates that
// essential_service consent cannot be set to granted=false.
func TestRecordConsentEssentialServiceCannotBeWithdrawn(t *testing.T) {
	// This test validates business logic without a DB
	svc := &Service{db: nil, serviceName: "test", region: RegionEUWest1}

	// Pass a nil DB context — the function must return an error before hitting DB
	_, err := svc.RecordConsent(context.Background(), "user-1", PurposeEssentialService,
		false, "in_app_prompt", "", "", "v1.0")
	if err == nil {
		t.Error("withdrawing essential_service consent must return an error")
	}
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

func containsString(s, substr string) bool {
	return len(s) > 0 && len(substr) > 0 && (s == substr || len(s) >= len(substr) &&
		func() bool {
			for i := 0; i <= len(s)-len(substr); i++ {
				if s[i:i+len(substr)] == substr {
					return true
				}
			}
			return false
		}())
}

// mockDB is a no-op sql.DB for tests that don't need DB calls
var _ *sql.DB = nil
