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
	"nearby/backend/services/chat/internal/application"
	"nearby/backend/services/chat/internal/infrastructure/cache"
	"nearby/backend/services/chat/internal/infrastructure/kafka"
	"nearby/backend/services/chat/internal/infrastructure/persistence"
	transportws "nearby/backend/services/chat/internal/transport/websocket"
	"nearby/backend/shared/config"
	"nearby/backend/shared/logger"
	"nearby/backend/shared/tracing"
)

func main() {
	log := logger.NewJSONLogger()
	slog.SetDefault(log)

	cfg := config.LoadBaseConfig()

	log.Info("Starting Chat WebSocket Router Service...",
		"environment", cfg.Environment,
		"port", cfg.Port,
	)

	// Initialize OpenTelemetry Tracing
	_, err := tracing.InitTracer("chat-service")
	if err != nil {
		log.Error("Failed to initialize OpenTelemetry tracing", "err", err)
	}

	// 1. Initialize PostgreSQL Connection
	if cfg.DatabaseURL == "" {
		log.Error("DATABASE_URL environment variable is not set")
		os.Exit(1)
	}

	db, err := sql.Open("postgres", cfg.DatabaseURL)
	if err != nil {
		log.Error("Failed to open Postgres database connection", "err", err)
		os.Exit(1)
	}
	defer db.Close()

	// Configure connection pool settings for scalability and low latency
	db.SetMaxOpenConns(25)
	db.SetMaxIdleConns(25)
	db.SetConnMaxLifetime(5 * time.Minute)

	if err := db.Ping(); err != nil {
		log.Error("Failed to ping Postgres database", "err", err)
		os.Exit(1)
	}
	log.Info("Successfully connected to PostgreSQL")

	// 2. Initialize Redis Connection
	var rdb *redis.Client
	if cfg.RedisURL != "" {
		opts, err := redis.ParseURL(cfg.RedisURL)
		if err == nil {
			rdb = redis.NewClient(opts)
		} else {
			// Fallback to direct address if parsing fails
			rdb = redis.NewClient(&redis.Options{
				Addr: cfg.RedisURL,
			})
		}
	} else {
		rdb = redis.NewClient(&redis.Options{
			Addr: "localhost:6379",
		})
	}
	defer rdb.Close()

	// Ping Redis to verify connection
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	if err := rdb.Ping(ctx).Err(); err != nil {
		log.Error("Failed to ping Redis cache server", "err", err)
		os.Exit(1)
	}
	log.Info("Successfully connected to Redis")

	// 3. Initialize Kafka Broker pipeline
	kafkaBrokersEnv := os.Getenv("KAFKA_BROKERS")
	var brokers []string
	if kafkaBrokersEnv != "" {
		brokers = strings.Split(kafkaBrokersEnv, ",")
	} else {
		brokers = []string{"localhost:9092"}
	}
	topic := "chat-messages"
	groupID := "chat-service-group"
	dlqTopic := "chat-messages-dlq"

	pipeline := kafka.NewKafkaPipeline(brokers, topic, groupID, dlqTopic)
	defer pipeline.Close()
	log.Info("Successfully initialized Kafka Event Pipeline", "brokers", brokers)

	// 4. Initialize Repositories and Usecase
	chatRepo := persistence.NewPostgresChatRepository(db)
	roomRepo := persistence.NewPostgresRoomRepository(db)
	requestRepo := persistence.NewPostgresRequestRepository(db)
	cacheRepo := cache.NewRedisCacheRepository(rdb)
	usecase := application.NewChatUsecase(chatRepo, roomRepo, requestRepo, cacheRepo, pipeline)

	// Read secret key for JWT verification
	secretEnv := os.Getenv("JWT_SECRET")
	if secretEnv == "" {
		secretEnv = "test_secret_key"
	}
	secretKey := []byte(secretEnv)

	// 5. Initialize Proximity Validator and WebSocket Server
	proximityValidator := application.NewProximityValidator(rdb, db)
	wsServer := transportws.NewServer(usecase, roomRepo, rdb, secretKey, proximityValidator)

	// 6. Start the Kafka consumer routing loop & ProfileEventSubscriber in the background
	ctxConsumer, cancelConsumer := context.WithCancel(context.Background())
	defer cancelConsumer()
	go wsServer.StartKafkaConsumer(ctxConsumer, pipeline)
	go wsServer.StartProfileEventSubscriber(ctxConsumer)

	// 7. Start HTTP Server for WebSocket connections and REST endpoints
	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})
	http.HandleFunc("/ws", wsServer.HandleWS)
	http.HandleFunc("/api/v1/chat/rooms", wsServer.HandleRooms)
	http.HandleFunc("/api/v1/chat/requests", wsServer.HandleRequests)
	http.HandleFunc("/api/v1/chat/requests/pending", wsServer.HandlePendingRequests)
	http.HandleFunc("/api/v1/chat/requests/status", wsServer.HandleRequestStatus)
	http.HandleFunc("/api/v1/chat/requests/", wsServer.HandleRequestActions)
	http.HandleFunc("/api/v1/chat/keys", wsServer.HandleKeys)
	http.HandleFunc("/api/v1/chat/keys/", wsServer.HandleKeyByUser)
	http.HandleFunc("/api/v1/chat/messages/", wsServer.HandleDeleteMessage)

	addr := fmt.Sprintf(":%d", cfg.Port)
	log.Info("WebSocket Server listening", "addr", addr)
	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Error("HTTP WebSocket server failed", "err", err)
		os.Exit(1)
	}
}
