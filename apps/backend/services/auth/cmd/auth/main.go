package main

import (
	"database/sql"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"time"

	_ "github.com/lib/pq"

	"nearby/backend/services/auth/internal/application"
	"nearby/backend/services/auth/internal/infrastructure/cache"
	"nearby/backend/services/auth/internal/infrastructure/persistence"
	transportHTTP "nearby/backend/services/auth/internal/transport/http"
	sharedconfig "nearby/backend/shared/config"
	"nearby/backend/shared/logger"
	"nearby/backend/shared/tracing"
)

func main() {
	log := logger.NewJSONLogger()
	slog.SetDefault(log)

	cfg := sharedconfig.LoadBaseConfig()

	// Port configuration: auth defaults to 8081
	port := cfg.Port
	if port == 8080 { // if it returned the default 8080 because PORT env wasn't set, override to 8081
		port = 8081
	}

	log.Info("Starting Auth Service...", "environment", cfg.Environment, "port", port)

	// Initialize OpenTelemetry tracing
	_, err := tracing.InitTracer("auth-service")
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
	log.Info("Successfully connected to PostgreSQL")

	// 2. Initialize Redis Client
	redisURL := cfg.RedisURL
	if redisURL == "" {
		redisURL = "localhost:6379"
	}
	redisCache, err := cache.NewRedisCache(redisURL, "", 0)
	if err != nil {
		log.Error("Failed to connect to Redis", "err", err)
		os.Exit(1)
	}
	defer redisCache.Close()
	log.Info("Successfully connected to Redis")

	// 3. Initialize Repositories and Adapters
	userRepo := persistence.NewPostgresUserRepository(db)
	sessionRepo := persistence.NewPostgresSessionRepository(db)

	// JWT configuration
	secretEnv := os.Getenv("JWT_SECRET")
	if secretEnv == "" {
		if os.Getenv("APP_ENV") == "production" {
			log.Error("FATAL: JWT_SECRET environment variable is required in production mode")
			os.Exit(1)
		}
		log.Warn("JWT_SECRET not set. Falling back to development test key. DO NOT USE IN PRODUCTION!")
		secretEnv = "test_secret_key"
	}
	secretKey := []byte(secretEnv)

	// 4. Initialize Use Case
	usecase, err := application.NewAuthUsecase(userRepo, sessionRepo, redisCache, secretKey, "easychat")
	if err != nil {
		log.Error("Failed to initialize AuthUsecase", "err", err)
		os.Exit(1)
	}

	// 5. Initialize HTTP Handlers
	authHandler := transportHTTP.NewAuthHandler(usecase)

	// Base health endpoint
	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})
	http.HandleFunc("/api/v1/auth/register", authHandler.Onboard)
	http.HandleFunc("/api/v1/auth/login", authHandler.Login)

	serverAddr := fmt.Sprintf(":%d", port)
	log.Info("Auth HTTP API Server listening", "addr", serverAddr)
	if err := http.ListenAndServe(serverAddr, nil); err != nil {
		log.Error("Auth HTTP server crashed", "err", err)
		os.Exit(1)
	}
}
