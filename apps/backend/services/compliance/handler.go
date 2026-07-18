// Package compliance provides HTTP handlers for GDPR data subject rights
// exposed via the API gateway. All endpoints require authenticated JWT sessions.
// Rate limiting is enforced at the gateway level.
package compliance

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"time"
)

// Handler exposes GDPR compliance endpoints.
type Handler struct {
	svc *Service
}

// NewHandler creates a new compliance HTTP handler.
func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

// RegisterRoutes registers all GDPR compliance routes.
// Prefix: /api/v1/privacy
func (h *Handler) RegisterRoutes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/privacy/consents", h.GetConsents)
	mux.HandleFunc("POST /api/v1/privacy/consents", h.UpdateConsent)
	mux.HandleFunc("GET /api/v1/privacy/export", h.RequestDataExport)
	mux.HandleFunc("POST /api/v1/privacy/requests/erasure", h.RequestErasure)
	mux.HandleFunc("POST /api/v1/privacy/requests/access", h.RequestAccess)
	mux.HandleFunc("POST /api/v1/privacy/requests/portability", h.RequestPortability)
	mux.HandleFunc("GET /api/v1/privacy/requests", h.ListDSRs)
	mux.HandleFunc("GET /api/v1/privacy/audit", h.GetAuditTrail)
}

// ─────────────────────────────────────────────────────────────────────────────

// GetConsents returns all consent states for the authenticated user.
// GET /api/v1/privacy/consents
// GDPR Art.7(3) — User must be able to withdraw consent at any time.
func (h *Handler) GetConsents(w http.ResponseWriter, r *http.Request) {
	userID := extractUserID(r)
	if userID == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	consents, err := h.svc.GetConsents(r.Context(), userID)
	if err != nil {
		slog.Error("GetConsents failed", "user_id", userID, "error", err)
		writeError(w, http.StatusInternalServerError, "internal error")
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"user_id":  userID,
		"consents": consents,
	})
}

// UpdateConsent grants or withdraws consent for a specific purpose.
// POST /api/v1/privacy/consents
// Body: {"purpose": "analytics", "granted": true}
func (h *Handler) UpdateConsent(w http.ResponseWriter, r *http.Request) {
	userID := extractUserID(r)
	if userID == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	var req struct {
		Purpose ConsentPurpose `json:"purpose"`
		Granted bool           `json:"granted"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	ipAddress := r.Header.Get("X-Forwarded-For")
	if ipAddress == "" {
		ipAddress = r.RemoteAddr
	}

	record, err := h.svc.RecordConsent(r.Context(), userID, req.Purpose, req.Granted,
		"in_app_prompt", ipAddress, consentTextForPurpose(req.Purpose), "v1.0")
	if err != nil {
		slog.Error("UpdateConsent failed", "user_id", userID, "purpose", req.Purpose, "error", err)
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}

	action := "granted"
	if !req.Granted {
		action = "withdrawn"
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"status":  "success",
		"action":  action,
		"purpose": req.Purpose,
		"record":  record,
	})
}

// RequestDataExport triggers an Art.20 data portability export.
// GET /api/v1/privacy/export
// Returns structured JSON with all user data (encrypted at transport layer).
func (h *Handler) RequestDataExport(w http.ResponseWriter, r *http.Request) {
	userID := extractUserID(r)
	if userID == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	export, err := h.svc.ExportUserData(r.Context(), userID)
	if err != nil {
		slog.Error("DataExport failed", "user_id", userID, "error", err)
		writeError(w, http.StatusInternalServerError, "export failed")
		return
	}

	// Set content-disposition for download
	w.Header().Set("Content-Disposition", "attachment; filename=\"my_data_export.json\"")
	w.Header().Set("Content-Type", "application/json")
	writeJSON(w, http.StatusOK, export)
}

// RequestErasure submits a GDPR Art.17 right-to-be-forgotten request.
// POST /api/v1/privacy/requests/erasure
func (h *Handler) RequestErasure(w http.ResponseWriter, r *http.Request) {
	userID := extractUserID(r)
	if userID == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	var req struct {
		Reason string `json:"reason"`
	}
	_ = json.NewDecoder(r.Body).Decode(&req)

	// Create DSR first (for tracking and deadline enforcement)
	dsr, err := h.svc.CreateDSR(r.Context(), userID, DSRErasure)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to create erasure request")
		return
	}

	// Execute erasure immediately (no holds in current model)
	summary, err := h.svc.EraseUserData(r.Context(), userID, userID, req.Reason)
	if err != nil {
		slog.Error("Erasure failed", "user_id", userID, "dsr_id", dsr.ID, "error", err)
		writeError(w, http.StatusInternalServerError, "erasure failed")
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"status":           "completed",
		"dsr_id":           dsr.ID,
		"deletion_summary": summary,
		"completed_at":     time.Now().UTC(),
		"message":          "Your data has been erased. Audit logs are retained for 7 years as required by law.",
	})
}

// RequestAccess submits a GDPR Art.15 right-of-access request.
// POST /api/v1/privacy/requests/access
func (h *Handler) RequestAccess(w http.ResponseWriter, r *http.Request) {
	userID := extractUserID(r)
	if userID == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}
	dsr, err := h.svc.CreateDSR(r.Context(), userID, DSRAccess)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to create access request")
		return
	}
	writeJSON(w, http.StatusAccepted, map[string]any{
		"status":     "pending",
		"dsr_id":     dsr.ID,
		"deadline":   dsr.DeadlineAt,
		"message":    "Your access request has been received. We will respond within 30 days as required by GDPR Art.12.",
	})
}

// RequestPortability submits a GDPR Art.20 data portability request.
// POST /api/v1/privacy/requests/portability
func (h *Handler) RequestPortability(w http.ResponseWriter, r *http.Request) {
	userID := extractUserID(r)
	if userID == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}
	dsr, err := h.svc.CreateDSR(r.Context(), userID, DSRPortability)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to create portability request")
		return
	}

	// Immediately generate the export for portability (Art.20 expects machine-readable format)
	export, err := h.svc.ExportUserData(r.Context(), userID)
	if err != nil {
		slog.Error("Portability export failed", "user_id", userID, "dsr_id", dsr.ID, "error", err)
		writeError(w, http.StatusInternalServerError, "export generation failed")
		return
	}

	w.Header().Set("Content-Disposition", "attachment; filename=\"data_portability_export.json\"")
	writeJSON(w, http.StatusOK, export)
}

// ListDSRs returns all data subject requests for the authenticated user.
// GET /api/v1/privacy/requests
func (h *Handler) ListDSRs(w http.ResponseWriter, r *http.Request) {
	userID := extractUserID(r)
	if userID == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	rows, err := h.svc.db.QueryContext(r.Context(), `
		SELECT id, request_type, status, requested_at, deadline_at, completed_at, rejection_reason
		FROM data_subject_requests WHERE user_id = $1
		ORDER BY requested_at DESC LIMIT 50
	`, userID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "failed to list requests")
		return
	}
	defer rows.Close()

	var requests []map[string]any
	for rows.Next() {
		var id, reqType, status string
		var requestedAt, deadlineAt time.Time
		var completedAt, rejectionReason any
		_ = rows.Scan(&id, &reqType, &status, &requestedAt, &deadlineAt, &completedAt, &rejectionReason)
		requests = append(requests, map[string]any{
			"id": id, "type": reqType, "status": status,
			"requested_at": requestedAt, "deadline_at": deadlineAt,
			"completed_at": completedAt, "rejection_reason": rejectionReason,
		})
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"user_id":  userID,
		"requests": requests,
	})
}

// GetAuditTrail returns the user's own processing audit trail (Art.15 transparency).
// GET /api/v1/privacy/audit?from=2024-01-01&to=2024-12-31
func (h *Handler) GetAuditTrail(w http.ResponseWriter, r *http.Request) {
	userID := extractUserID(r)
	if userID == "" {
		writeError(w, http.StatusUnauthorized, "authentication required")
		return
	}

	from := time.Now().AddDate(0, -3, 0) // default: last 3 months
	to := time.Now()

	if f := r.URL.Query().Get("from"); f != "" {
		if t, err := time.Parse("2006-01-02", f); err == nil {
			from = t
		}
	}
	if t := r.URL.Query().Get("to"); t != "" {
		if parsed, err := time.Parse("2006-01-02", t); err == nil {
			to = parsed
		}
	}

	events, err := h.svc.QueryAuditEvents(r.Context(), userID, from, to, 200)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "audit query failed")
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"user_id": userID,
		"from":    from,
		"to":      to,
		"events":  events,
		"count":   len(events),
	})
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

// extractUserID pulls the authenticated user ID from JWT claims set by the gateway.
func extractUserID(r *http.Request) string {
	// The API gateway validates JWT and injects X-User-ID header
	return r.Header.Get("X-User-ID")
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}

// consentTextForPurpose returns the canonical consent text for a given purpose
// (hashed for the consent record proof).
func consentTextForPurpose(p ConsentPurpose) string {
	texts := map[ConsentPurpose]string{
		PurposeAnalytics:         "I consent to the collection and analysis of my usage data to improve the service.",
		PurposeMarketingEmails:   "I consent to receiving marketing communications by email.",
		PurposeLocationSharing:   "I consent to the processing of my location data for nearby discovery features.",
		PurposeThirdPartyData:    "I consent to sharing my data with third-party service providers.",
		PurposeEssentialService:  "Processing of essential data is required for service operation.",
		PurposePushNotifications: "I consent to receiving push notifications from the service.",
	}
	if t, ok := texts[p]; ok {
		return t
	}
	return string(p)
}
