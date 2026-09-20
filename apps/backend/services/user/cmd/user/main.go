package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"time"

	_ "github.com/lib/pq"
	"github.com/redis/go-redis/v9"

	"nearby/backend/services/user/internal/infrastructure/events"
	"nearby/backend/services/user/internal/infrastructure/persistence"
	sharedconfig "nearby/backend/shared/config"
	"nearby/backend/shared/logger"
	"nearby/backend/shared/tracing"
)

func main() {
	log := logger.NewJSONLogger()
	slog.SetDefault(log)

	cfg := sharedconfig.LoadBaseConfig()

	// Port configuration: user service defaults to 8082
	port := cfg.Port
	if port == 8080 {
		port = 8082
	}

	log.Info("Starting User Service...", "environment", cfg.Environment, "port", port)

	// Initialize OpenTelemetry tracing
	_, err := tracing.InitTracer("user-service")
	if err != nil {
		log.Error("Failed to initialize OpenTelemetry tracing", "err", err)
	}

	// 1. Initialize PostgreSQL Connection
	dbURL := cfg.DatabaseURL
	if dbURL == "" {
		dbURL = "postgresql://nearby_user:nearby_secure_pass@localhost:5432/nearby_connect?sslmode=disable"
	}
	db, err := sql.Open("postgres", dbURL)
	if err != nil {
		log.Error("Failed to open Postgres connection", "err", err)
		os.Exit(1)
	}
	defer db.Close()

	db.SetMaxOpenConns(25)
	db.SetMaxIdleConns(25)
	db.SetConnMaxLifetime(5 * time.Minute)

	if err := db.Ping(); err != nil {
		log.Error("Failed to ping Postgres database", "err", err)
		os.Exit(1)
	}
	// 2. Initialize Redis Connection
	var rdb *redis.Client
	redisURL := cfg.RedisURL
	if redisURL == "" {
		redisURL = "localhost:6379"
	}
	if opts, err := redis.ParseURL(redisURL); err == nil {
		rdb = redis.NewClient(opts)
	} else {
		rdb = redis.NewClient(&redis.Options{Addr: redisURL})
	}
	defer rdb.Close()
	log.Info("Successfully connected to Redis in User Service")

	eventPublisher := events.NewRedisEventPublisher(rdb)

	// 3. Initialize Repositories
	userRepo := persistence.NewUserRepository(db)

	// 4. Register Routes
	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})

	http.HandleFunc("/api/v1/user/profile", func(w http.ResponseWriter, r *http.Request) {
		userID := r.Header.Get("X-User-Id")
		if userID == "" {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusBadRequest)
			_, _ = w.Write([]byte(`{"error":"missing user id header"}`))
			return
		}

		if r.Method == http.MethodPut || r.Method == http.MethodPost {
			var req struct {
				DisplayName string `json:"display_name"`
				Username    string `json:"username"`
				AvatarURL   string `json:"avatar_url"`
				Bio         string `json:"bio"`
			}
			if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusBadRequest)
				_, _ = w.Write([]byte(`{"error":"invalid request json body"}`))
				return
			}

			updated, err := userRepo.UpdateProfile(r.Context(), userID, req.DisplayName, req.Username, req.AvatarURL, req.Bio)
			if err != nil {
				log.Error("Failed to update user profile", "err", err, "user_id", userID)
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(http.StatusInternalServerError)
				_, _ = w.Write([]byte(`{"error":"failed to update user profile"}`))
				return
			}

			// Publish ProfileUpdatedEvent asynchronously
			go func(u *persistence.UserProfile) {
				pubErr := eventPublisher.PublishProfileUpdated(context.Background(), &events.ProfileUpdatedEvent{
					Type:        "PROFILE_UPDATED",
					UserID:      u.ID,
					Username:    u.Username,
					DisplayName: u.DisplayName,
					AvatarURL:   u.AvatarURL,
					Bio:         u.Bio,
					UpdatedAt:   u.UpdatedAt,
				})
				if pubErr != nil {
					log.Error("Failed to publish ProfileUpdatedEvent", "err", pubErr, "user_id", u.ID)
				} else {
					log.Info("Successfully published ProfileUpdatedEvent to Redis", "user_id", u.ID, "display_name", u.DisplayName)
				}
			}(updated)

			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusOK)
			_ = json.NewEncoder(w).Encode(updated)
			return
		}

		profile, err := userRepo.GetUserByID(r.Context(), userID)
		if err != nil {
			log.Error("Failed to query user profile", "err", err, "user_id", userID)
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusInternalServerError)
			_, _ = w.Write([]byte(`{"error":"internal server error"}`))
			return
		}

		if profile == nil {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusNotFound)
			_, _ = w.Write([]byte(`{"error":"user not found"}`))
			return
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusOK)
		_ = json.NewEncoder(w).Encode(profile)
	})

	serverAddr := fmt.Sprintf(":%d", port)
	log.Info("User HTTP API Server listening", "addr", serverAddr)
	if err := http.ListenAndServe(serverAddr, nil); err != nil {
		log.Error("User HTTP server crashed", "err", err)
		os.Exit(1)
	}
}
