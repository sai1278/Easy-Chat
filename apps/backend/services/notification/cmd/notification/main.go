package main

import (
	"context"
	"database/sql"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"strings"
	"time"

	_ "github.com/lib/pq"
	"github.com/redis/go-redis/v9"

	"nearby/backend/services/notification/internal/application"
	"nearby/backend/services/notification/internal/domain"
	"nearby/backend/services/notification/internal/infrastructure/persistence"
	"nearby/backend/services/notification/internal/infrastructure/push"
	"nearby/backend/services/notification/internal/infrastructure/queue"
	transportHTTP "nearby/backend/services/notification/internal/transport/http"
	transportKafka "nearby/backend/services/notification/internal/transport/kafka"
	sharedconfig "nearby/backend/shared/config"
	"nearby/backend/shared/logger"
	"nearby/backend/shared/tracing"
)

func main() {
	log := logger.NewJSONLogger()
	slog.SetDefault(log)

	cfg := sharedconfig.LoadBaseConfig()

	log.Info("Starting Notification Service...", "environment", cfg.Environment, "port", cfg.Port)

	// Initialize OpenTelemetry tracing
	_, err := tracing.InitTracer("notification-service")
	if err != nil {
		log.Error("Failed to initialize OpenTelemetry tracing", "err", err)
	}

	// 1. Initialize PostgreSQL Connection
	var db *sql.DB
	if cfg.DatabaseURL != "" {
		d, err := sql.Open("postgres", cfg.DatabaseURL)
		if err != nil {
			log.Error("Failed to open Postgres connection", "err", err)
			os.Exit(1)
		}
		db = d
		defer db.Close()

		db.SetMaxOpenConns(25)
		db.SetMaxIdleConns(25)
		db.SetConnMaxLifetime(5 * time.Minute)

		if err := db.Ping(); err != nil {
			log.Error("Failed to ping Postgres database", "err", err)
			os.Exit(1)
		}
		log.Info("Successfully connected to PostgreSQL")
	} else {
		log.Warn("DATABASE_URL is empty. Continuing in mock preference mode.")
	}

	// 2. Initialize Redis Client
	var redisClient *redis.Client
	redisAddr := os.Getenv("REDIS_ADDR")
	if redisAddr != "" {
		redisClient = redis.NewClient(&redis.Options{
			Addr: redisAddr,
		})
		log.Info("Redis client connected", "addr", redisAddr)
	} else {
		log.Warn("REDIS_ADDR not set. Falling back to local in-memory queueing.")
	}

	// 3. Initialize Repositories and Adapters
	var prefRepo domain.PreferenceRepository
	if db != nil {
		prefRepo = persistence.NewPostgresPreferenceRepository(db)
	} else {
		prefRepo = &mockPreferenceRepository{}
	}

	queueRepo := queue.NewRedisQueueRepository(redisClient)
	pushProvider := push.NewPushProviderAdapter(false)

	// 4. Initialize Use Case
	usecase := application.NewNotificationUsecase(prefRepo, queueRepo, pushProvider)

	// 5. Initialize & Start Kafka Consumer Daemon
	kafkaBrokers := os.Getenv("KAFKA_BROKERS")
	if kafkaBrokers == "" {
		kafkaBrokers = "localhost:9092"
	}
	brokersList := strings.Split(kafkaBrokers, ",")

	consumer := transportKafka.NewNotificationConsumer(
		brokersList,
		"chat-notifications",
		"notification-service-group",
		usecase,
	)
	defer consumer.Close()

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Run Kafka Event daemon in a background routine
	go consumer.Start(ctx)

	// 6. Register HTTP Handlers for user preference endpoints
	prefHandler := transportHTTP.NewPreferenceHandler(prefRepo)
	http.HandleFunc("/preferences", prefHandler.GetPreferencesHandler)
	http.HandleFunc("/preferences/update", prefHandler.UpdatePreferencesHandler)
	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ok"))
	})
	http.HandleFunc("/ready", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ready"))
	})
	http.HandleFunc("/live", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("live"))
	})
	http.HandleFunc("/metrics", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("notification_service_status 1"))
	})

	serverAddr := fmt.Sprintf(":%d", cfg.Port)
	log.Info("Notification HTTP API Server listening", "addr", serverAddr)
	if err := http.ListenAndServe(serverAddr, nil); err != nil {
		log.Error("Notification HTTP server crashed", "err", err)
		os.Exit(1)
	}
}

// Minimal fallback mock in-memory Preference Repository
type mockPreferenceRepository struct {
	pref domain.NotificationPreference
}

func (m *mockPreferenceRepository) SavePreference(ctx context.Context, pref *domain.NotificationPreference) error {
	m.pref = *pref
	return nil
}

func (m *mockPreferenceRepository) GetPreference(ctx context.Context, userID string) (*domain.NotificationPreference, error) {
	return &domain.NotificationPreference{
		UserID:          userID,
		EnablePush:      true,
		QuietHoursStart: "22:00",
		QuietHoursEnd:   "08:00",
	}, nil
}
