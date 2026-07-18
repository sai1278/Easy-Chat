package logger

import (
	"context"
	"log/slog"
	"os"
)

type contextKey string

const CorrelationIDKey contextKey = "correlation_id"

// ContextHandler intercepts logs to inject context-bound correlation IDs dynamically.
type ContextHandler struct {
	slog.Handler
}

func (h *ContextHandler) Handle(ctx context.Context, r slog.Record) error {
	if ctx != nil {
		if id, ok := ctx.Value(CorrelationIDKey).(string); ok {
			r.AddAttrs(slog.String("correlation_id", id))
		}
	}
	return h.Handler.Handle(ctx, r)
}

// NewJSONLogger initializes the structured Google-standard JSON log handoff.
func NewJSONLogger() *slog.Logger {
	baseHandler := slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{
		Level: slog.LevelInfo,
	})
	return slog.New(&ContextHandler{Handler: baseHandler})
}
