package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"time"

	"github.com/redis/go-redis/v9"

	"nearby/backend/services/presence/internal/application"
	"nearby/backend/services/presence/internal/domain"
	"nearby/backend/services/presence/internal/infrastructure/cache"
	sharedconfig "nearby/backend/shared/config"
	"nearby/backend/shared/logger"
	"nearby/backend/shared/tracing"
)

func main() {
	log := logger.NewJSONLogger()
	slog.SetDefault(log)

	cfg := sharedconfig.LoadBaseConfig()

	// Port configuration: presence service defaults to 8085
	port := cfg.Port
	if port == 8080 {
		port = 8085
	}

	log.Info("Starting Presence Service...", "environment", cfg.Environment, "port", port)

	// Initialize OpenTelemetry tracing
	_, err := tracing.InitTracer("presence-service")
	if err != nil {
		log.Error("Failed to initialize OpenTelemetry tracing", "err", err)
	}

	// 1. Initialize Redis Connection
	var rdb *redis.Client
	redisURL := cfg.RedisURL
	if redisURL == "" {
		redisURL = "localhost:6379"
	}
	if opts, err := redis.ParseURL(redisURL); err == nil {
		opts.DialTimeout = 3 * time.Second
		opts.ReadTimeout = 2 * time.Second
		opts.WriteTimeout = 2 * time.Second
		rdb = redis.NewClient(opts)
	} else {
		rdb = redis.NewClient(&redis.Options{
			Addr:         redisURL,
			Password:     os.Getenv("REDIS_PASSWORD"),
			DialTimeout:  3 * time.Second,
			ReadTimeout:  2 * time.Second,
			WriteTimeout: 2 * time.Second,
		})
	}

	// Verify Redis connection
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := rdb.Ping(ctx).Err(); err != nil {
		log.Error("Failed to connect to Redis", "err", err)
		os.Exit(1)
	}
	log.Info("Successfully connected to Redis")

	// 2. Initialize Repositories, Use Cases, and Handlers
	presenceRepo := cache.NewRedisPresenceRepository(rdb)
	usecase := application.NewPresenceUsecase(presenceRepo)

	// 3. Register Routes
	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})

	http.HandleFunc("/api/v1/presence/heartbeat", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			w.WriteHeader(http.StatusMethodNotAllowed)
			return
		}

		type Request struct {
			UserID   string               `json:"user_id"`
			DeviceID string               `json:"device_id"`
			State    domain.PresenceState `json:"state"`
			H3Index  string               `json:"h3_index"`
		}

		var req Request
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusBadRequest)
			_, _ = w.Write([]byte(`{"error":"bad request"}`))
			return
		}

		err := usecase.Heartbeat(r.Context(), req.UserID, req.DeviceID, req.State, req.H3Index)
		if err != nil {
			log.Error("Failed to process presence heartbeat", "err", err)
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusInternalServerError)
			_, _ = w.Write([]byte(`{"error":"internal server error"}`))
			return
		}

		w.WriteHeader(http.StatusOK)
	})

	http.HandleFunc("/api/v1/presence/status", func(w http.ResponseWriter, r *http.Request) {
		userID := r.URL.Query().Get("user_id")
		if userID == "" {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusBadRequest)
			_, _ = w.Write([]byte(`{"error":"user_id query param is required"}`))
			return
		}

		devices, err := presenceRepo.GetDevicePresences(r.Context(), userID)
		if err != nil {
			log.Error("Failed to lookup device presences", "err", err, "user_id", userID)
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusInternalServerError)
			_, _ = w.Write([]byte(`{"error":"internal server error"}`))
			return
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_ = json.NewEncoder(w).Encode(devices)
	})

	serverAddr := fmt.Sprintf(":%d", port)
	log.Info("Presence HTTP API Server listening", "addr", serverAddr)
	if err := http.ListenAndServe(serverAddr, nil); err != nil {
		log.Error("Presence HTTP server crashed", "err", err)
		os.Exit(1)
	}
}
